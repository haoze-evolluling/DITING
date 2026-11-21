use std::sync::{Mutex, MutexGuard, RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::wire;

pub(super) fn build_key(query: &[u8]) -> Option<([u8; wire::MAX_KEY_LEN], wire::KeyParts)> {
    if query.len() < 12 {
        return None;
    }
    let mut buffer = [0u8; wire::MAX_KEY_LEN];
    let parts = wire::write_question_key(query, &mut buffer)?;
    Some((buffer, parts))
}

pub(super) fn parse_key_parts(key: &[u8]) -> Option<(Vec<u8>, u16, u16)> {
    let last = key.iter().rposition(|byte| *byte == b':')?;
    let previous = key[..last].iter().rposition(|byte| *byte == b':')?;
    let qclass = parse_decimal(&key[last + 1..])?;
    let qtype = parse_decimal(&key[previous + 1..last])?;
    Some((key[..previous].to_vec(), qtype, qclass))
}

fn parse_decimal(bytes: &[u8]) -> Option<u16> {
    if bytes.is_empty() || bytes.len() > 5 {
        return None;
    }
    let mut value = 0u32;
    for byte in bytes {
        if !byte.is_ascii_digit() {
            return None;
        }
        value = value * 10 + u32::from(byte - b'0');
    }
    u16::try_from(value).ok()
}

pub(super) fn shard_index(key: &[u8]) -> usize {
    (fnv32(key) as usize) % crate::policy::NUM_SHARDS
}

fn fnv32(bytes: &[u8]) -> u32 {
    let mut hash = 2166136261u32;
    for &byte in bytes {
        hash ^= u32::from(byte);
        hash = hash.wrapping_mul(16777619);
    }
    hash
}

pub(super) fn now_wall_ms() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(elapsed) => elapsed.as_millis().min(i64::MAX as u128) as i64,
        Err(_) => 0,
    }
}

pub(super) fn read_guard<T>(lock: &RwLock<T>) -> RwLockReadGuard<'_, T> {
    lock.read().unwrap_or_else(|poisoned| poisoned.into_inner())
}

pub(super) fn write_guard<T>(lock: &RwLock<T>) -> RwLockWriteGuard<'_, T> {
    lock.write()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

pub(super) fn mutex_guard<T>(lock: &Mutex<T>) -> MutexGuard<'_, T> {
    lock.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}
