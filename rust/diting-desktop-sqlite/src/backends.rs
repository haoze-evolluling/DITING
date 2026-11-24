use std::sync::Arc;

use diting_desktop_app::RuntimeStores;
use diting_desktop_core::querylog::Config as QueryLogConfig;

use crate::{
    RoutedSqliteQueryLogStorage, SqliteCachePersistence, SqliteConfigStore, SqliteDb,
    SqliteListCache, SqliteSessionStore, SqliteStateStore,
};

pub fn runtime_stores(db: Arc<SqliteDb>, querylog: &QueryLogConfig) -> RuntimeStores {
    RuntimeStores {
        backend: "sqlite",
        config: Arc::new(SqliteConfigStore::new(Arc::clone(&db))),
        querylog: Some(Arc::new(RoutedSqliteQueryLogStorage::new(
            Arc::clone(&db),
            querylog,
        ))),
        list_cache: Arc::new(SqliteListCache::new(Arc::clone(&db))),
        cache: Arc::new(SqliteCachePersistence::new(Arc::clone(&db))),
    }
}

pub fn state_store(db: Arc<SqliteDb>) -> SqliteStateStore {
    SqliteStateStore::new(db)
}

pub fn session_store(db: Arc<SqliteDb>) -> SqliteSessionStore {
    SqliteSessionStore::new(db)
}
