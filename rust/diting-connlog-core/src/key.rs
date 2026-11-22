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
