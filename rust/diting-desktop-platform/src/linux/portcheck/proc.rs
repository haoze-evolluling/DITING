//! `/proc/net/{udp,tcp,udp6,tcp6}` parsing for sockets bound to port 53.

use std::io;

const TCP_LISTEN_STATE: i32 = 0x0A;

/// One socket row from a `/proc/net` table.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ProcSocket {
    pub protocol: String,
    pub local_address: String,
    pub local_port: u16,
    pub inode: u64,
    pub state: i32,
}

const PROC_NET_FILES: [(&str, &str); 4] = [
    ("/proc/net/udp", "UDP"),
    ("/proc/net/tcp", "TCP"),
    ("/proc/net/udp6", "UDP"),
    ("/proc/net/tcp6", "TCP"),
];

/// Parses one `/proc/net` table; a missing table means the protocol is unavailable.
pub(crate) fn parse_proc_net(path: &str, protocol: &str) -> io::Result<Vec<ProcSocket>> {
    match std::fs::read_to_string(path) {
        Ok(content) => Ok(parse_proc_net_content(&content, protocol)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(error) => Err(error),
    }
}

/// Pure parser for a `/proc/net` table body.
pub(crate) fn parse_proc_net_content(content: &str, protocol: &str) -> Vec<ProcSocket> {
    let mut sockets = Vec::new();
    for line in content.lines().skip(1) {
        let fields: Vec<&str> = line.split_whitespace().collect();
        // local_address, state and inode are the fields we need.
        if fields.len() < 10 {
            continue;
        }
        let Ok((address, port)) = parse_hex_endpoint(fields[1]) else {
            continue;
        };
        let Ok(state) = i32::from_str_radix(fields[3], 16) else {
            continue;
        };
        let inode = fields[9].parse::<u64>().unwrap_or(0);

        sockets.push(ProcSocket {
            protocol: protocol.to_string(),
            local_address: join_host_port(&address, port),
            local_port: port,
            inode,
            state,
        });
    }
    sockets
}

/// Parses `"0100007F:0035"` into `("127.0.0.1", 53)`.
pub(crate) fn parse_hex_endpoint(value: &str) -> Result<(String, u16), ()> {
    let mut parts = value.split(':');
    let address = parts.next().ok_or(())?;
    let port = parts.next().ok_or(())?;
    if parts.next().is_some() {
        return Err(());
    }
    let port = u16::from_str_radix(port, 16).map_err(|_| ())?;
    let address = parse_proc_hex_ip(address)?;
    Ok((address, port))
}

/// Converts a little-endian hex IPv4 or `/proc` IPv6 address into text.
pub(crate) fn parse_proc_hex_ip(value: &str) -> Result<String, ()> {
    match value.len() {
        8 => {
            let parsed = u32::from_str_radix(value, 16).map_err(|_| ())?;
            Ok(format!(
                "{}.{}.{}.{}",
                parsed & 0xff,
                (parsed >> 8) & 0xff,
                (parsed >> 16) & 0xff,
                (parsed >> 24) & 0xff
            ))
        }
        32 => parse_proc_hex_ipv6(value),
        _ => Err(()),
    }
}

/// Reassembles 32 hex characters as four little-endian 32-bit groups.
fn parse_proc_hex_ipv6(value: &str) -> Result<String, ()> {
    let mut groups: Vec<String> = Vec::with_capacity(8);
    let mut offset = 0;
    while offset < 32 {
        let chunk = value.get(offset..offset + 8).ok_or(())?;
        let parsed = u32::from_str_radix(chunk, 16).map_err(|_| ())?;
        groups.push(format!("{:02x}{:02x}", parsed & 0xff, (parsed >> 8) & 0xff));
        groups.push(format!(
            "{:02x}{:02x}",
            (parsed >> 16) & 0xff,
            (parsed >> 24) & 0xff
        ));
        offset += 8;
    }
    Ok(groups.join(":"))
}

fn join_host_port(address: &str, port: u16) -> String {
    if address.contains(':') {
        format!("[{address}]:{port}")
    } else {
        format!("{address}:{port}")
    }
}

/// Collects every UDP/TCP socket listening on 53 in Go's file order.
pub(crate) fn collect_port53_sockets() -> io::Result<Vec<ProcSocket>> {
    let mut listeners = Vec::new();
    for (path, protocol) in PROC_NET_FILES {
        for socket in parse_proc_net(path, protocol)? {
            if socket.local_port != 53 {
                continue;
            }
            if socket.protocol == "TCP" && socket.state != TCP_LISTEN_STATE {
                continue;
            }
            listeners.push(socket);
        }
    }
    Ok(listeners)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n\
        0: 0100007F:0035 00000000:0000 07 00000000:00000000 00:00000000 00000000     0        0 12345 0\n\
        1: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 999 0\n";

    #[test]
    fn proc_rows_are_parsed_with_inode() {
        let sockets = parse_proc_net_content(SAMPLE, "UDP");
        assert_eq!(sockets.len(), 2);
        assert_eq!(sockets[0].local_address, "127.0.0.1:53");
        assert_eq!(sockets[0].local_port, 53);
        assert_eq!(sockets[0].inode, 12345);
    }

    #[test]
    fn endpoint_parsing_is_little_endian() {
        assert_eq!(
            parse_hex_endpoint("0100007F:0035").unwrap(),
            ("127.0.0.1".to_string(), 53)
        );
        assert!(parse_hex_endpoint("bad").is_err());
    }

    #[test]
    fn ipv6_hex_is_reassembled() {
        assert_eq!(
            parse_proc_hex_ip("00000000000000000000000001000000").unwrap(),
            "0000:0000:0000:0000:0000:0000:0000:0001"
        );
        assert!(parse_proc_hex_ip("zz").is_err());
    }

    #[test]
    fn tcp_non_listen_rows_are_filtered() {
        // The sample's second row is TCP with state 0A (LISTEN); changing it to 01 excludes it.
        let non_listen = SAMPLE.replace(
            "00000000:0016 00000000:0000 0A",
            "00000000:0016 00000000:0000 01",
        );
        let sockets = parse_proc_net_content(&non_listen, "TCP");
        assert_eq!(sockets.len(), 2);
        let collected: Vec<_> = sockets
            .iter()
            .filter(|socket| socket.protocol != "TCP" || socket.state == TCP_LISTEN_STATE)
            .collect();
        assert_eq!(collected.len(), 1);
    }
}
