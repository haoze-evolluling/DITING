//! Subscription-list management (`rule_engine_lists.go`).
//!
//! All methods are asynchronous: fetching is network I/O and index rebuilding is CPU/file I/O. The
//! rebuild itself runs through `tokio::spawn_blocking` and publishes one atomic snapshot swap, so
//! neither work ever blocks the DNS hot path.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use diting_desktop_api::config::FilterList;

use super::engine::now_ms;
use super::types::FilterError;
use super::{fetch, RuleEngine};

impl RuleEngine {
    /// Adds a list, fetches it, then rebuilds the index (`AddFilterList`).
    pub async fn add_list(&self, mut list: FilterList) -> Result<(), FilterError> {
        if list.id.trim().is_empty() {
            list.id = format!("list-{}", now_nanos());
        }
        {
            let config = self.inner.config.read().unwrap();
            if config.lists.iter().any(|existing| existing.id == list.id) {
                return Err(FilterError::DuplicateList(list.id));
            }
        }
        self.inner.config.write().unwrap().lists.push(list.clone());
        self.inner.refresh_list_inner(&list.id).await?;
        self.rebuild_async().await
    }

    /// Updates name/URL/enabled of an existing list (`UpdateFilterList`).
    pub async fn update_list(&self, list: FilterList) -> Result<(), FilterError> {
        if list.url.trim().is_empty() {
            return Err(FilterError::EmptyUrl(list.id));
        }
        {
            let mut config = self.inner.config.write().unwrap();
            let Some(existing) = config.lists.iter_mut().find(|item| item.id == list.id) else {
                return Err(FilterError::ListNotFound(list.id));
            };
            existing.name = list.name;
            existing.url = list.url;
            existing.enabled = list.enabled;
        }
        self.rebuild_async().await
    }

    /// Removes a list and its cache file (`RemoveFilterList`).
    pub async fn delete_list(&self, id: &str) -> Result<(), FilterError> {
        let data_dir;
        {
            let mut config = self.inner.config.write().unwrap();
            let Some(index) = config.lists.iter().position(|item| item.id == id) else {
                return Err(FilterError::ListNotFound(id.to_string()));
            };
            config.lists.remove(index);
            data_dir = config.data_dir.clone();
        }
        let id = id.to_string();
        tokio::task::spawn_blocking(move || fetch::remove_cache(&data_dir, &id))
            .await
            .map_err(|error| FilterError::Join(error.to_string()))?;
        self.rebuild_async().await
    }

    /// Forces one list refresh; rebuilds only when its content changed (`RefreshList`).
    pub async fn refresh_list(&self, id: &str) -> Result<(), FilterError> {
        if self.inner.refresh_list_inner(id).await? {
            self.rebuild_async().await?;
        }
        Ok(())
    }

    /// `RefreshFilterLists`: an empty id refreshes every enabled list.
    pub async fn refresh_lists(&self, id: &str) -> Result<(), FilterError> {
        if id.is_empty() {
            self.refresh_all_lists().await
        } else {
            self.refresh_list(id).await
        }
    }

    /// `RefreshAllLists`.
    pub async fn refresh_all_lists(&self) -> Result<(), FilterError> {
        let ids: Vec<String> = self
            .inner
            .config
            .read()
            .unwrap()
            .lists
            .iter()
            .filter(|list| list.enabled)
            .map(|list| list.id.clone())
            .collect();
        let mut changed = false;
        for id in ids {
            if self.inner.refresh_list_inner(&id).await? {
                changed = true;
            }
        }
        if changed {
            self.rebuild_async().await?;
        }
        Ok(())
    }

    /// Refreshes enabled lists older than `updateIntervalHours`; returns whether anything changed.
    pub async fn refresh_due(&self) -> Result<bool, FilterError> {
        let ids: Vec<String> = {
            let config = self.inner.config.read().unwrap();
            let interval = i64::from(config.update_interval_hours) * 3_600_000;
            let now = now_ms();
            config
                .lists
                .iter()
                .filter(|list| list.enabled)
                .filter(|list| now.saturating_sub(list.last_updated) > interval)
                .map(|list| list.id.clone())
                .collect()
        };
        let mut changed = false;
        for id in ids {
            if self.inner.refresh_list_inner(&id).await? {
                changed = true;
            }
        }
        if changed {
            self.rebuild_async().await?;
        }
        Ok(changed)
    }

    /// Runs the CPU/file-bound rebuild on a blocking pool thread, then swaps the snapshot.
    async fn rebuild_async(&self) -> Result<(), FilterError> {
        let inner = Arc::clone(&self.inner);
        tokio::task::spawn_blocking(move || inner.rebuild_now())
            .await
            .map_err(|error| FilterError::Join(error.to_string()))?;
        Ok(())
    }
}

fn now_nanos() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0)
}
