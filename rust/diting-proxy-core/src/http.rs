use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;

pub fn connect_request(target: &str, username: &str, password: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(160);
    out.extend_from_slice(b"CONNECT ");
    out.extend_from_slice(target.as_bytes());
    out.extend_from_slice(b" HTTP/1.1\r\nHost: ");
    out.extend_from_slice(target.as_bytes());
    out.extend_from_slice(b"\r\nUser-Agent: Go-http-client/1.1\r\n");
    if !username.is_empty() || !password.is_empty() {
        let token = STANDARD.encode(format!("{username}:{password}"));
        out.extend_from_slice(b"Proxy-Authorization: Basic ");
        out.extend_from_slice(token.as_bytes());
        out.extend_from_slice(b"\r\n");
    }
    out.extend_from_slice(b"\r\n");
    out
}

#[cfg(test)]
mod tests;
