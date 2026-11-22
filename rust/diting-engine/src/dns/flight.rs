use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use diting_dns_wire::question_key;
use tokio::sync::Notify;

use crate::engine::Engine;

type FlightResult = Option<Result<Vec<u8>, String>>;

#[derive(Clone)]
pub struct Flight {
    result: Arc<Mutex<FlightResult>>,
    notify: Arc<Notify>,
}

impl Flight {
    fn new() -> Self {
        Self {
            result: Arc::new(Mutex::new(None)),
            notify: Arc::new(Notify::new()),
        }
    }

    fn finish(&self, result: Result<Vec<u8>, String>) {
        if let Ok(mut slot) = self.result.lock() {
            *slot = Some(result);
        }
        self.notify.notify_waiters();
    }

    async fn wait(&self) -> Result<Vec<u8>, String> {
        loop {
            let notified = self.notify.notified();
            tokio::pin!(notified);
            // 先注册再检查，避免 finish() 恰好落在检查与 await 之间导致永久挂起。
            notified.as_mut().enable();
            if let Ok(slot) = self.result.lock() {
                if let Some(result) = slot.as_ref() {
                    return result.clone();
                }
            }
            notified.await;
        }
    }
}

pub async fn resolve(engine: &Arc<Engine>, query: &[u8]) -> Result<(Vec<u8>, bool), String> {
    let Some(key) = question_key(query).map(|key| key.key) else {
        return run_resolver(engine, query)
            .await
            .map(|response| (response, false));
    };

    let (flight, leader) = engine.flight(&key);

    if !leader {
        let result = flight.wait().await;
        return result.map(|response| (response, true));
    }

    let mut leader = LeaderGuard {
        flight: flight.clone(),
        engine: Arc::clone(engine),
        key: key.clone(),
        finished: false,
    };
    let result = run_resolver(engine, query).await;
    if let Ok(response) = &result {
        engine.cache().put(query, response);
    }
    flight.finish(result.clone());
    engine.finish_flight(&key);
    leader.finished = true;
    result.map(|response| (response, false))
}

struct LeaderGuard {
    flight: Flight,
    engine: Arc<Engine>,
    key: Vec<u8>,
    finished: bool,
}

impl Drop for LeaderGuard {
    fn drop(&mut self) {
        if self.finished {
            return;
        }
        self.flight.finish(Err("resolution cancelled".to_string()));
        self.engine.finish_flight(&self.key);
    }
}

async fn run_resolver(engine: &Arc<Engine>, query: &[u8]) -> Result<Vec<u8>, String> {
    let resolver = engine.resolver();
    let (result, race) = resolver.resolve(query).await;
    if let Some(mut event) = race {
        let info = diting_dns_core::message::query_info(query);
        event.query_name = info.name;
        event.query_type = info.qtype;
        engine.logs().race(event);
    }
    result
}

impl Engine {
    pub(crate) fn flight(&self, key: &[u8]) -> (Flight, bool) {
        let mut flights: std::sync::MutexGuard<'_, HashMap<Vec<u8>, Flight>> = self
            .flights()
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        match flights.get(key) {
            Some(flight) => (flight.clone(), false),
            None => {
                let flight = Flight::new();
                flights.insert(key.to_vec(), flight.clone());
                (flight, true)
            }
        }
    }

    pub(crate) fn finish_flight(&self, key: &[u8]) {
        let mut flights = self
            .flights()
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        flights.remove(key);
    }
}
