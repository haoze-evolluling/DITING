use std::sync::atomic::Ordering;
use std::sync::Arc;

use crate::error::EngineResult;
use crate::logs::EventSink;

use super::Engine;

impl Engine {
    pub fn set_event_sink(&self, sink: Option<Arc<dyn EventSink>>) {
        self.logs.set_sink(sink);
    }

    pub fn start_standalone(self: &Arc<Self>, port: u16) -> EngineResult<()> {
        self.start_standalone_on(port, false)
    }

    pub fn start_standalone_loopback(self: &Arc<Self>, port: u16) -> EngineResult<()> {
        self.start_standalone_on(port, true)
    }

    fn start_standalone_on(self: &Arc<Self>, port: u16, loopback: bool) -> EngineResult<()> {
        let mut server = self
            .server
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(existing) = server.take() {
            existing.stop();
        }
        let started = if loopback {
            crate::standalone::start_loopback(Arc::clone(self), port)?
        } else {
            crate::standalone::start(Arc::clone(self), port)?
        };
        *server = Some(started);
        self.running.store(true, Ordering::Release);
        Ok(())
    }

    pub fn stop_standalone(&self) {
        let mut server = self
            .server
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(started) = server.take() {
            started.stop();
        }
        self.running.store(false, Ordering::Release);
    }

    pub fn stop(&self) {
        self.stop_standalone();
        self.stop_full();
        self.cache.clear();
    }

    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Acquire) || self.is_full_running()
    }

    pub fn started_at_ms(&self) -> i64 {
        self.started_at_ms
    }

    pub fn standalone_port(&self) -> Option<u16> {
        self.server
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(|server| server.port())
    }
}
