//! `PingProbe` output parsing and the latency arithmetic the probes share.
//!
//! The system `ping` binary stays a Kotlin `Process`; what moves here is everything that reads its
//! text: the reply/loss/summary patterns, the per-sequence gap rows, the min/avg/max/jitter block,
//! and the sample averaging `DnsLatencyTester` and the TCP fallback use.
//!
//! The patterns are the Kotlin ones, but Java's character classes are spelled out so the two
//! engines cannot drift:
//!
//! * `\s` -> `[ \t\n\x0B\f\r]` (Java's `\s` is ASCII, Rust's is Unicode),
//! * `\S` -> `[^ \t\n\x0B\f\r]`,
//! * `\d` -> `[0-9]` (Java's `\d` is ASCII by default, Rust's is Unicode `Nd`),
//! * `.`  -> `[^\n\r\x{85}\x{2028}\x{2029}]` (Java stops at those five line terminators, Rust only
//!   at `\n`), which is what keeps `(.*)` and `.*?` inside one line exactly like before.

use std::sync::LazyLock;

use regex::Regex;

const SPACE: &str = r"[ \t\n\x0B\f\r]";
const NOT_SPACE: &str = r"[^ \t\n\x0B\f\r]";
const DIGIT: &str = r"[0-9]";
const ANY: &str = r"[^\n\r\x{85}\x{2028}\x{2029}]";

/// `from\s+(\S+):\s+(?:icmp_seq|seq)=(\d+)(?:.*?ttl=(\d+))?.*?time=([0-9.]+)\s*ms`
static REPLY: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!(
        "from{SPACE}+({NOT_SPACE}+):{SPACE}+(?:icmp_seq|seq)=({DIGIT}+)(?:{ANY}*?ttl=({DIGIT}+))?{ANY}*?time=([0-9.]+){SPACE}*ms"
    ))
    .expect("ping reply pattern")
});

/// `([0-9.]+)% packet loss`
static LOSS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"([0-9.]+)% packet loss").expect("ping loss pattern"));

/// `(\d+) packets? transmitted`
static TRANSMITTED: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!("({DIGIT}+) packets? transmitted")).expect("ping transmitted pattern")
});

/// `(\d+) (?:packets? )?received`
static RECEIVED: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!("({DIGIT}+) (?:packets? )?received")).expect("ping received pattern")
});

/// `=\s*([0-9.]+)/([0-9.]+)/([0-9.]+)(?:/([0-9.]+))?\s*ms`
static RTT: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!(
        "={SPACE}*([0-9.]+)/([0-9.]+)/([0-9.]+)(?:/([0-9.]+))?{SPACE}*ms"
    ))
    .expect("ping rtt pattern")
});

/// One row of the `replies` list a diagnostics panel renders.
#[derive(Debug, Clone, PartialEq)]
pub struct Reply {
    pub sequence: i32,
    pub elapsed_ms: Option<f64>,
    pub ttl: Option<i32>,
    /// Synthesized gap row: the packet was declared transmitted but never reported.
    pub timeout: bool,
}

/// What one `ping` run's text says, in the shape `PingSummary` wants.
#[derive(Debug, Clone, PartialEq)]
pub struct Summary {
    pub transmitted: i32,
    pub received: i32,
    pub loss_percent: f64,
    pub min_ms: Option<f64>,
    pub avg_ms: Option<f64>,
    pub max_ms: Option<f64>,
    pub jitter_ms: Option<f64>,
    pub replies: Vec<Reply>,
}

/// One parsed reply line, before the rows are fanned out per sequence number.
struct ParsedReply {
    sequence: Option<i32>,
    elapsed_ms: Option<f64>,
    ttl: Option<i32>,
}

