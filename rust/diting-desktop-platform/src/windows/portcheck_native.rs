use std::collections::HashMap;
use std::ffi::c_void;
use std::mem::size_of;
use std::net::{Ipv4Addr, Ipv6Addr};
use std::ptr;

use diting_desktop_api::platform_types::PortConflict;
use windows_sys::Win32::Foundation::{
    CloseHandle, ERROR_INSUFFICIENT_BUFFER, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::NetworkManagement::IpHelper::{
    GetExtendedTcpTable, GetExtendedUdpTable, MIB_TCP6ROW_OWNER_PID, MIB_TCPROW_OWNER_PID,
    MIB_UDP6ROW_OWNER_PID, MIB_UDPROW_OWNER_PID, TCP_TABLE_OWNER_PID_ALL, UDP_TABLE_OWNER_PID,
};
use windows_sys::Win32::Networking::WinSock::{AF_INET, AF_INET6};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
};

use crate::exec::CommandExecutor;

use super::portcheck_ics::check_ics_status;

const MIB_TCP_STATE_LISTEN: u32 = 2;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct NativePortListener {
    pub protocol: String,
    pub local_address: String,
    pub pid: u32,
    pub process_name: String,
}

#[derive(Clone, Copy)]
struct TableSpec {
    protocol: &'static str,
    family: u32,
    tcp: bool,
    ipv6: bool,
}

const PORT_TABLES: [TableSpec; 4] = [
    TableSpec {
        protocol: "TCP",
        family: AF_INET as u32,
        tcp: true,
        ipv6: false,
    },
    TableSpec {
        protocol: "TCP",
        family: AF_INET6 as u32,
        tcp: true,
        ipv6: true,
    },
    TableSpec {
        protocol: "UDP",
        family: AF_INET as u32,
        tcp: false,
        ipv6: false,
    },
    TableSpec {
        protocol: "UDP",
        family: AF_INET6 as u32,
        tcp: false,
        ipv6: true,
    },
];

#[derive(Debug, Clone, PartialEq, Eq)]
struct RawListener {
    address: String,
    pid: u32,
}

fn decode_port(raw: u32) -> u16 {
    (((raw & 0xff) << 8) | ((raw >> 8) & 0xff)) as u16
}

fn fetch_mib_table(spec: &TableSpec) -> Option<Vec<u8>> {
    let mut size: u32 = 0;
    let mut buffer: Vec<u8> = Vec::new();
    let mut status = u32::MAX;

    for _ in 0..5 {
        let pointer = if buffer.is_empty() {
            ptr::null_mut()
        } else {
            buffer.as_mut_ptr() as *mut c_void
        };
        status = unsafe {
            if spec.tcp {
                GetExtendedTcpTable(
                    pointer,
                    &mut size,
                    0,
                    spec.family,
                    TCP_TABLE_OWNER_PID_ALL,
                    0,
                )
            } else {
                GetExtendedUdpTable(pointer, &mut size, 0, spec.family, UDP_TABLE_OWNER_PID, 0)
            }
        };
        if status == 0 {
            break;
        }
        if status != ERROR_INSUFFICIENT_BUFFER {
            return None;
        }
        buffer = vec![0u8; size as usize];
    }

    if status != 0 || buffer.len() < 4 {
        None
    } else {
        Some(buffer)
    }
}

