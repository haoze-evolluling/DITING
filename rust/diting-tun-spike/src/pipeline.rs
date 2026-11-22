use std::net::{SocketAddr, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{sync_channel, TrySendError};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

use crate::callback::Dispatcher;
use crate::io::{Fault, PacketSource};
use crate::protector::{Connector, Evidence, Protector};
use crate::stats::{ConnectionState, Counters};

pub const DEFAULT_QUEUE_CAPACITY: usize = 2048;
pub const DEFAULT_CALLBACK_CAPACITY: usize = 1024;
pub const MAX_BACKOFF: Duration = Duration::from_millis(200);

#[derive(Debug, Clone)]
pub struct Config {
    pub mtu: usize,
    pub queue_capacity: usize,
    pub target: SocketAddr,
}

impl Config {
    pub fn new(target: SocketAddr, mtu: usize) -> Config {
        Config {
            mtu,
            queue_capacity: DEFAULT_QUEUE_CAPACITY,
            target,
        }
    }
}

#[derive(Default)]
struct Stop {
    flag: AtomicBool,
    lock: Mutex<()>,
    ready: Condvar,
}

impl Stop {
    fn set(&self) {
        self.flag.store(true, Ordering::SeqCst);
        self.ready.notify_all();
    }

    fn is_set(&self) -> bool {
        self.flag.load(Ordering::SeqCst)
    }

    fn sleep(&self, duration: Duration) -> bool {
        let guard = self.lock.lock().unwrap_or_else(|err| err.into_inner());
        if self.is_set() {
            return true;
        }
        let _unused = self
            .ready
            .wait_timeout(guard, duration)
            .unwrap_or_else(|err| err.into_inner());
        self.is_set()
    }
}

pub struct Running {
    pub counters: Arc<Counters>,
    pub evidence: Arc<Evidence>,
    pub connection: Arc<ConnectionState>,
    callbacks: Arc<Dispatcher>,
    stop: Arc<Stop>,
    source: Arc<dyn PacketSource>,
    error: Arc<Mutex<Option<String>>>,
    reader: Mutex<Option<JoinHandle<()>>>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

impl Running {
    pub fn error(&self) -> Option<String> {
        self.error
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .clone()
    }

    pub fn callbacks(&self) -> Arc<Dispatcher> {
        self.callbacks.clone()
    }

    pub fn stop(&self) {
        self.stop.set();
        self.source.wake();
        if let Some(handle) = self
            .reader
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .take()
        {
            let _ = handle.join();
        }
        if let Some(handle) = self
            .worker
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .take()
        {
            let _ = handle.join();
        }
        self.callbacks.stop();
    }
}

impl Drop for Running {
    fn drop(&mut self) {
        self.stop();
    }
}

pub fn start(
    source: Arc<dyn PacketSource>,
    protector: Arc<dyn Protector>,
    config: Config,
    callbacks: Arc<Dispatcher>,
) -> Result<Running, String> {
    let counters = Arc::new(Counters::default());
    let evidence = Arc::new(Evidence::default());
    let connection = Arc::new(ConnectionState::default());
    let error = Arc::new(Mutex::new(None));
    let stop = Arc::new(Stop::default());
    let (tx, rx) = sync_channel::<Vec<u8>>(config.queue_capacity.max(1));

    let reader = {
        let source = source.clone();
        let counters = counters.clone();
        let stop = stop.clone();
        let mtu = config.mtu.max(64);
        std::thread::Builder::new()
            .name("diting-tun-reader".to_string())
            .spawn(move || read_loop(source, tx, counters, stop, mtu))
            .map_err(|err| format!("spawn the TUN reader: {err}"))?
    };

    let worker = {
        let counters = counters.clone();
        let evidence = evidence.clone();
        let connection = connection.clone();
        let error = error.clone();
        let stop = stop.clone();
        let callbacks = callbacks.clone();
        let connector = Connector::new(protector, config.target, evidence.clone());
        std::thread::Builder::new()
            .name("diting-tun-worker".to_string())
            .spawn(move || worker_loop(rx, connector, callbacks, counters, connection, error, stop))
            .map_err(|err| format!("spawn the TUN worker: {err}"))?
    };

    Ok(Running {
        counters,
        evidence,
        connection,
        callbacks,
        stop,
        source,
        error,
        reader: Mutex::new(Some(reader)),
        worker: Mutex::new(Some(worker)),
    })
}

fn read_loop(
    source: Arc<dyn PacketSource>,
    tx: std::sync::mpsc::SyncSender<Vec<u8>>,
    counters: Arc<Counters>,
    stop: Arc<Stop>,
    mtu: usize,
) {
    let mut buf = vec![0u8; mtu];
    let mut backoff = Duration::from_millis(1);
    while !stop.is_set() {
        match source.recv(&mut buf) {
            Ok(length) => {
                backoff = Duration::from_millis(1);
                counters.read.fetch_add(1, Ordering::SeqCst);
                counters.bytes_in.fetch_add(length as u64, Ordering::SeqCst);
                match tx.try_send(buf[..length].to_vec()) {
                    Ok(()) => {}
                    Err(TrySendError::Full(_)) => {
                        counters.dropped.fetch_add(1, Ordering::SeqCst);
                    }
                    Err(TrySendError::Disconnected(_)) => break,
                }
            }
            Err(Fault::Again) => {
                counters.retries.fetch_add(1, Ordering::SeqCst);
                if stop.sleep(Duration::from_micros(200)) {
                    break;
                }
            }
            Err(Fault::Backoff) => {
                counters.backoffs.fetch_add(1, Ordering::SeqCst);
                let wait = backoff;
                backoff = (backoff * 2).min(MAX_BACKOFF);
                if stop.sleep(wait) {
                    break;
                }
            }
            Err(Fault::Fatal) => break,
        }
    }
}

fn worker_loop(
    queue: std::sync::mpsc::Receiver<Vec<u8>>,
    connector: Connector,
    callbacks: Arc<Dispatcher>,
    counters: Arc<Counters>,
    connection: Arc<ConnectionState>,
    error: Arc<Mutex<Option<String>>>,
    stop: Arc<Stop>,
) {
    let mut stream: Option<TcpStream> = None;
    let mut sequence: u64 = 0;
    while let Ok(packet) = queue.recv() {
        if stop.is_set() {
            break;
        }
        if stream.is_none() {
            match connector.connect() {
                Ok(connected) => {
                    connection.set(true);
                    stream = Some(connected);
                }
                Err(message) => {
                    *error.lock().unwrap_or_else(|err| err.into_inner()) = Some(message);
                    connection.set(false);
                    stop.set();
                    break;
                }
            }
        }

        use std::io::Write;
        let upstream = stream.as_mut().expect("connected above");
        if let Err(err) = upstream.write_all(&packet) {
            counters.write_failures.fetch_add(1, Ordering::SeqCst);
            *error.lock().unwrap_or_else(|err| err.into_inner()) =
                Some(format!("write to the upstream socket: {err}"));
            stream = None;
            connection.set(false);
            continue;
        }

        sequence += 1;
        let payload = format!(r#"{{"seq":{sequence},"len":{}}}"#, packet.len());
        if callbacks.dispatch(payload) {
            counters.events.fetch_add(1, Ordering::SeqCst);
        }
    }
    connection.set(false);
}
