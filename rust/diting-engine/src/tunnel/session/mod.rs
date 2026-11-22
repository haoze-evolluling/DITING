mod io;
mod stack;
mod tasks;
mod tcp;
mod udp;

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

use tokio::sync::{mpsc, Semaphore};

use crate::engine::Engine;
use crate::netstack::{Limits, Stats, TcpKey};
use crate::tunnel::link::PacketLink;
use crate::tunnel::queue::{Egress, Events};
use crate::tunnel::stats::TunnelCounters;

pub const INGRESS_QUEUE: usize = 2048;
pub const EGRESS_QUEUE: usize = 2048;
pub(super) const FLOW_CHANNEL: usize = 64;
pub(super) const MAX_DNS_INFLIGHT: usize = 256;

pub(super) type UdpRelays = HashMap<TcpKey, (u64, mpsc::Sender<Vec<u8>>)>;

pub struct Session {
    stop: Arc<AtomicBool>,
    events: Arc<Events>,
    egress: Arc<Egress>,
    link: Arc<dyn PacketLink>,
    counters: Arc<TunnelCounters>,
    stack_stats: Arc<Mutex<Stats>>,
    threads: Vec<JoinHandle<()>>,
}

impl Session {
    pub fn start(engine: Arc<Engine>, link: Arc<dyn PacketLink>) -> Result<Self, String> {
        let mtu = link.mtu().clamp(576, 65535);
        let limits = Limits {
            mtu,
            ..Limits::default()
        };
        let stop = Arc::new(AtomicBool::new(false));
        let events = Arc::new(Events::new(INGRESS_QUEUE));
        let egress = Arc::new(Egress::new(EGRESS_QUEUE));
        let counters = Arc::new(TunnelCounters::default());
        let stack_stats = Arc::new(Mutex::new(Stats::default()));
        let dns_permits = Arc::new(Semaphore::new(MAX_DNS_INFLIGHT));

        let reader = io::spawn_reader(
            Arc::clone(&link),
            Arc::clone(&stop),
            Arc::clone(&events),
            Arc::clone(&counters),
        )?;
        let writer = io::spawn_writer(
            Arc::clone(&link),
            Arc::clone(&stop),
            Arc::clone(&egress),
            Arc::clone(&counters),
        )?;
        let stack = stack::spawn_stack(
            engine,
            Arc::clone(&stop),
            Arc::clone(&events),
            Arc::clone(&egress),
            Arc::clone(&counters),
            Arc::clone(&stack_stats),
            dns_permits,
            limits,
        )?;

        Ok(Self {
            stop,
            events,
            egress,
            link,
            counters,
            stack_stats,
            threads: vec![reader, stack, writer],
        })
    }

    pub fn document(&self) -> serde_json::Value {
        let stats = *self
            .stack_stats
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        self.counters.document(stats)
    }

    pub fn is_running(&self) -> bool {
        !self.stop.load(Ordering::Acquire)
    }

    pub fn stop(mut self) {
        self.shutdown();
    }

    fn shutdown(&mut self) {
        if self.stop.swap(true, Ordering::AcqRel) {
            return;
        }
        self.link.close();
        self.events.close();
        self.egress.close();
        // 栈线程自己持有流任务表，退出时会 `abort_all`，这里只需等它结束。
        for thread in self.threads.drain(..) {
            let _ = thread.join();
        }
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.shutdown();
    }
}