fn walk_table(spec: &TableSpec, target_port: u16) -> Option<Vec<RawListener>> {
    let buffer = fetch_mib_table(spec)?;
    let count = u32::from_le_bytes([buffer[0], buffer[1], buffer[2], buffer[3]]) as usize;
    let mut offset = 4usize;
    let mut listeners = Vec::new();

    for _ in 0..count {
        match (spec.tcp, spec.ipv6) {
            (true, false) => {
                let row_size = size_of::<MIB_TCPROW_OWNER_PID>();
                if offset + row_size > buffer.len() {
                    break;
                }
                let row = unsafe {
                    ptr::read_unaligned(buffer.as_ptr().add(offset) as *const MIB_TCPROW_OWNER_PID)
                };
                offset += row_size;
                if row.dwState != MIB_TCP_STATE_LISTEN {
                    continue;
                }
                let port = decode_port(row.dwLocalPort);
                if port != target_port {
                    continue;
                }
                listeners.push(RawListener {
                    address: format!("{}:{port}", Ipv4Addr::from(row.dwLocalAddr.to_le_bytes())),
                    pid: row.dwOwningPid,
                });
            }
            (true, true) => {
                let row_size = size_of::<MIB_TCP6ROW_OWNER_PID>();
                if offset + row_size > buffer.len() {
                    break;
                }
                let row = unsafe {
                    ptr::read_unaligned(buffer.as_ptr().add(offset) as *const MIB_TCP6ROW_OWNER_PID)
                };
                offset += row_size;
                if row.dwState != MIB_TCP_STATE_LISTEN {
                    continue;
                }
                let port = decode_port(row.dwLocalPort);
                if port != target_port {
                    continue;
                }
                listeners.push(RawListener {
                    address: format!("{}:{port}", Ipv6Addr::from(row.ucLocalAddr)),
                    pid: row.dwOwningPid,
                });
            }
            (false, false) => {
                let row_size = size_of::<MIB_UDPROW_OWNER_PID>();
                if offset + row_size > buffer.len() {
                    break;
                }
                let row = unsafe {
                    ptr::read_unaligned(buffer.as_ptr().add(offset) as *const MIB_UDPROW_OWNER_PID)
                };
                offset += row_size;
                let port = decode_port(row.dwLocalPort);
                if port != target_port {
                    continue;
                }
                listeners.push(RawListener {
                    address: format!("{}:{port}", Ipv4Addr::from(row.dwLocalAddr.to_le_bytes())),
                    pid: row.dwOwningPid,
                });
            }
            (false, true) => {
                let row_size = size_of::<MIB_UDP6ROW_OWNER_PID>();
                if offset + row_size > buffer.len() {
                    break;
                }
                let row = unsafe {
                    ptr::read_unaligned(buffer.as_ptr().add(offset) as *const MIB_UDP6ROW_OWNER_PID)
                };
                offset += row_size;
                let port = decode_port(row.dwLocalPort);
                if port != target_port {
                    continue;
                }
                listeners.push(RawListener {
                    address: format!("{}:{port}", Ipv6Addr::from(row.ucLocalAddr)),
                    pid: row.dwOwningPid,
                });
            }
        }
    }

    Some(listeners)
}

fn process_name_map() -> HashMap<u32, String> {
    let mut names = HashMap::new();
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snapshot == INVALID_HANDLE_VALUE {
        return names;
    }

    let mut entry: PROCESSENTRY32W = unsafe { std::mem::zeroed() };
    entry.dwSize = size_of::<PROCESSENTRY32W>() as u32;
    let mut status = unsafe { Process32FirstW(snapshot, &mut entry) };
    while status != 0 {
        let length = entry
            .szExeFile
            .iter()
            .position(|unit| *unit == 0)
            .unwrap_or(entry.szExeFile.len());
        names.insert(
            entry.th32ProcessID,
            String::from_utf16_lossy(&entry.szExeFile[..length]),
        );
        status = unsafe { Process32NextW(snapshot, &mut entry) };
    }

    unsafe { CloseHandle(snapshot) };
    names
}

fn get_port53_listeners_native() -> (Vec<NativePortListener>, bool) {
    let names = process_name_map();
    let mut listeners = Vec::new();
    let mut any_success = false;

    for spec in &PORT_TABLES {
        let Some(rows) = walk_table(spec, 53) else {
            continue;
        };
        any_success = true;
        for row in rows {
            let process_name = names
                .get(&row.pid)
                .cloned()
                .unwrap_or_else(|| "unknown".to_string());
            listeners.push(NativePortListener {
                protocol: spec.protocol.to_string(),
                local_address: row.address,
                pid: row.pid,
                process_name,
            });
        }
    }

    (listeners, any_success)
}

