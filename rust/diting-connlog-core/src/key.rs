//! `connLogKey`, reproduced byte for byte.
//!
//! The Go version appended the ints with `strconv.AppendInt(..., 10)`, which is the plain decimal
//! spelling (negative values keep the leading `-`). Ports and protocols are non-negative here, but
//! the port is an `i32` on the boundary so the negative case is still pinned by a test.

/// Builds the dedupe key `[blk|]app|dest|port|proto[|reason]`.
pub fn build_key(
    prefix: &str,
    app: &str,
    dest: &str,
    port: i32,
    protocol: i32,
    reason: &str,
) -> String {
    let mut out = String::with_capacity(prefix.len() + app.len() + dest.len() + reason.len() + 16);
    out.push_str(prefix);
    out.push_str(app);
    out.push('|');
    out.push_str(dest);
    out.push('|');
    out.push_str(&port.to_string());
    out.push('|');
    out.push_str(&protocol.to_string());
    if !reason.is_empty() {
        out.push('|');
        out.push_str(reason);
    }
    out
}

#[cfg(test)]
mod tests;
