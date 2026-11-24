use std::net::IpAddr;
use std::sync::LazyLock;
use std::time::Duration;

use regex::Regex;

use super::host;
use super::process::{self, RunError};
use super::{PingReply, PingRequest, PingResponse};

static SAMPLE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(?:time|时间)\s*[=<>]\s*([0-9]+(?:\.[0-9]+)?)\s*(?:ms|毫秒)")
        .expect("ping sample pattern")
});

static TTL: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)ttl\s*[=:]\s*([0-9]+)").expect("ping ttl pattern"));

pub async fn ping(request: &PingRequest) -> Result<PingResponse, String> {
    let target = host::validate_target(&request.target)?;
    let count = request.count.unwrap_or(4).clamp(1, 20);
    let timeout_seconds = request.timeout_seconds.unwrap_or(3).clamp(1, 10);

    let address = resolve(&target).await?;
    let family = if address.is_ipv4() { "IPv4" } else { "IPv6" };
    let resolved = address.to_string();
    let total = Duration::from_secs((u64::from(count) * u64::from(timeout_seconds) + 5).min(120));

    let output = execute(address, count, timeout_seconds, total).await?;
    Ok(parse(&output, count, &target, &resolved, family))
}

async fn resolve(target: &str) -> Result<IpAddr, String> {
    let mut addresses = tokio::net::lookup_host((target, 0))
        .await
        .map_err(|error| format!("无法解析目标 {target}: {error}"))?;
    addresses
        .next()
        .map(|address| address.ip())
        .ok_or_else(|| format!("无法解析目标 {target}"))
}

fn candidates(address: IpAddr) -> Vec<&'static str> {
    if cfg!(windows) {
        vec!["ping"]
    } else if address.is_ipv6() {
        vec!["ping6", "ping"]
    } else {
        vec!["ping"]
    }
}

fn arguments(address: IpAddr, count: u32, timeout_seconds: u32) -> Vec<String> {
    if cfg!(windows) {
        vec![
            "-n".to_string(),
            count.to_string(),
            "-w".to_string(),
            (u64::from(timeout_seconds) * 1000).to_string(),
            if address.is_ipv4() { "-4" } else { "-6" }.to_string(),
            address.to_string(),
        ]
    } else {
        vec![
            "-c".to_string(),
            count.to_string(),
            "-W".to_string(),
            timeout_seconds.to_string(),
            address.to_string(),
        ]
    }
}

async fn execute(
    address: IpAddr,
    count: u32,
    timeout_seconds: u32,
    total: Duration,
) -> Result<String, String> {
    let args = arguments(address, count, timeout_seconds);
    let mut missing = true;
    let mut last_error = String::new();
    for program in candidates(address) {
        match process::run(program, &args, total).await {
            Ok(output) => return Ok(output),
            Err(RunError::NotFound) => continue,
            Err(error) => {
                missing = false;
                last_error = error.message(program);
            }
        }
    }
    if missing {
        Err("系统未找到 ping 命令，无法执行延迟测试".to_string())
    } else {
        Err(last_error)
    }
}

fn parse(output: &str, count: u32, target: &str, resolved: &str, family: &str) -> PingResponse {
    let mut samples: Vec<(f64, Option<i32>)> = Vec::new();
    for line in output.lines() {
        let Some(captures) = SAMPLE.captures(line) else {
            continue;
        };
        let Some(sample) = captures
            .get(1)
            .and_then(|value| value.as_str().parse().ok())
        else {
            continue;
        };
        let ttl = TTL
            .captures(line)
            .and_then(|captures| captures.get(1))
            .and_then(|value| value.as_str().parse().ok());
        samples.push((sample, ttl));
    }

    let received = samples.len().min(count as usize) as u32;
    let mut replies = Vec::with_capacity(count as usize);
    for index in 0..count {
        replies.push(match samples.get(index as usize) {
            Some((elapsed, ttl)) => PingReply {
                sequence: index as i32 + 1,
                elapsed_ms: Some(*elapsed),
                ttl: *ttl,
                timeout: false,
            },
            None => PingReply {
                sequence: index as i32 + 1,
                elapsed_ms: None,
                ttl: None,
                timeout: true,
            },
        });
    }

    let latencies: Vec<f64> = samples.iter().map(|(sample, _)| *sample).collect();
    let (min_ms, avg_ms, max_ms, jitter_ms) = stats(&latencies);
    let loss_percent = if count == 0 {
        100.0
    } else {
        f64::from(count - received) * 100.0 / f64::from(count)
    };

    PingResponse {
        target: target.to_string(),
        resolved_address: resolved.to_string(),
        address_family: family.to_string(),
        transmitted: count,
        received,
        loss_percent,
        min_ms,
        avg_ms,
        max_ms,
        jitter_ms,
        success: received > 0,
        message: if received == 0 {
            first_line(output).unwrap_or_else(|| "目标无响应".to_string())
        } else {
            String::new()
        },
        replies,
    }
}

