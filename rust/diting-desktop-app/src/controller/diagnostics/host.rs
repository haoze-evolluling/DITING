/// 清理用户输入里的协议、端口、路径与凭据，得到裸主机名。
pub fn sanitize(input: &str) -> String {
    let mut value = input.trim();
    if value.is_empty() {
        return String::new();
    }

    if let Some(index) = value.find("://") {
        value = &value[index + 3..];
    }
    if let Some(index) = value.find(['/', '?', '#']) {
        value = &value[..index];
    }
    if let Some(index) = value.rfind('@') {
        value = &value[index + 1..];
    }

    if let Some(rest) = value.strip_prefix('[') {
        return match rest.find(']') {
            Some(end) => rest[..end].to_string(),
            None => value.to_string(),
        };
    }

    if !value.contains("::") && value.matches(':').count() == 1 {
        let (host, port) = value.split_once(':').unwrap_or((value, ""));
        if !port.is_empty() && port.chars().all(|c| c.is_ascii_digit()) {
            return host.to_string();
        }
    }

    value.to_string()
}

pub fn is_ip_literal(value: &str) -> bool {
    let text = value.strip_prefix('[').unwrap_or(value);
    let text = text.strip_suffix(']').unwrap_or(text);
    if text.is_empty() {
        return false;
    }

    if !text.contains(':') {
        let parts: Vec<&str> = text.split('.').collect();
        if parts.len() != 4 {
            return false;
        }
        return parts.iter().all(|part| {
            !part.is_empty()
                && part.len() <= 3
                && part.chars().all(|c| c.is_ascii_digit())
                && part.parse::<u32>().is_ok_and(|value| value <= 255)
        });
    }

    if text.matches(':').count() < 2 {
        return false;
    }
    text.chars()
        .all(|c| c.is_ascii_digit() || c.is_ascii_hexdigit() || c == ':' || c == '.')
}

/// 校验用于解析的域名，返回去掉末尾点的小写形式。
pub fn validate_domain(input: &str) -> Result<String, String> {
    let host = sanitize(input);
    if host.is_empty() {
        return Err("请输入要查询的域名".to_string());
    }
    if is_ip_literal(&host) {
        return Err("DNS 查询需要域名，不能直接填写 IP 地址".to_string());
    }
    let domain = host.trim_end_matches('.').to_ascii_lowercase();
    if domain.is_empty() || domain.len() > 253 {
        return Err("域名长度不合法".to_string());
    }
    if domain
        .split('.')
        .any(|label| label.is_empty() || label.len() > 63)
    {
        return Err("域名格式不合法".to_string());
    }
    Ok(domain)
}

/// 网络诊断目标：域名或 IP 都可以，返回可直接交给系统工具的主机名。
pub fn validate_target(input: &str) -> Result<String, String> {
    let host = sanitize(input);
    if host.is_empty() {
        return Err("请输入诊断目标".to_string());
    }
    if host.len() > 253 || host.chars().any(|c| c.is_whitespace()) {
        return Err("诊断目标格式不合法".to_string());
    }
    Ok(host)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_strips_url_parts() {
        assert_eq!(
            sanitize("  https://user:pw@dns.google:8443/dns-query?x=1#f  "),
            "dns.google"
        );
        assert_eq!(sanitize("dns.google:53"), "dns.google");
        assert_eq!(sanitize("[2001:db8::1]:53"), "2001:db8::1");
        assert_eq!(sanitize(""), "");
    }

    #[test]
    fn domains_are_normalized_and_ips_rejected() {
        assert_eq!(validate_domain(" Example.COM. ").unwrap(), "example.com");
        assert!(validate_domain("1.1.1.1").is_err());
        assert!(validate_domain("a..b").is_err());
        assert!(validate_domain("").is_err());
    }

    #[test]
    fn targets_accept_domains_and_ips() {
        assert_eq!(validate_target(" 1.1.1.1 ").unwrap(), "1.1.1.1");
        assert_eq!(validate_target("example.com").unwrap(), "example.com");
        assert!(validate_target("  ").is_err());
    }
}