/// `PingProbe.parseSummary`. None means "no `N% packet loss` line", which is the caller's signal to
/// fall back to `InetAddress.isReachable` / TCP timing.
pub fn parse_summary(output: &str) -> Option<Summary> {
    let loss = LOSS.captures(output)?;

    let parsed: Vec<ParsedReply> = REPLY
        .captures_iter(output)
        .map(|captures| ParsedReply {
            sequence: captures.get(2).and_then(|m| parse_i32(m.as_str())),
            ttl: captures.get(3).and_then(|m| parse_i32(m.as_str())),
            elapsed_ms: captures.get(4).and_then(|m| parse_f64(m.as_str())),
        })
        .collect();

    let transmitted = TRANSMITTED
        .captures(output)
        .and_then(|captures| captures.get(1))
        .and_then(|m| parse_i32(m.as_str()))
        .unwrap_or(parsed.len().max(1) as i32);
    let received = RECEIVED
        .captures(output)
        .and_then(|captures| captures.get(1))
        .and_then(|m| parse_i32(m.as_str()))
        .unwrap_or_else(|| {
            parsed
                .iter()
                .filter(|reply| reply.elapsed_ms.is_some())
                .count() as i32
        });
    let loss_percent = loss
        .get(1)
        .and_then(|m| parse_f64(m.as_str()))
        .unwrap_or_else(|| {
            if transmitted > 0 {
                (transmitted - received) as f64 * 100.0 / transmitted as f64
            } else {
                100.0
            }
        });

    let rtt = RTT.captures(output);

    // `associateBy`: a duplicate sequence number keeps the last line, and an unparsable one lands
    // on -1, which no row range can hit.
    let mut by_sequence: Vec<(i32, &ParsedReply)> = Vec::new();
    for reply in &parsed {
        let key = reply.sequence.unwrap_or(-1);
        match by_sequence
            .iter_mut()
            .find(|(existing, _)| *existing == key)
        {
            Some(entry) => entry.1 = reply,
            None => by_sequence.push((key, reply)),
        }
    }

    let base = if by_sequence.iter().any(|(key, _)| *key == 0) {
        0
    } else {
        1
    };
    let mut replies = Vec::with_capacity(transmitted.max(0) as usize);
    for sequence in base..base + transmitted {
        match by_sequence.iter().find(|(key, _)| *key == sequence) {
            Some((_, reply)) => replies.push(Reply {
                sequence,
                elapsed_ms: reply.elapsed_ms,
                ttl: reply.ttl,
                timeout: false,
            }),
            None => replies.push(Reply {
                sequence,
                elapsed_ms: None,
                ttl: None,
                timeout: true,
            }),
        }
    }

    let samples: Vec<f64> = parsed.iter().filter_map(|reply| reply.elapsed_ms).collect();
    let stats = latency_stats(&samples);

    Some(Summary {
        transmitted,
        received,
        loss_percent,
        min_ms: rtt
            .as_ref()
            .and_then(|captures| captures.get(1))
            .and_then(|m| parse_f64(m.as_str()))
            .or(stats.min_ms),
        avg_ms: rtt
            .as_ref()
            .and_then(|captures| captures.get(2))
            .and_then(|m| parse_f64(m.as_str()))
            .or(stats.avg_ms),
        max_ms: rtt
            .as_ref()
            .and_then(|captures| captures.get(3))
            .and_then(|m| parse_f64(m.as_str()))
            .or(stats.max_ms),
        jitter_ms: rtt
            .as_ref()
            .and_then(|captures| captures.get(4))
            .and_then(|m| parse_f64(m.as_str()))
            .or(stats.jitter_ms),
        replies,
    })
}

/// Min / avg / max / mean absolute deviation, plus the rounded average a latency sample uses.
#[derive(Debug, Clone, PartialEq)]
pub struct LatencyStats {
    pub min_ms: Option<f64>,
    pub avg_ms: Option<f64>,
    pub max_ms: Option<f64>,
    pub jitter_ms: Option<f64>,
    /// `average().roundToLong().coerceAtLeast(1)`: the millisecond value `DnsLatencyTester` reports.
    pub rounded_average_ms: i64,
}

