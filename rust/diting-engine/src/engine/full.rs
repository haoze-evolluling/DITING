use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use crate::error::EngineError;
use crate::tunnel::{PacketLink, Session, TunFd};

use super::{Engine, TrafficSink, DEFAULT_TUN_MTU};

impl Engine {
    pub fn traffic(&self) -> &Arc<diting_telemetry_core::TrafficTracker> {
        &self.traffic
    }

    pub fn set_traffic_sink(&self, sink: Option<Arc<dyn TrafficSink>>) {
        *self
            .traffic_sink
            .write()
            .unwrap_or_else(|error| error.into_inner()) = sink;
    }

    pub fn set_tick_interval_ms(&self, millis: i64) {
        if millis <= 0 {
            return;
        }
        self.tick_interval_ms
            .store(millis as u64, Ordering::Release);
    }

    pub(super) fn traffic_sink(&self) -> Option<Arc<dyn TrafficSink>> {
        self.traffic_sink
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn start_full(self: &Arc<Self>, fd: i32) -> crate::error::EngineResult<()> {
        let link = TunFd::open(fd, DEFAULT_TUN_MTU).map_err(|error| {
            EngineError::state(format!("StartFull: dup TUN fd {fd} failed: {error}"))
        })?;
        self.start_full_with_link(Arc::new(link))
    }

    pub fn start_full_with_link(
        self: &Arc<Self>,
        link: Arc<dyn PacketLink>,
    ) -> crate::error::EngineResult<()> {
        let mut slot = self.full.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(session) = slot.as_ref() {
            if session.is_running() {
                return Ok(());
            }
        }
        self.connlog.reset();
        if let Ok(mut flows) = self.flows.lock() {
            flows.reset();
        }
        self.total_queries.store(0, Ordering::Relaxed);
        self.blocked_queries.store(0, Ordering::Relaxed);
        let session = Session::start(Arc::clone(self), link).map_err(EngineError::state)?;
        *slot = Some(session);
        drop(slot);
        let outbound = self.outbound();
        if outbound.config().enabled() {
            outbound.report("connecting", "");
        } else {
            outbound.report("disabled", "");
        }
        self.start_traffic_ticker();
        Ok(())
    }

    pub fn stop_full(&self) {
        let session = {
            let mut slot = self.full.lock().unwrap_or_else(|error| error.into_inner());
            slot.take()
        };
        if let Some(session) = session {
            session.stop();
        }
        self.stop_traffic_ticker();
    }

    /// 网络切换后立即下线旧链路上的所有数据面连接。
    ///
    /// 引擎持有的上游 socket 在切换后不会收到 RST，`write` 会一直挂起；这里主动
    /// 中止所有 TCP/UDP 流，应用会收到 RST 并在新链路上重新建连。
    pub fn reset_data_plane(&self) {
        let slot = self.full.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(session) = slot.as_ref() {
            session.abort_all();
        }
    }

    pub fn is_full_running(&self) -> bool {
        self.full
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(Session::is_running)
            .unwrap_or(false)
    }

    pub fn tun_document(&self) -> Option<serde_json::Value> {
        self.full
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(Session::document)
    }

    pub fn note_query(&self, blocked: bool) {
        self.total_queries.fetch_add(1, Ordering::Relaxed);
        if blocked {
            self.blocked_queries.fetch_add(1, Ordering::Relaxed);
        }
    }

    pub fn total_queries(&self) -> u64 {
        self.total_queries.load(Ordering::Relaxed)
    }

    pub fn blocked_queries(&self) -> u64 {
        self.blocked_queries.load(Ordering::Relaxed)
    }

    fn start_traffic_ticker(self: &Arc<Self>) {
        let running = Arc::new(AtomicBool::new(true));
        {
            let mut slot = self
                .ticker
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if let Some(previous) = slot.take() {
                previous.store(false, Ordering::Release);
            }
            *slot = Some(Arc::clone(&running));
        }
        let engine = Arc::clone(self);
        self.spawn(async move {
            loop {
                let interval = engine.tick_interval_ms.load(Ordering::Acquire).max(100);
                tokio::time::sleep(Duration::from_millis(interval)).await;
                if !running.load(Ordering::Acquire) {
                    return;
                }
                let deltas = engine.traffic.tick();
                if let Some(sink) = engine.traffic_sink() {
                    let now = crate::resolver::now_ns();
                    let rows: Vec<(i32, i64, i64, String)> = deltas
                        .iter()
                        .map(|delta| {
                            (
                                delta.uid,
                                delta.tx as i64,
                                delta.rx as i64,
                                engine.attribution().package_for(delta.uid, now),
                            )
                        })
                        .collect();
                    sink.tick(&crate::tunnel::stats::traffic_payload(&rows));
                }
            }
        });
    }

    fn stop_traffic_ticker(&self) {
        let running = {
            let mut slot = self
                .ticker
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            slot.take()
        };
        if let Some(running) = running {
            running.store(false, Ordering::Release);
        }
    }
}
