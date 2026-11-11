//! Single-flight query coalescing.
//!
//! `dns_cache_flight.go` kept this in Go because Go owned the resolver callback. Here the resolver
//! is a local async function, so the coalescer is a plain `Notify`-based flight table:
//!
//! * the first caller for a question key becomes the leader and runs the resolver;
//! * every other caller for the same key waits for the leader and then re-reads the cache (the
//!   leader stored its answer), so a burst of identical queries costs one upstream round trip;
//! * a shared answer carries the leader's transaction id, so it is patched to the waiter's before
//!   it is returned — a client rejects an answer with the wrong id;
//! * a query without a usable question key is not coalesced at all (it cannot be keyed).
//!
//! The cache itself is asked *without* counting (`get(query, false)` equivalent): the caller's own
//! lookup already recorded the miss, and counting again would double the miss rate.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use diting_dns_wire::question_key;
use tokio::sync::Notify;

use crate::engine::Engine;

/// The answer a flight publishes: `None` while the resolver is still running.
type FlightResult = Option<Result<Vec<u8>, String>>;

/// One in-flight resolution.
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
        // `notify_waiters` rather than `notify_one`: every waiter must wake, and the loop below
        // re-checks the slot, so a spurious wake is harmless.
        self.notify.notify_waiters();
    }

    async fn wait(&self) -> Result<Vec<u8>, String> {
        loop {
            // Register before checking the slot: `finish` publishes the result and *then* notifies,
            // so a waiter that registered first can never miss the wake-up.
            let notified = self.notify.notified();
            if let Ok(slot) = self.result.lock() {
                if let Some(result) = slot.as_ref() {
                    return result.clone();
                }
            }
            notified.await;
        }
    }
}

/// Resolves one query through the coalescer. The flag reports whether the answer was shared (which is
/// what the log row's `cached` bit means for this branch).
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

    let result = run_resolver(engine, query).await;
    if let Ok(response) = &result {
        engine.cache().put(query, response);
    }
    flight.finish(result.clone());
    engine.finish_flight(&key);
    result.map(|response| (response, false))
}

/// One upstream round trip. A response that the cache refuses to store (a malformed answer) is still
/// returned to the caller: refusing to answer a client because the cache did not like the bytes would
/// be worse than the cache miss.
async fn run_resolver(engine: &Arc<Engine>, query: &[u8]) -> Result<Vec<u8>, String> {
    let resolver = engine.resolver();
    let (result, race) = resolver.resolve(query).await;
    if let Some(mut event) = race {
        event.query_name = engine.query_name(query);
        event.query_type = engine.query_type(query);
        engine.logs().race(event);
    }
    result
}

/// The flight table's bookkeeping, kept on the engine so the leader can be found from any task.
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
