use std::net::IpAddr;
use std::sync::LazyLock;
use std::time::Duration;

use regex::Regex;

use super::host;
use super::process::{self, RunError};
use super::{TraceHop, TraceRequest, TraceResponse};

static HOP_LINE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*(\d+)\s+(.+)$").expect("trace hop pattern"));

static ELAPSED: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"([0-9]+(?:\.[0-9]+)?)\s*(?:ms|毫秒)").expect("trace elapsed pattern")
});

pub async fn trace(request: &TraceRequest) -> Result<TraceResponse, String> {
    let target = host::validate_target(&request.target)?;
    let max_hops = request.max_hops.unwrap_or(30).clamp(1, 64);

    let address = resolve(&target).await?;
    let total = Duration::from_secs((u64::from(max_hops) * 3 + 10).min(180));
    let output = execute(address, max_hops, total).await?;
    Ok(parse(&output, &target, address, max_hops))
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
        vec!["tracert"]
    } else if address.is_ipv6() {
        vec!["traceroute6", "traceroute"]
    } else {
        vec!["traceroute"]
    }
}

fn arguments(address: IpAddr, max_hops: u32) -> Vec<String> {
    if cfg!(windows) {
        vec![
            "-d".to_string(),
            "-h".to_string(),
            max_hops.to_string(),
            "-w".to_string(),
            "2000".to_string(),
            address.to_string(),
        ]
    } else {
        vec![
            "-n".to_string(),
            "-m".to_string(),
            max_hops.to_string(),
            "-q".to_string(),
            "1".to_string(),
            "-w".to_string(),
            "2".to_string(),
            address.to_string(),
        ]
    }
}

async fn execute(address: IpAddr, max_hops: u32, total: Duration) -> Result<String, String> {
    let args = arguments(address, max_hops);
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
        Err("系统未安装 traceroute / tracert，无法执行路由追踪".to_string())
    } else {
        Err(last_error)
    }
}

fn parse(output: &str, target: &str, resolved: IpAddr, max_hops: u32) -> TraceResponse {
    let mut hops = Vec::new();
    let mut reached = false;

    for line in output.lines() {
        let Some(captures) = HOP_LINE.captures(line) else {
            continue;
        };
        let Some(index) = captures
            .get(1)
            .and_then(|value| value.as_str().parse::<u32>().ok())
        else {
            continue;
        };
        if index == 0 || index > max_hops {
            continue;
        }
        let rest = captures.get(2).map(|value| value.as_str()).unwrap_or("");
        let address = first_address(rest);
        let elapsed_ms = ELAPSED
            .captures(rest)
            .and_then(|captures| captures.get(1))
            .and_then(|value| value.as_str().parse::<f64>().ok());
        let timeout = address.is_none() && elapsed_ms.is_none();
        if address.is_some_and(|address| address == resolved) {
            reached = true;
        }
        hops.push(TraceHop {
            hop: index as i32,
            address: address.map(|address| address.to_string()),
            elapsed_ms,
            timeout,
        });
        if reached {
            break;
        }
    }

    let message = if reached {
        String::new()
    } else if hops.is_empty() {
        first_line(output).unwrap_or_else(|| "未能解析路由追踪结果".to_string())
    } else {
        format!("经 {} 跳仍未到达目标", hops.len())
    };

    TraceResponse {
        target: target.to_string(),
        resolved_address: resolved.to_string(),
        hops,
        reached,
        message,
    }
}

fn first_address(text: &str) -> Option<IpAddr> {
    text.split_whitespace().find_map(|token| {
        let token = token.trim_matches(|c| matches!(c, '[' | ']' | '(' | ')' | ',' | '.'));
        token.parse::<IpAddr>().ok()
    })
}

fn first_line(output: &str) -> Option<String> {
    let line = output
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())?;
    Some(line.chars().take(160).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_unix_traceroute() {
        let output = "traceroute to 1.1.1.1 (1.1.1.1), 30 hops max, 60 byte packets\n\
 1  192.168.1.1  1.234 ms\n\
 2  *\n\
 3  1.1.1.1  12.345 ms\n";
        let result = parse(output, "one.one.one.one", "1.1.1.1".parse().unwrap(), 30);
        assert_eq!(result.hops.len(), 3);
        assert_eq!(result.hops[0].address.as_deref(), Some("192.168.1.1"));
        assert_eq!(result.hops[0].elapsed_ms, Some(1.234));
        assert!(result.hops[1].timeout);
        assert!(result.reached);
    }

    #[test]
    fn parses_windows_tracert() {
        let output = "通过最多 30 个跃点跟踪到 1.1.1.1 的路由\n\
  1    <1 ms    <1 ms    <1 ms  192.168.1.1\n\
  2     *        *        *     请求超时。\n\
  3    12 ms    13 ms    12 ms  1.1.1.1\n\
跟踪完成。\n";
        let result = parse(output, "1.1.1.1", "1.1.1.1".parse().unwrap(), 30);
        assert_eq!(result.hops.len(), 3);
        assert_eq!(result.hops[0].elapsed_ms, Some(1.0));
        assert!(result.hops[1].timeout);
        assert!(result.reached);
    }

    #[test]
    fn a_run_that_never_reaches_reports_the_hop_count() {
        let output = " 1  192.168.1.1  1.0 ms\n 2  *\n";
        let result = parse(output, "example.com", "93.184.216.34".parse().unwrap(), 2);
        assert!(!result.reached);
        assert_eq!(result.message, "经 2 跳仍未到达目标");
    }

    #[test]
    fn bracketed_ipv6_tokens_are_accepted() {
        assert_eq!(
            first_address("[2001:db8::1] 1.2 ms"),
            Some("2001:db8::1".parse().unwrap())
        );
        assert_eq!(first_address("* * *"), None);
    }
}