async fn get_port53_listeners(executor: &dyn CommandExecutor) -> Vec<NativePortListener> {
    let (listeners, any_native_success) = get_port53_listeners_native();
    if any_native_success {
        return listeners;
    }

    let mut fallback = Vec::new();
    for (protocol, tcp) in [("TCP", true), ("UDP", false)] {
        let args = if tcp {
            vec!["-ano", "-p", "TCP"]
        } else {
            vec!["-ano", "-p", "UDP"]
        };
        if let Ok(output) = executor.run("netstat", &args).await {
            fallback.extend(parse_netstat_output(&output.text(), protocol, tcp));
        }
    }
    let names = process_name_map();
    for listener in &mut fallback {
        if listener.process_name.is_empty() || listener.process_name == "unknown" {
            if let Some(name) = names.get(&listener.pid) {
                listener.process_name = name.clone();
            }
        }
    }
    fallback
}

pub(crate) fn parse_netstat_output(
    output: &str,
    protocol: &str,
    tcp: bool,
) -> Vec<NativePortListener> {
    let mut listeners = Vec::new();
    for line in output.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 4 {
            continue;
        }
        let Some(local) = fields.get(1) else {
            continue;
        };
        if !local.ends_with(":53") {
            continue;
        }
        if tcp {
            let listening = fields
                .iter()
                .any(|field| field.eq_ignore_ascii_case("LISTENING") || *field == "侦听");
            if !listening {
                continue;
            }
        }
        let Some(pid) = fields.last().and_then(|field| field.parse::<u32>().ok()) else {
            continue;
        };
        listeners.push(NativePortListener {
            protocol: protocol.to_string(),
            local_address: (*local).to_string(),
            pid,
            process_name: String::new(),
        });
    }
    listeners
}

pub(crate) fn format_port_conflicts(
    raw_list: &[NativePortListener],
    has_ics: bool,
    ics_pid: u32,
    available: bool,
    self_pid: u32,
) -> (Vec<PortConflict>, bool, String) {
    let mut conflicts = Vec::with_capacity(raw_list.len());
    let mut diagnostics = Vec::new();
    let mut has_self_listener = false;

    for item in raw_list {
        let is_self = self_pid > 0 && item.pid == self_pid;
        if is_self {
            has_self_listener = true;
        }
        let is_ics = if !is_self && has_ics {
            if ics_pid > 0 {
                item.pid == ics_pid
            } else {
                item.process_name.to_ascii_lowercase().contains("svchost")
            }
        } else {
            false
        };

        let diagnosis = if is_self {
            format!(
                "进程 PID {} ({}) 为谛听 (DITING) 服务自身正在监听 {} ({})。",
                item.pid, item.process_name, item.local_address, item.protocol
            )
        } else if is_ics {
            let message = format!(
                "检测到 Windows 网络连接共享服务 (SharedAccess / ICS) 正在运行 (PID: {})。ICS 会在 0.0.0.0:53 上占用 UDP，阻止本地 DNS 代理绑定。排查建议：按 Win+R 打开 services.msc 停止并禁用 'Internet Connection Sharing (ICS)' 服务，或以管理员身份运行 'sc stop SharedAccess'。",
                item.pid
            );
            diagnostics.push(message.clone());
            message
        } else {
            let message = format!(
                "检测到外部进程 '{}' (PID: {}) 正在监听 {} ({})。排查建议：请在任务管理器中结束该进程，或修改该软件的监听端口后重试。",
                item.process_name, item.pid, item.local_address, item.protocol
            );
            diagnostics.push(message.clone());
            message
        };

        conflicts.push(PortConflict {
            port: 53,
            protocol: item.protocol.clone(),
            local_address: item.local_address.clone(),
            pid: item.pid as i32,
            process_name: item.process_name.clone(),
            service_name: if is_ics {
                "SharedAccess".to_string()
            } else {
                String::new()
            },
            is_ics,
            is_self,
            diagnosis,
        });
    }

    let diagnostic = if diagnostics.is_empty() {
        if has_self_listener {
            "127.0.0.1:53 当前由谛听 (DITING) 核心服务监听中，无外部端口冲突。".to_string()
        } else if available {
            "53 端口空闲且可用，无端口冲突。".to_string()
        } else {
            "未能直接绑定 127.0.0.1:53，但未探测到明确的系统监听进程（可能需要管理员权限）。排查建议：请检查是否有其他 DNS 或代理软件占用，或尝试以管理员身份运行本服务。".to_string()
        }
    } else {
        diagnostics.join("\n")
    };

    (conflicts, has_ics, diagnostic)
}

