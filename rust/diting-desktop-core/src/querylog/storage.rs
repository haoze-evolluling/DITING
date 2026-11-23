use std::io;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use super::reader;
use super::types::{Config, Record, SearchQuery, SearchResult};
use super::writer::Writer;

/// 查询日志的持久化后端。文件后端保持旧行为，桌面 SQLite 模式注入数据库实现。
pub trait QueryLogStorage: Send + Sync {
    fn append(&self, record: Record) -> bool;

    /// SQLite 等权威后端返回完整结果；文件后端返回 `None`，由 `QueryLog` 合并内存环。
    fn search(&self, query: &SearchQuery) -> Option<SearchResult>;

    /// 文件后端在内存环之后继续搜索旧记录；数据库后端不需要。
    fn search_older(
        &self,
        query: &SearchQuery,
        mem_total: i64,
        mem_oldest: i64,
    ) -> (Vec<Record>, i64);

    /// 启动时回填内存环与 24 小时统计。
    fn recent(&self, since_ms: i64, limit: usize) -> Vec<Record>;

    fn configure(&self, config: &Config);
    fn clear(&self) -> io::Result<()>;
    fn close(&self) -> io::Result<()>;
    fn is_persistent(&self) -> bool;
}

struct FileInner {
    writer: Option<Arc<Writer>>,
    file_ok: bool,
}

pub struct FileQueryLogStorage {
    inner: RwLock<FileInner>,
}

impl FileQueryLogStorage {
    pub fn new(config: &Config) -> Self {
        let (writer, file_ok) = build_writer(config);
        Self {
            inner: RwLock::new(FileInner { writer, file_ok }),
        }
    }
}

impl QueryLogStorage for FileQueryLogStorage {
    fn append(&self, record: Record) -> bool {
        let writer = self
            .inner
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .writer
            .clone();
        match writer {
            Some(writer) => writer.enqueue(record),
            None => false,
        }
    }

    fn search(&self, _query: &SearchQuery) -> Option<SearchResult> {
        None
    }

    fn search_older(
        &self,
        query: &SearchQuery,
        mem_total: i64,
        mem_oldest: i64,
    ) -> (Vec<Record>, i64) {
        let writer = self
            .inner
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .writer
            .clone();
        match writer {
            Some(writer) => reader::search_files(writer.dir(), query, mem_total, mem_oldest),
            None => (Vec::new(), 0),
        }
    }

    fn recent(&self, _since_ms: i64, _limit: usize) -> Vec<Record> {
        Vec::new()
    }

    fn configure(&self, config: &Config) {
        let stale = {
            let mut inner = self
                .inner
                .write()
                .unwrap_or_else(|error| error.into_inner());
            let need_reinit = inner.writer.is_none() != !config.file_enabled
                || inner.writer.as_ref().is_some_and(|writer| {
                    writer.dir() != Path::new(&config.data_dir)
                        || writer.retention_days() != config.retention_days
                });
            if !need_reinit {
                return;
            }
            inner.file_ok = false;
            inner.writer.take()
        };

        if let Some(writer) = stale {
            let _ = writer.close();
        }
        let (writer, file_ok) = build_writer(config);
        let mut inner = self
            .inner
            .write()
            .unwrap_or_else(|error| error.into_inner());
        inner.writer = writer;
        inner.file_ok = file_ok;
    }

    fn clear(&self) -> io::Result<()> {
        let (writer, file_ok) = {
            let inner = self.inner.read().unwrap_or_else(|error| error.into_inner());
            (inner.writer.clone(), inner.file_ok)
        };
        if !file_ok {
            return Ok(());
        }
        match writer {
            Some(writer) => writer.clear(),
            None => Ok(()),
        }
    }

    fn close(&self) -> io::Result<()> {
        let writer = {
            let mut inner = self
                .inner
                .write()
                .unwrap_or_else(|error| error.into_inner());
            inner.file_ok = false;
            inner.writer.take()
        };
        match writer {
            Some(writer) => writer.close(),
            None => Ok(()),
        }
    }

    fn is_persistent(&self) -> bool {
        self.inner
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .file_ok
    }
}

fn build_writer(config: &Config) -> (Option<Arc<Writer>>, bool) {
    if !config.file_enabled {
        return (None, false);
    }
    match Writer::new(PathBuf::from(&config.data_dir), config.retention_days) {
        Ok(writer) => (Some(Arc::new(writer)), true),
        Err(_) => (None, false),
    }
}
