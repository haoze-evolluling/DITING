//! Reader for the `.dtri` subscription rule index (`policy_dtri_reader.go`).
//!
//! The file format is owned by [`crate::`]s sibling crate `diting-rule-core::dtri` (the writer) and
//! pinned byte for byte against the Kotlin/JVM reference, so this port only has to reproduce the
//! Go read path: header parse, bloom prefilter, then a label-by-label walk from the TLD down.
//!
//! Differences that cannot change a decision on a well-formed file:
//! * every slice access is bounds checked, so a truncated/corrupt index is a miss instead of a Go
//!   panic;
//! * the file is memory mapped once per path and shared through [`open_shared`] (Go keeps one
//!   reader per path in `policyEngine.currentTries` and delays the close by two seconds; reference
//!   counting replaces that delay because a snapshot keeps its readers alive).

use std::collections::HashMap;
use std::fs::File;
use std::path::Path;
use std::sync::{Arc, Mutex, OnceLock, Weak};

use memmap2::Mmap;

const MAGIC: u32 = 0x4454_5249;
const VERSION: u32 = 1;
const HEADER_SIZE: usize = 36;
const NODE_SIZE: usize = 12;
const EDGE_SIZE: usize = 12;

/// A mapped `.dtri` index. Cheap to clone behind an `Arc`, immutable once mapped.
pub struct DtriReader {
    _file: File,
    map: Mmap,
    file_path: String,
    mod_time: i64,
    size: u64,
    sources: usize,
    bloom_bits: i64,
    bloom_bytes: usize,
    node_offset: usize,
    edge_offset: usize,
    label_offset: usize,
    source_names: Vec<String>,
}