pub(crate) async fn check_port53_native(
    executor: &dyn CommandExecutor,
    available: bool,
    self_pid: u32,
) -> (Vec<PortConflict>, bool, String) {
    let listeners = get_port53_listeners(executor).await;
    let (has_ics, ics_pid) = check_ics_status(executor).await;
    format_port_conflicts(&listeners, has_ics, ics_pid, available, self_pid)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn listener(protocol: &str, address: &str, pid: u32, name: &str) -> NativePortListener {
        NativePortListener {
            protocol: protocol.to_string(),
            local_address: address.to_string(),
            pid,
            process_name: name.to_string(),
        }
    }

    #[test]
    fn ics_listener_is_flagged_and_diagnosed() {
        let raw = vec![listener("UDP", "0.0.0.0:53", 1824, "svchost.exe")];
        let (conflicts, has_ics, diagnostic) = format_port_conflicts(&raw, true, 1824, true, 0);
        assert!(has_ics);
        assert_eq!(conflicts.len(), 1);
        assert!(conflicts[0].is_ics);
        assert_eq!(conflicts[0].service_name, "SharedAccess");
        assert!(diagnostic.contains("SharedAccess"));
        assert!(diagnostic.contains("Internet Connection Sharing"));
    }

    #[test]
    fn third_party_listener_is_reported() {
        let raw = vec![listener("UDP", "127.0.0.1:53", 9999, "acrylic.exe")];
        let (conflicts, has_ics, diagnostic) = format_port_conflicts(&raw, false, 0, false, 0);
        assert!(!has_ics);
        assert!(!conflicts[0].is_ics);
        assert!(diagnostic.contains("acrylic.exe"));
    }

    #[test]
    fn clean_port_has_no_conflicts() {
        let (conflicts, has_ics, diagnostic) = format_port_conflicts(&[], false, 0, true, 0);
        assert!(conflicts.is_empty());
        assert!(!has_ics);
        assert!(diagnostic.contains("空闲且可用"));
    }

    #[test]
    fn self_listener_is_available() {
        let raw = vec![listener("UDP", "127.0.0.1:53", 1234, "diting-service.exe")];
        let (conflicts, _, diagnostic) = format_port_conflicts(&raw, false, 0, false, 1234);
        assert!(conflicts[0].is_self);
        assert!(diagnostic.contains("谛听 (DITING) 核心服务监听中"));
    }

    #[test]
    fn netstat_fallback_parses_udp_and_tcp() {
        let udp = "  UDP    0.0.0.0:53         *:*                                    1824\n";
        let parsed = parse_netstat_output(udp, "UDP", false);
        assert_eq!(parsed, vec![listener("UDP", "0.0.0.0:53", 1824, "")]);

        let tcp = "  TCP    127.0.0.1:53         0.0.0.0:0              LISTENING       1234\n";
        let parsed = parse_netstat_output(tcp, "TCP", true);
        assert_eq!(parsed, vec![listener("TCP", "127.0.0.1:53", 1234, "")]);

        let unrelated = "  TCP    127.0.0.1:5353       0.0.0.0:0              LISTENING       1\n";
        assert!(parse_netstat_output(unrelated, "TCP", true).is_empty());
    }

    #[test]
    fn port_decoding_swaps_network_order() {
        assert_eq!(decode_port(0x3500), 53);
    }
}
