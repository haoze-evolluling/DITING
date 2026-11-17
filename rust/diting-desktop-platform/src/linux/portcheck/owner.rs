//! Maps socket inodes from `/proc/net` to owning PIDs and identifies systemd-resolved.

use std::collections::HashMap;
use std::path::Path;

/// Builds inode → PID by walking every `/proc/<pid>/fd` symlink.
pub(crate) fn socket_inode_owners() -> HashMap<u64, i32> {
    let mut owners = HashMap::new();
    let Ok(entries) = std::fs::read_dir("/proc") else {
        return owners;
    };
    // The current process must be registered too: downstream checks `pid == self` to mark its own
    // listener as harmless instead of a third-party conflict.
    for entry in entries.flatten() {
        if !entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false) {
            continue;
        }
        let Ok(pid) = entry.file_name().to_string_lossy().parse::<i32>() else {
            continue;
        };
        collect_socket_fds(pid, &mut owners);
    }
    owners
}

fn collect_socket_fds(pid: i32, owners: &mut HashMap<u64, i32>) {
    let fd_directory = Path::new("/proc").join(pid.to_string()).join("fd");
    let Ok(entries) = std::fs::read_dir(&fd_directory) else {
        return;
    };
    for entry in entries.flatten() {
        let Ok(link) = std::fs::read_link(entry.path()) else {
            continue;
        };
        if let Some(inode) = parse_socket_link(&link.to_string_lossy()) {
            owners.insert(inode, pid);
        }
    }
}

/// Extracts the inode from a `socket:[12345]` symlink target.
pub(crate) fn parse_socket_link(link: &str) -> Option<u64> {
    let inner = link.strip_prefix("socket:[")?.strip_suffix(']')?;
    inner.parse::<u64>().ok()
}

/// Reads `/proc/<pid>/comm`, returning an empty string when unavailable.
pub(crate) fn process_name(pid: i32) -> String {
    match std::fs::read_to_string(Path::new("/proc").join(pid.to_string()).join("comm")) {
        Ok(name) => name.trim().to_string(),
        Err(_) => String::new(),
    }
}

/// Finds the running systemd-resolved PID, or 0 when it is not running.
pub(crate) fn systemd_resolved_pid() -> i32 {
    let Ok(entries) = std::fs::read_dir("/proc") else {
        return 0;
    };
    for entry in entries.flatten() {
        if !entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false) {
            continue;
        }
        let Ok(pid) = entry.file_name().to_string_lossy().parse::<i32>() else {
            continue;
        };
        if is_systemd_resolved_process(pid) {
            return pid;
        }
    }
    0
}

/// True when `/proc/<pid>/comm` names systemd-resolved.
pub(crate) fn is_systemd_resolved_process(pid: i32) -> bool {
    let name = process_name(pid);
    name == "systemd-resolve" || name == "systemd-resolved"
}

/// True for the systemd-resolved stub addresses (127.0.0.53 and 127.0.0.54).
pub(crate) fn is_resolved_stub_address(address: &str) -> bool {
    let host = match address.rfind(':') {
        Some(index) => &address[..index],
        None => address,
    };
    let host = host.trim_matches(['[', ']']);
    host == "127.0.0.53" || host == "127.0.0.54"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn socket_links_are_parsed() {
        assert_eq!(parse_socket_link("socket:[12345]"), Some(12345));
        assert_eq!(parse_socket_link("pipe:[12345]"), None);
        assert_eq!(parse_socket_link("socket:[bad]"), None);
    }

    #[test]
    fn stub_addresses_are_recognized() {
        assert!(is_resolved_stub_address("127.0.0.53:53"));
        assert!(!is_resolved_stub_address("[::1]:53"));
        assert!(is_resolved_stub_address("127.0.0.54:53"));
        assert!(!is_resolved_stub_address("127.0.0.1:53"));
    }
}