/// `samples.minOrNull()` / `average()` / `maxOrNull()` / `jitterOf`.
pub fn latency_stats(samples: &[f64]) -> LatencyStats {
    if samples.is_empty() {
        return LatencyStats {
            min_ms: None,
            avg_ms: None,
            max_ms: None,
            jitter_ms: None,
            rounded_average_ms: 1,
        };
    }
    let mut min = samples[0];
    let mut max = samples[0];
    let mut sum = 0.0;
    for sample in samples {
        sum += *sample;
        if *sample < min {
            min = *sample;
        }
        if *sample > max {
            max = *sample;
        }
    }
    let mean = sum / samples.len() as f64;
    // `jitterOf` returns null for fewer than two samples (mean absolute deviation needs a pair).
    let jitter = if samples.len() >= 2 {
        Some(
            samples
                .iter()
                .map(|sample| (sample - mean).abs())
                .sum::<f64>()
                / samples.len() as f64,
        )
    } else {
        None
    };
    let rounded = round_half_up(mean).max(1);
    LatencyStats {
        min_ms: Some(min),
        avg_ms: Some(mean),
        max_ms: Some(max),
        jitter_ms: jitter,
        rounded_average_ms: rounded,
    }
}

/// `kotlin.math.roundToLong` / `Math.round`: half up, NaN to zero, and a saturating cast.
fn round_half_up(value: f64) -> i64 {
    value.round() as i64
}

/// `String.toIntOrNull`: ASCII digits with an optional sign, trailing text rejected, overflow null.
fn parse_i32(text: &str) -> Option<i32> {
    text.parse::<i32>().ok()
}

