//! `isSensitiveHost` and `isIPAddress`: the heuristics that keep banking, payment and identity
//! endpoints out of the interception path.
//!
//! Both are field-for-field ports. `strings.Split(host, ".")` keeps empty labels and they are
//! skipped; `strings.FieldsFunc` splits on `-` and `_` in that same order; the `bank` prefix and
//! suffix checks use the label's *byte* length (`len(lbl)` in Go), which the labels here keep.
//!
//! Note the deliberate quirk in [`is_ip_address`]: only the presence of a colon or "nothing but
//! digits and dots" is checked, so `1.2.3.4.5` counts as an address and never gets intercepted.
//! That is what the Go original did and what the tests pin.

/// The keywords of `sniSensitiveKeywords`, in the original order.
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

/// Payment brands matched as whole labels.
const PAYMENT_BRANDS: &[&str] = &[
    "paypal",
    "alipay",
    "tenpay",
    "wechatpay",
    "unionpay",
    "applepay",
    "googlepay",
];

/// Substrings that mark any label as a payment endpoint.
const PAYMENT_SUBSTRINGS: &[&str] = &["alipay", "paypal", "wechatpay"];

/// `bank` needs this many bytes before the prefix/suffix match counts.
const BANK_MIN_LEN: usize = 6;

/// `isSensitiveHost`.
pub fn is_sensitive_host(host: &str) -> bool {
    for label in host.split('.') {
        if label.is_empty() {
            continue;
        }

        if SENSITIVE_KEYWORDS.contains(&label) {
            return true;
        }

        for token in label.split(['-', '_']) {
            // FieldsFunc drops empty tokens; `split` keeps them and no keyword is empty.
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

/// `isIPAddress`.
pub fn is_ip_address(host: &str) -> bool {
    if host.contains(':') {
        return true;
    }
    !host.is_empty() && host.chars().all(|c| c == '.' || c.is_ascii_digit())
}

#[cfg(test)]
mod tests;
