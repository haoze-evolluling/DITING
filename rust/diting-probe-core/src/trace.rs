//! `TraceProbe`'s reading of one `ping -t <ttl>` run.
//!
//! Hop-by-hop traceroute borrows the system `ping` binary (no root, no `traceroute`), so one hop is
//! one process run and one text blob. The process, its streaming reader, the first-response stamp
//! and the loop stay in Kotlin; the kernel answers "what does this output say about this TTL".

use std::sync::LazyLock;

use regex::Regex;

const SPACE: &str = r"[ \t\n\x0B\f\r]";
const NOT_SPACE: &str = r"[^ \t\n\x0B\f\r]";
const ANY: &str = r"[^\n\r\x{85}\x{2028}\x{2029}]";

/// `from\s+(\S+):\s+(?:icmp_seq|seq)=\d+.*?time=([0-9.]+)\s*ms`
static REPLY: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!(
        "from{SPACE}+({NOT_SPACE}+):{SPACE}+(?:icmp_seq|seq)=[0-9]+{ANY}*?time=([0-9.]+){SPACE}*ms"
    ))
    .expect("trace reply pattern")
});

/// `From\s+(.+?)\s*:??\s*icmp_seq=\d+\s+(.*)`
static FROM: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!(
        "From{SPACE}+({ANY}+?){SPACE}*:??{SPACE}*icmp_seq=[0-9]+{SPACE}+({ANY}*)"
    ))
    .expect("trace from pattern")
});

/// What one hop's output means.
#[derive(Debug, Clone, PartialEq)]
pub enum Hop {
    /// The target itself answered.
    Reached {
        address: Option<String>,
        elapsed_ms: Option<f64>,
    },
    /// A router answered, possibly with an ICMP unreachable.
    Answered { address: String, unreachable: bool },
    /// No hop address, but the run says the network could not send a probe at all.
    NetUnreachable,
    /// No pattern matched: the hop timed out.
    NoMatch,
    /// The binary does not support `-t` (`Usage:` / `invalid option`).
    Unsupported,
}

/// `TraceProbe`'s per-hop parse. `resolved` is the address the caller resolved the target to; it
/// fills in a reply line whose `from` group came back empty.
pub fn parse_hop(text: &str, resolved: &str) -> Hop {
    if text.contains("Usage:") || text.contains("invalid option") {
        return Hop::Unsupported;
    }

    if let Some(captures) = REPLY.captures(text) {
        let address = captures
            .get(1)
            .map(|m| m.as_str())
            .filter(|value| !value.is_empty())
            .unwrap_or(resolved)
            .to_string();
        return Hop::Reached {
            address: Some(address),
            elapsed_ms: captures.get(2).and_then(|m| m.as_str().parse::<f64>().ok()),
        };
    }

    if let Some(captures) = FROM.captures(text) {
        let address = captures
            .get(1)
            .map(|m| m.as_str())
            .unwrap_or("")
            .to_string();
        let unreachable = captures
            .get(2)
            .map(|m| {
                // `contains("unreach", ignoreCase = true)`: Java compares character by character,
                // a lowercase fold finds the same ASCII needle.
                m.as_str().to_lowercase().contains("unreach")
            })
            .unwrap_or(false);
        return Hop::Answered {
            address,
            unreachable,
        };
    }

    if text.to_lowercase().contains("unreach") {
        return Hop::NetUnreachable;
    }
    Hop::NoMatch
}

/// The streaming reader's stamp line: `contains("time=") || startsWith("From ")`.
pub fn is_response_line(line: &str) -> bool {
    line.contains("time=") || line.starts_with("From ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_target_answering() {
        let text = "PING 1.1.1.1 (1.1.1.1) 56(84) bytes of data.\n\
64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.3 ms\n\
\n--- 1.1.1.1 ping statistics ---\n1 packets transmitted, 1 received, 0% packet loss\n";
        assert_eq!(
            parse_hop(text, "9.9.9.9"),
            Hop::Reached {
                address: Some("1.1.1.1".into()),
                elapsed_ms: Some(12.3)
            }
        );
    }

    #[test]
    fn reads_a_router_reporting_unreachable() {
        let text = "From 192.168.1.1 icmp_seq=1 Time to live exceeded\n";
        assert_eq!(
            parse_hop(text, ""),
            Hop::Answered {
                address: "192.168.1.1".into(),
                unreachable: false
            }
        );

        let text = "From 10.0.0.1: icmp_seq=1 Destination Net Unreachable\n";
        assert_eq!(
            parse_hop(text, ""),
            Hop::Answered {
                address: "10.0.0.1".into(),
                unreachable: true
            }
        );
    }

    #[test]
    fn ipv6_hop_limit_is_an_answer_without_reaching() {
        let text = "From 2001:db8::1 icmp_seq=1 Time exceeded: Hop limit\n";
        assert_eq!(
            parse_hop(text, ""),
            Hop::Answered {
                address: "2001:db8::1".into(),
                unreachable: false
            }
        );
    }

    #[test]
    fn a_silent_hop_is_a_gap_and_an_unsupported_binary_is_named() {
        let text = "PING x (1.2.3.4) 56 data bytes\n\n--- 1.2.3.4 ping statistics ---\n\
1 packets transmitted, 0 received, 100% packet loss\n";
        assert_eq!(parse_hop(text, ""), Hop::NoMatch);

        assert_eq!(parse_hop("Usage: ping [-t ttl]\n", ""), Hop::Unsupported);
        assert_eq!(
            parse_hop("ping: invalid option -- t\n", ""),
            Hop::Unsupported
        );
        assert_eq!(
            parse_hop("connect: Network is unreachable\n", ""),
            Hop::NetUnreachable
        );
    }

    #[test]
    fn the_stamp_lines_are_the_two_the_reader_looked_for() {
        assert!(is_response_line(
            "64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.3 ms"
        ));
        assert!(is_response_line(
            "From 10.0.0.1 icmp_seq=1 Time to live exceeded"
        ));
        assert!(!is_response_line(
            "PING 1.1.1.1 (1.1.1.1) 56(84) bytes of data."
        ));
        assert!(!is_response_line("--- 1.1.1.1 ping statistics ---"));
    }
}