fn be_u32(data: &[u8], offset: usize) -> Option<u32> {
    let slice = data.get(offset..offset + 4)?;
    Some(u32::from_be_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

impl DtriReader {
    /// `openDTRI`.
    pub fn open(path: &str) -> Result<DtriReader, String> {
        if path.is_empty() {
            return Err("empty path".to_string());
        }
        let file = File::open(Path::new(path))
            .map_err(|error| format!("failed to open DTRI file {path}: {error}"))?;
        let metadata = file
            .metadata()
            .map_err(|error| format!("failed to stat DTRI file {path}: {error}"))?;
        let size = metadata.len();
        if size < HEADER_SIZE as u64 {
            return Err(format!("file {path} too small to be a valid DTRI"));
        }
        // SAFETY: the mapping is read-only and the file is ours; a concurrently rewritten index is
        // written through a temporary file and renamed, so the mapped bytes stay valid.
        let map = unsafe { Mmap::map(&file) }
            .map_err(|error| format!("mmap failed for {path}: {error}"))?;
        let data: &[u8] = &map;

        let magic = be_u32(data, 0).ok_or_else(|| format!("corrupted DTRI file {path}"))?;
        if magic != MAGIC {
            return Err(format!(
                "invalid DTRI magic: expected {MAGIC:X}, got {magic:X}"
            ));
        }
        let version = be_u32(data, 4).ok_or_else(|| format!("corrupted DTRI file {path}"))?;
        if version != VERSION {
            return Err(format!(
                "invalid DTRI version: expected {VERSION}, got {version}"
            ));
        }
        let nodes = be_u32(data, 8).unwrap_or(0) as usize;
        let edges = be_u32(data, 12).unwrap_or(0) as usize;
        let sources = be_u32(data, 16).unwrap_or(0) as usize;
        let bloom_bits = be_u32(data, 20).unwrap_or(0) as i64;
        let bloom_bytes = be_u32(data, 24).unwrap_or(0) as usize;
        let labels_bytes = be_u32(data, 28).unwrap_or(0) as usize;
        let sources_bytes = be_u32(data, 32).unwrap_or(0) as usize;

        let node_offset = HEADER_SIZE
            .checked_add(bloom_bytes)
            .ok_or_else(|| format!("corrupted DTRI file {path}"))?;
        let edge_offset = nodes
            .checked_mul(NODE_SIZE)
            .and_then(|span| node_offset.checked_add(span))
            .ok_or_else(|| format!("corrupted DTRI file {path}"))?;
        let label_offset = edges
            .checked_mul(EDGE_SIZE)
            .and_then(|span| edge_offset.checked_add(span))
            .ok_or_else(|| format!("corrupted DTRI file {path}"))?;
        let source_offset = label_offset
            .checked_add(labels_bytes)
            .ok_or_else(|| format!("corrupted DTRI file {path}"))?;
        let source_end = source_offset
            .checked_add(sources_bytes)
            .ok_or_else(|| format!("corrupted DTRI file {path}"))?;
        if source_end > data.len() || HEADER_SIZE + bloom_bytes > data.len() {
            return Err(format!("corrupted DTRI file {path}"));
        }

        let mut source_names = vec![String::new(); sources];
        let mut cursor = source_offset;
        for name in source_names.iter_mut() {
            let Some(length) = be_u32(data, cursor) else {
                break;
            };
            cursor += 4;
            let end = cursor.saturating_add(length as usize);
            let Some(bytes) = data.get(cursor..end) else {
                break;
            };
            *name = String::from_utf8_lossy(bytes).into_owned();
            cursor = end;
        }

        let mod_time = metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|delta| delta.as_nanos() as i64)
            .unwrap_or(0);

        Ok(DtriReader {
            _file: file,
            map,
            file_path: path.to_string(),
            mod_time,
            size,
            sources,
            bloom_bits,
            bloom_bytes,
            node_offset,
            edge_offset,
            label_offset,
            source_names,
        })
    }

    fn data(&self) -> &[u8] {
        &self.map
    }

    fn compare_edge(
        &self,
        edge_index: usize,
        domain: &[u8],
        start: usize,
        end: usize,
    ) -> Option<i32> {
        let data = self.data();
        let base = self
            .edge_offset
            .checked_add(edge_index.checked_mul(EDGE_SIZE)?)?;
        let offset = be_u32(data, base)? as usize;
        let length = be_u32(data, base + 4)? as usize;
        let target_len = end.checked_sub(start)?;
        let min_len = target_len.min(length);
        let label_base = self.label_offset.checked_add(offset)?;
        let label = data.get(label_base..label_base.checked_add(length)?)?;
        let target = domain.get(start..end)?;
        for i in 0..min_len {
            let left = *target.get(i)? as i32;
            let right = *label.get(i)? as i32;
            if left != right {
                return Some(left - right);
            }
        }
        Some(target_len as i32 - length as i32)
    }

    fn find_child(&self, node: usize, domain: &[u8], start: usize, end: usize) -> Option<usize> {
        let data = self.data();
        let base = self.node_offset.checked_add(node.checked_mul(NODE_SIZE)?)?;
        let first = be_u32(data, base + 4)? as usize;
        let count = be_u32(data, base + 8)? as usize;
        if count == 0 {
            return None;
        }
        let mut low = first as i64;
        let mut high = (first + count) as i64 - 1;
        while low <= high {
            let mid = ((low + high) >> 1) as usize;
            let cmp = self.compare_edge(mid, domain, start, end)?;
            if cmp < 0 {
                high = mid as i64 - 1;
            } else if cmp > 0 {
                low = mid as i64 + 1;
            } else {
                let edge_base = self.edge_offset.checked_add(mid.checked_mul(EDGE_SIZE)?)?;
                return Some(be_u32(data, edge_base + 8)? as usize);
            }
        }
        None
    }

    /// `dtriHashes`: two FNV-ish 64-bit hashes over `val[start..end]`, wrapping like Go's int64.
    fn hashes(value: &[u8], start: usize, end: usize) -> (i64, i64) {
        let mut h1: i64 = -3750763034362895579;
        let mut h2: i64 = -3750763034362895579;
        for byte in value.get(start..end).unwrap_or(&[]) {
            let b = *byte as i64 & 0xff;
            h1 = (h1 ^ b).wrapping_mul(1099511628211);
            h2 = h2.wrapping_mul(1099511628211) ^ b;
        }
        (h1, h2 | 1)
    }

    /// `mightContainDomainOrParent`: bloom prefilter over the domain and every parent label.
    fn might_contain_domain_or_parent(&self, domain: &[u8]) -> bool {
        if self.bloom_bits <= 0 || self.bloom_bytes == 0 {
            return true;
        }
        let bloom = match self.data().get(HEADER_SIZE..HEADER_SIZE + self.bloom_bytes) {
            Some(slice) => slice,
            None => return true,
        };
        let modulo = self.bloom_bits;
        let mut start = 0usize;
        while start < domain.len() {
            let (h1, h2) = DtriReader::hashes(domain, start, domain.len());
            let mut possible = true;
            for i in 0..7i64 {
                let sum = h1.wrapping_add(i.wrapping_mul(h2));
                let bit = ((sum % modulo) + modulo) % modulo;
                let byte_index = (bit / 8) as usize;
                let mask = 1u8 << ((bit % 8) as u32);
                match bloom.get(byte_index) {
                    Some(byte) if byte & mask != 0 => {}
                    _ => {
                        possible = false;
                        break;
                    }
                }
            }
            if possible {
                return true;
            }
            match domain[start..].iter().position(|b| *b == b'.') {
                Some(position) => start += position + 1,
                None => break,
            }
        }
        false
    }

    /// `containsOrParent`.
    pub fn contains_or_parent(&self, domain: &str) -> Option<&str> {
        self.contains_or_parent_with_disabled(domain, None)
    }

    /// `containsOrParentWithDisabled`: walks the labels from the TLD down and stops at the first
    /// terminal node; disabled patterns are skipped and the walk continues with the parent.
    pub fn contains_or_parent_with_disabled(
        &self,
        domain: &str,
        disabled: Option<&HashMap<String, ()>>,
    ) -> Option<&str> {
        if self.map.is_empty() {
            return None;
        }
        let lowered = crate::text::go_lower(domain.trim_end_matches('.')).into_owned();
        if lowered.is_empty() || !self.might_contain_domain_or_parent(lowered.as_bytes()) {
            return None;
        }
        let domain_bytes = lowered.as_bytes();
        let mut node = 0usize;
        let mut end = domain_bytes.len();
        while end > 0 {
            let start = lowered[..end].rfind('.').map(|dot| dot + 1).unwrap_or(0);
            let child = self.find_child(node, domain_bytes, start, end)?;
            node = child;
            let pattern = &lowered[start..];
            if let Some(disabled) = disabled {
                if disabled.contains_key(pattern) {
                    end = start.saturating_sub(1);
                    continue;
                }
            }
            let base = self.node_offset.checked_add(node.checked_mul(NODE_SIZE)?)?;
            let source_index = be_u32(self.data(), base)? as i32;
            if source_index >= 0 {
                let source = if (source_index as usize) < self.source_names.len() {
                    self.source_names[source_index as usize].as_str()
                } else {
                    "filter_list"
                };
                return Some(source);
            }
            end = start.saturating_sub(1);
        }
        None
    }

    /// Number of source labels stored in the index.
    pub fn source_count(&self) -> usize {
        self.sources
    }

    /// Path this index was mapped from (used in logs and tests).
    pub fn path(&self) -> &str {
        &self.file_path
    }
}

/// `path` + `modTime` + `size`, the identity Go uses to decide whether a trie can be reused
/// (`policyEngine.currentTries`). The registry only holds *weak* references: a mapping stays alive
/// exactly as long as a snapshot uses it, so the file is unmapped - and on Windows deletable - as
/// soon as the last snapshot that needed it is gone.
const MAX_CACHED: usize = 8;

struct CacheEntry {
    path: String,
    reader: Weak<DtriReader>,
}

static REGISTRY: OnceLock<Mutex<Vec<CacheEntry>>> = OnceLock::new();

fn registry() -> &'static Mutex<Vec<CacheEntry>> {
    REGISTRY.get_or_init(|| Mutex::new(Vec::new()))
}

