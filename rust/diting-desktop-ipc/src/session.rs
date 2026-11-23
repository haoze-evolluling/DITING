use crate::auth::SessionInfo;

/// 管理端会话的可选持久化后端。内存仍是鉴权热路径，存储只用于重启恢复。
pub trait SessionStore: Send + Sync {
    fn load(&self) -> Vec<SessionInfo>;
    fn insert(&self, session: &SessionInfo);
    fn remove(&self, token: &str);
    fn clear(&self);
    fn prune(&self, now_unix: i64);
}
