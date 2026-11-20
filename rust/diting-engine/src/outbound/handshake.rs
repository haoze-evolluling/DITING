use diting_proxy_core::http;
use diting_proxy_core::socks5::{self, AuthMethod, ReplyParse};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

const REPLY_MAX: usize = 4 + 1 + 255 + 2;
const HTTP_HEAD_MAX: usize = 16 * 1024;

pub async fn socks5_connect(
    stream: &mut TcpStream,
    username: &str,
    password: &str,
    target: &str,
) -> Result<(), String> {
    negotiate(stream, username, password).await?;
    let request = socks5::request(socks5::COMMAND_CONNECT, target)?;
    stream
        .write_all(&request)
        .await
        .map_err(|error| format!("SOCKS5 request: {error}"))?;
    read_reply(stream).await.map(|_| ())
}

pub async fn socks5_udp_associate(
    stream: &mut TcpStream,
    username: &str,
    password: &str,
) -> Result<String, String> {
    negotiate(stream, username, password).await?;
    stream
        .write_all(&socks5::udp_associate_request())
        .await
        .map_err(|error| format!("SOCKS5 UDP associate: {error}"))?;
    read_reply(stream)
        .await
        .map_err(|error| format!("SOCKS5 UDP associate: {error}"))
}

async fn negotiate(stream: &mut TcpStream, username: &str, password: &str) -> Result<(), String> {
    stream
        .write_all(&socks5::greeting(username, password))
        .await
        .map_err(|error| format!("SOCKS5 greeting: {error}"))?;
    let mut reply = [0u8; 2];
    stream
        .read_exact(&mut reply)
        .await
        .map_err(|_| "invalid SOCKS5 greeting response".to_string())?;
    if socks5::method_reply(&reply)? == AuthMethod::None {
        return Ok(());
    }
    stream
        .write_all(&socks5::auth_request(username, password))
        .await
        .map_err(|error| format!("SOCKS5 authentication: {error}"))?;
    stream
        .read_exact(&mut reply)
        .await
        .map_err(|_| "SOCKS5 authentication failed".to_string())?;
    socks5::auth_reply(&reply)
}

async fn read_reply(stream: &mut TcpStream) -> Result<String, String> {
    let mut buffer = vec![0u8; REPLY_MAX];
    let mut read = 0usize;
    loop {
        let needed = match socks5::parse_reply(&buffer[..read])? {
            ReplyParse::Done { address } => return Ok(address),
            ReplyParse::NeedMore(needed) => needed,
        };
        if needed > buffer.len() {
            return Err(format!("SOCKS5 reply frame is {needed} bytes"));
        }
        let filled = read_field(stream, &mut buffer, read, needed).await?;
        read = filled;
    }
}

async fn read_field(
    stream: &mut TcpStream,
    buffer: &mut [u8],
    read: usize,
    needed: usize,
) -> Result<usize, String> {
    let mut filled = read;
    while filled < needed {
        match stream.read(&mut buffer[filled..needed]).await {
            Ok(0) => {
                return Err(if read == 0 {
                    "SOCKS5 response: unexpected end of file".to_string()
                } else {
                    "unexpected end of file".to_string()
                });
            }
            Ok(count) => filled += count,
            Err(error) => {
                return Err(if read == 0 {
                    format!("SOCKS5 response: {error}")
                } else {
                    error.to_string()
                });
            }
        }
    }
    Ok(filled)
}

pub async fn http_connect(
    stream: &mut TcpStream,
    username: &str,
    password: &str,
    target: &str,
) -> Result<(), String> {
    stream
        .write_all(&http::connect_request(target, username, password))
        .await
        .map_err(|error| format!("HTTP CONNECT write: {error}"))?;
    let status = read_status(stream).await?;
    if status.code == 200 {
        Ok(())
    } else {
        Err(format!("HTTP proxy returned {}", status.text))
    }
}

struct Status {
    code: u16,
    text: String,
}

async fn read_status(stream: &mut TcpStream) -> Result<Status, String> {
    let mut head = Vec::with_capacity(256);
    let mut chunk = [0u8; 512];
    loop {
        if head.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
        if head.len() > HTTP_HEAD_MAX {
            return Err("HTTP CONNECT response: header too large".to_string());
        }
        match stream.read(&mut chunk).await {
            Ok(0) => return Err("HTTP CONNECT response: unexpected end of file".to_string()),
            Ok(count) => head.extend_from_slice(&chunk[..count]),
            Err(error) => return Err(format!("HTTP CONNECT response: {error}")),
        }
    }
    let line = head
        .split(|byte| *byte == b'\n')
        .next()
        .map(|line| String::from_utf8_lossy(line).trim().to_string())
        .unwrap_or_default();
    parse_status_line(&line)
}

fn parse_status_line(line: &str) -> Result<Status, String> {
    let mut parts = line.splitn(3, ' ');
    let _version = parts.next().unwrap_or_default();
    let code = parts
        .next()
        .and_then(|code| code.parse::<u16>().ok())
        .ok_or_else(|| format!("HTTP CONNECT response: malformed status line {line:?}"))?;
    let reason = parts.next().unwrap_or_default().trim();
    let text = if reason.is_empty() {
        code.to_string()
    } else {
        format!("{code} {reason}")
    };
    Ok(Status { code, text })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_status_line_becomes_the_status_text_go_reported() {
        let status = parse_status_line("HTTP/1.1 403 Forbidden").expect("status");
        assert_eq!(status.code, 403);
        assert_eq!(status.text, "403 Forbidden");
        let status = parse_status_line("HTTP/1.1 200").expect("status");
        assert_eq!(status.text, "200");
        assert!(parse_status_line("nonsense").is_err());
    }
}