/// Opens `path`, reusing an already mapped index whose mtime and size did not change.
pub fn open_shared(path: &str) -> Result<Arc<DtriReader>, String> {
    if path.is_empty() {
        return Err("empty path".to_string());
    }
    let metadata = std::fs::metadata(Path::new(path))
        .map_err(|error| format!("failed to stat DTRI trie {path}: {error}"))?;
    let size = metadata.len();
    let mod_time = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|delta| delta.as_nanos() as i64)
        .unwrap_or(0);

    let mut cache = registry().lock().unwrap_or_else(|error| error.into_inner());
    let reused = cache
        .iter()
        .position(|entry| entry.path == path)
        .and_then(|position| {
            let reader = cache[position].reader.upgrade()?;
            if reader.mod_time == mod_time && reader.size == size {
                Some((position, reader))
            } else {
                None
            }
        });
    if let Some((position, reader)) = reused {
        let entry = cache.remove(position);
        cache.insert(0, entry);
        return Ok(reader);
    }
    // A different mtime/size for the same path means the index was rewritten: the old mapping
    // stays valid for the snapshots that still hold it, but nobody else may pick it up again.
    cache.retain(|entry| entry.path != path);
    let reader = Arc::new(DtriReader::open(path)?);
    cache.insert(
        0,
        CacheEntry {
            path: path.to_string(),
            reader: Arc::downgrade(&reader),
        },
    );
    cache.retain(|entry| entry.reader.strong_count() > 0);
    cache.truncate(MAX_CACHED);
    Ok(reader)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map_of(entries: &[&str]) -> HashMap<String, ()> {
        entries
            .iter()
            .map(|entry| (entry.to_string(), ()))
            .collect()
    }

    #[test]
    fn hashes_wrap_like_go_int64() {
        let (h1, h2) = DtriReader::hashes(b"example.com", 0, 11);
        assert_eq!(h1, DtriReader::hashes(b"example.com.", 0, 11).0);
        assert_eq!(h2 & 1, 1);
        // Skipping the first label must match hashing that slice on its own.
        assert_eq!(
            DtriReader::hashes(b"www.example.com", 4, 15),
            DtriReader::hashes(b"example.com", 0, 11)
        );
    }

    #[test]
    fn missing_file_is_an_error_not_a_crash() {
        let error = match DtriReader::open("this/path/does/not/exist.dtri") {
            Ok(_) => panic!("expected an error"),
            Err(error) => error,
        };
        assert!(error.contains("failed to open DTRI file"));
    }

    #[test]
    fn disabled_set_is_only_used_as_a_lookup() {
        let disabled = map_of(&["ads.example.com"]);
        assert_eq!(disabled.len(), 1);
        assert!(disabled.contains_key("ads.example.com"));
    }
}