/// `String.toDoubleOrNull`: the inputs here are `[0-9.]+`, where `Double.parseDouble` and Rust's
/// parser agree (a bare `.` or `1.2.3` fails on both).
fn parse_f64(text: &str) -> Option<f64> {
    text.parse::<f64>().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    const IPUTILS: &str = "PING example.com (93.184.216.34) 56(84) bytes of data.\n\
64 bytes from 93.184.216.34: icmp_seq=1 ttl=57 time=12.3 ms\n\
64 bytes from 93.184.216.34: icmp_seq=2 ttl=57 time=15.1 ms\n\
\n\
--- example.com ping statistics ---\n\
3 packets transmitted, 2 received, 33.3333% packet loss, time 2003ms\n\
rtt min/avg/max/mdev = 12.300/13.700/15.100/1.400 ms\n";

    #[test]
    fn parses_iputils_output_with_a_lost_packet() {
        let summary = parse_summary(IPUTILS).unwrap();
        assert_eq!(summary.transmitted, 3);
        assert_eq!(summary.received, 2);
        assert_eq!(summary.loss_percent, 33.3333);
        assert_eq!(summary.min_ms, Some(12.3));
        assert_eq!(summary.avg_ms, Some(13.7));
        assert_eq!(summary.max_ms, Some(15.1));
        assert_eq!(summary.jitter_ms, Some(1.4));
        assert_eq!(
            summary.replies,
            vec![
                Reply {
                    sequence: 1,
                    elapsed_ms: Some(12.3),
                    ttl: Some(57),
                    timeout: false
                },
                Reply {
                    sequence: 2,
                    elapsed_ms: Some(15.1),
                    ttl: Some(57),
                    timeout: false
                },
                Reply {
                    sequence: 3,
                    elapsed_ms: None,
                    ttl: None,
                    timeout: true
                },
            ]
        );
    }

    #[test]
    fn without_an_rtt_line_the_samples_are_measured_here() {
        let output = "PING x (1.2.3.4)\n\
64 bytes from 1.2.3.4: icmp_seq=1 ttl=64 time=10.0 ms\n\
64 bytes from 1.2.3.4: icmp_seq=2 ttl=64 time=20.0 ms\n\
\n\
2 packets transmitted, 2 received, 0% packet loss\n";
        let summary = parse_summary(output).unwrap();
        assert_eq!(summary.min_ms, Some(10.0));
        assert_eq!(summary.avg_ms, Some(15.0));
        assert_eq!(summary.max_ms, Some(20.0));
        assert_eq!(summary.jitter_ms, Some(5.0));
    }

    #[test]
    fn busybox_starts_at_zero_and_omits_the_totals() {
        // No `packets transmitted` / `received` lines: the counts come from the reply lines.
        let output = "PING 1.1.1.1 (1.1.1.1): 56 data bytes\n\
64 bytes from 1.1.1.1: seq=0 ttl=57 time=8.664 ms\n\
64 bytes from 1.1.1.1: seq=1 ttl=57 time=9.100 ms\n\
\n\
--- 1.1.1.1 ping statistics ---\n\
2 packets transmitted, 2 packets received, 0% packet loss\n";
        let summary = parse_summary(output).unwrap();
        assert_eq!(summary.transmitted, 2);
        assert_eq!(summary.received, 2);
        assert_eq!(summary.replies[0].sequence, 0);
        assert_eq!(summary.replies[1].sequence, 1);
    }

    #[test]
    fn ping6_output_without_ttl_still_parses() {
        let output = "PING 2001:db8::1(2001:db8::1) 56 data bytes\n\
64 bytes from 2001:db8::1: icmp_seq=1 ttl=64 time=1.05 ms\n\
\n\
--- 2001:db8::1 ping statistics ---\n\
1 packets transmitted, 1 received, 0% packet loss, time 0ms\n\
rtt min/avg/max/mdev = 1.050/1.050/1.050/0.000 ms\n";
        let summary = parse_summary(output).unwrap();
        assert_eq!(summary.replies.len(), 1);
        assert_eq!(summary.replies[0].ttl, Some(64));
        assert_eq!(summary.jitter_ms, Some(0.0));
    }

    #[test]
    fn a_run_without_the_loss_line_is_not_a_summary() {
        assert!(parse_summary("ping: unknown host nope.invalid\n").is_none());
        assert!(parse_summary("").is_none());
    }

    #[test]
    fn a_lost_first_packet_keeps_the_one_based_range() {
        // No `<n> received` line and an unparsable loss value: both fall back to the reply lines.
        let output = "64 bytes from 1.2.3.4: icmp_seq=2 ttl=57 time=20.0 ms\n\
2 packets transmitted, 1 received, 1.2.3% packet loss\n";
        let summary = parse_summary(output).unwrap();
        assert_eq!(summary.transmitted, 2);
        assert_eq!(summary.received, 1);
        assert!(summary.replies[0].timeout);
        assert_eq!(summary.replies[1].elapsed_ms, Some(20.0));
        assert_eq!(summary.loss_percent, 50.0);
    }

    #[test]
    fn a_missing_received_count_is_taken_from_the_replies() {
        let output = "64 bytes from 1.2.3.4: icmp_seq=1 ttl=57 time=20.0 ms\n\
2 packets transmitted, 0% packet loss\n";
        let summary = parse_summary(output).unwrap();
        assert_eq!(summary.received, 1);
        assert_eq!(summary.loss_percent, 0.0);
        assert_eq!(summary.replies.len(), 2);
    }

    #[test]
    fn latency_stats_follows_the_kotlin_arithmetic() {
        let stats = latency_stats(&[10.0, 20.0, 30.0]);
        assert_eq!(stats.min_ms, Some(10.0));
        assert_eq!(stats.avg_ms, Some(20.0));
        assert_eq!(stats.max_ms, Some(30.0));
        assert_eq!(stats.jitter_ms, Some(20.0 / 3.0));
        assert_eq!(stats.rounded_average_ms, 20);

        // Round half up, then clamp to one millisecond.
        assert_eq!(latency_stats(&[1.0, 2.0]).rounded_average_ms, 2);
        assert_eq!(latency_stats(&[0.2]).rounded_average_ms, 1);
        assert_eq!(latency_stats(&[]).rounded_average_ms, 1);
        assert_eq!(latency_stats(&[]).min_ms, None);

        // A single sample has no jitter at all (`jitterOf` needs two).
        assert_eq!(latency_stats(&[7.0]).jitter_ms, None);
    }
}
