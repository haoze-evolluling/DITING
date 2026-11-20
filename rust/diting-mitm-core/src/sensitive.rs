pub const SENSITIVE_KEYWORDS: &[&str] = &[
    "bank",
    "pay",
    "payment",
    "auth",
    "oauth",
    "login",
    "signin",
    "token",
    "secure",
    "wallet",
    "crypto",
    "trading",
    "invest",
    "finance",
    "insurance",
    "healthcare",
    "medical",
    "gov",
];

const PAYMENT_BRANDS: &[&str] = &[
    "paypal",
    "alipay",
    "tenpay",
    "wechatpay",
    "unionpay",
    "applepay",
    "googlepay",
];

const PAYMENT_SUBSTRINGS: &[&str] = &["alipay", "paypal", "wechatpay"];

const BANK_MIN_LEN: usize = 6;

pub fn is_sensitive_host(host: &str) -> bool {
    for label in host.split('.') {
        if label.is_empty() {
            continue;
        }

        if SENSITIVE_KEYWORDS.contains(&label) {
            return true;
        }

        for token in label.split(['-', '_']) {
            if SENSITIVE_KEYWORDS.contains(&token) {
                return true;
            }
        }

        if label.len() >= BANK_MIN_LEN && (label.ends_with("bank") || label.starts_with("bank")) {
            return true;
        }

        if PAYMENT_BRANDS.contains(&label) {
            return true;
        }
        if PAYMENT_SUBSTRINGS
            .iter()
            .any(|needle| label.contains(needle))
        {
            return true;
        }
    }
    false
}

pub fn is_ip_address(host: &str) -> bool {
    if host.contains(':') {
        return true;
    }
    !host.is_empty() && host.chars().all(|c| c == '.' || c.is_ascii_digit())
}

#[cfg(test)]
mod tests;