fn stats(samples: &[f64]) -> (Option<f64>, Option<f64>, Option<f64>, Option<f64>) {
    let Some(first) = samples.first() else {
        return (None, None, None, None);
    };
    let mut min = *first;
    let mut max = *first;
    let mut sum = 0.0;
    for sample in samples {
        sum += sample;
        min = min.min(*sample);
        max = max.max(*sample);
    }
    let avg = sum / samples.len() as f64;
    let jitter = if samples.len() >= 2 {
        Some(
            samples
                .iter()
                .map(|sample| (sample - avg).abs())
                .sum::<f64>()
                / samples.len() as f64,
        )
    } else {
        None
    };
    (Some(min), Some(avg), Some(max), jitter)
}

fn first_line(output: &str) -> Option<String> {
    let line = output
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())?;
    let truncated: String = line.chars().take(160).collect();
    Some(truncated)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_iputils_output() {
        let output = "PING example.com (93.184.216.34) 56(84) bytes of data.\n\
64 bytes from 93.184.216.34: icmp_seq=1 ttl=57 time=12.3 ms\n\
64 bytes from 93.184.216.34: icmp_seq=2 ttl=57 time=15.1 ms\n\
\n--- example.com ping statistics ---\n\
2 packets transmitted, 2 received, 0% packet loss\n";
        let result = parse(output, 3, "example.com", "93.184.216.34", "IPv4");
        assert_eq!(result.received, 2);
        assert_eq!(result.transmitted, 3);
        assert_eq!(result.loss_percent, 100.0 / 3.0);
        assert_eq!(result.min_ms, Some(12.3));
        assert_eq!(result.max_ms, Some(15.1));
        assert_eq!(result.avg_ms, Some(13.7));
        assert!(result.replies[2].timeout);
        assert!(result.success);
    }

    #[test]
    fn parses_windows_localized_output() {
        let output = "正在 Ping 1.1.1.1 具有 32 字节的数据:\n\
来自 1.1.1.1 的回复: 字节=32 时间=12ms TTL=57\n\
来自 1.1.1.1 的回复: 字节=32 时间=13ms TTL=57\n\
\n1.1.1.1 的 Ping 统计信息:\n\
    数据包: 已发送 = 2，已接收 = 2，丢失 = 0 (0% 丢失)，\n";
        let result = parse(output, 2, "1.1.1.1", "1.1.1.1", "IPv4");
        assert_eq!(result.received, 2);
        assert_eq!(result.replies[0].ttl, Some(57));
        assert_eq!(result.avg_ms, Some(12.5));
        assert_eq!(result.loss_percent, 0.0);
    }

    #[test]
    fn a_silent_target_reports_loss_and_a_reason() {
        let output = "PING 10.255.255.1 (10.255.255.1) 56(84) bytes of data.\n\
\n--- 10.255.255.1 ping statistics ---\n\
4 packets transmitted, 0 received, 100% packet loss, time 3069ms\n";
        let result = parse(output, 4, "10.255.255.1", "10.255.255.1", "IPv4");
        assert!(!result.success);
        assert_eq!(result.received, 0);
        assert_eq!(result.loss_percent, 100.0);
        assert_eq!(
            result.message,
            "PING 10.255.255.1 (10.255.255.1) 56(84) bytes of data."
        );
        assert!(result.replies.iter().all(|reply| reply.timeout));
    }

    #[test]
    fn stats_need_two_samples_for_jitter() {
        let (_, avg, _, jitter) = stats(&[10.0]);
        assert_eq!(avg, Some(10.0));
        assert_eq!(jitter, None);
    }
}
