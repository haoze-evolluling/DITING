use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;

use crate::tunnel::link::{LinkFault, PacketLink};
use crate::tunnel::queue::{Egress, Events};
use crate::tunnel::stats::TunnelCounters;

const WRITE_ATTEMPTS: u32 = 40;
const WRITE_BASE_WAIT: Duration = Duration::from_millis(5);
const WRITE_MAX_WAIT: Duration = Duration::from_millis(100);
const READER_BACKOFF_BASE: Duration = Duration::from_millis(1);
const READER_BACKOFF_MAX: Duration = Duration::from_millis(200);

pub(super) fn spawn_reader(
    link: Arc<dyn PacketLink>,
    stop: Arc<AtomicBool>,
    events: Arc<Events>,
    counters: Arc<TunnelCounters>,
) -> Result<JoinHandle<()>, String> {
    thread::Builder::new()
        .name("diting-tun-reader".to_string())
        .spawn(move || {
            let mut buffer = vec![0u8; link.mtu() + 1];
            let mut backoff = READER_BACKOFF_BASE;
            while !stop.load(Ordering::Acquire) {
                match link.recv(&mut buffer) {
                    Ok(read) => {
                        if read == 0 || read > link.mtu() {
                            continue;
                        }
                        backoff = READER_BACKOFF_BASE;
                        events.push_packet(buffer[..read].to_vec());
                    }
                    Err(LinkFault::Again) => {}
                    Err(LinkFault::Backoff) => {
                        thread::sleep(backoff);
                        backoff = (backoff * 2).min(READER_BACKOFF_MAX);
                    }
                    Err(LinkFault::Fatal) => break,
                }
            }
            counters
                .ingress_dropped
                .store(events.dropped(), Ordering::Relaxed);
        })
        .map_err(|error| format!("TUN reader thread: {error}"))
}

pub(super) fn spawn_writer(
    link: Arc<dyn PacketLink>,
    stop: Arc<AtomicBool>,
    egress: Arc<Egress>,
    counters: Arc<TunnelCounters>,
) -> Result<JoinHandle<()>, String> {
    thread::Builder::new()
        .name("diting-tun-writer".to_string())
        .spawn(move || {
            let mut healthy = true;
            let mut backoff = WRITE_BASE_WAIT;
            while !stop.load(Ordering::Acquire) {
                let Some(packet) = egress.pop(Duration::from_millis(200)) else {
                    continue;
                };
                if !write_packet(
                    link.as_ref(),
                    &packet,
                    &stop,
                    &counters,
                    &mut healthy,
                    &mut backoff,
                ) {
                    return;
                }
            }
        })
        .map_err(|error| format!("TUN writer thread: {error}"))
}

fn write_packet(
    link: &dyn PacketLink,
    packet: &[u8],
    stop: &AtomicBool,
    counters: &TunnelCounters,
    healthy: &mut bool,
    backoff: &mut Duration,
) -> bool {
    let attempts = if *healthy { WRITE_ATTEMPTS } else { 1 };
    for attempt in 1..=attempts {
        match link.send(packet) {
            Ok(()) => {
                *healthy = true;
                *backoff = WRITE_BASE_WAIT;
                return true;
            }
            Err(LinkFault::Fatal) => {
                counters.write_failures.fetch_add(1, Ordering::Relaxed);
                return false;
            }
            Err(LinkFault::Again) | Err(LinkFault::Backoff) => {}
        }
        if attempt == attempts {
            *healthy = false;
            counters.write_failures.fetch_add(1, Ordering::Relaxed);
            return true;
        }
        if stop.load(Ordering::Acquire) {
            return false;
        }
        counters.write_retries.fetch_add(1, Ordering::Relaxed);
        thread::sleep(*backoff);
        *backoff = (*backoff * 2).min(WRITE_MAX_WAIT);
    }
    true
}
