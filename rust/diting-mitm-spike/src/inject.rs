//! The response side of the relay: `Accept-Encoding` stripping and the streaming injected body.
//!
//! `mitm_relay.go` + `mitm_common.go` did four things here, and each one has a counterpart:
//!
//! 1. `requestAcceptsHTML(req)` → `req.Header.Del("Accept-Encoding")` so the upstream sends the page
//!    uncompressed and the scanner can splice into it while it streams ([`strip_accept_encoding`]).
//! 2. `ShouldInjectHTML(contentType)` → [`is_html`].
//! 3. `wrapResponseForInjection` → [`inject_html`]: pick a decoder from `Content-Encoding`
//!    (`gzip`, `deflate`, identity), splice the `<link>` with the kernel's scanner, and drop the
//!    headers that no longer describe the body.
//! 4. `injectingReader` → [`InjectingReader`], the `AsyncRead` adapter around
//!    [`diting_cosmetic_core::Injector`].
//!
//! Two deliberate differences from Go:
//!
//! * `deflate` is disambiguated from the two-byte zlib header instead of "read the whole body, try
//!   zlib, retry as raw deflate". Go buffered the entire page in memory for that fallback; sniffing
//!   is exact for every valid zlib stream and keeps the body streaming.
//! * an injected response is chunked, so the connection stays usable. Go had to force
//!   `Connection: close` because `net/http` refuses to chunk a response whose `Uncompressed` flag is
//!   set; hyper frames an unknown-length body itself, and `keep-alive` survives.

use std::io;
use std::pin::Pin;
use std::task::{Context, Poll};

use async_compression::tokio::bufread::{DeflateDecoder, GzipDecoder, ZlibDecoder};
use bytes::Bytes;
use diting_cosmetic_core::inject::Upstream;
use diting_cosmetic_core::Injector;
use futures_util::StreamExt;
use http::header::{HeaderMap, ACCEPT_ENCODING, CONTENT_ENCODING};
use http::Response;
use http_body_util::{BodyExt, StreamBody};
use hyper::body::{Frame, Incoming};
use tokio::io::{AsyncBufReadExt, AsyncRead, BufReader, ReadBuf};
use tokio_util::io::{ReaderStream, StreamReader};

use crate::{BoxError, ResponseBody};

/// How much the adapter asks the upstream (or the decoder) for per poll.
///
/// Larger than the kernel's 16 KiB scan limit on purpose: the link tag is spliced into the caller's
/// buffer, and the buffer has to have room for `n + tag.len()` so a splice never has to park bytes.
pub const READ_CHUNK: usize = 16 * 1024;

/// `requestAcceptsHTML`.
pub fn request_accepts_html(accept: &str) -> bool {
    accept.to_ascii_lowercase().contains("text/html")
}

/// `ShouldInjectHTML`.
pub fn is_html(content_type: &str) -> bool {
    content_type.to_ascii_lowercase().contains("text/html")
}

/// `if requestAcceptsHTML(req) { req.Header.Del("Accept-Encoding") }`.
pub fn strip_accept_encoding(headers: &mut HeaderMap) {
    let accepts_html = headers
        .get(http::header::ACCEPT)
        .and_then(|value| value.to_str().ok())
        .is_some_and(request_accepts_html);
    if accepts_html {
        headers.remove(ACCEPT_ENCODING);
    }
}

/// Returns the body untouched, re-boxed so every branch of the relay has one body type.
pub fn passthrough(upstream: Response<Incoming>) -> Response<ResponseBody> {
    let (parts, body) = upstream.into_parts();
    Response::from_parts(parts, passthrough_body(body))
}

fn passthrough_body(body: Incoming) -> ResponseBody {
    body.map_err(|err| -> BoxError { Box::new(err) })
        .boxed_unsync()
}

/// Decodes (when needed), splices the cosmetic `<link>` in, and re-frames the body as chunked.
///
/// The caller has already checked [`is_html`] and that a `<link>` tag exists; an encoding the relay
/// does not know is left alone (`default: return` in Go's `wrapResponseForInjection`).
pub async fn inject_html(upstream: Response<Incoming>, link: &str) -> Response<ResponseBody> {
    let (mut parts, body) = upstream.into_parts();
    let encoding = parts
        .headers
        .get(CONTENT_ENCODING)
        .and_then(|value| value.to_str().ok())
        .map(|value| value.trim().to_ascii_lowercase())
        .unwrap_or_default();

    if !matches!(encoding.as_str(), "" | "identity" | "gzip" | "deflate") {
        return Response::from_parts(parts, passthrough_body(body));
    }

    let reader: Box<dyn AsyncRead + Send + Unpin> = match encoding.as_str() {
        "gzip" => Box::new(GzipDecoder::new(BufReader::new(body_reader(body)))),
        "deflate" => {
            let mut buffered = BufReader::new(body_reader(body));
            // `fill_buf` does not consume: the decoder still sees the two bytes it was sniffed on.
            let head = match buffered.fill_buf().await {
                Ok(head) => head.to_vec(),
                Err(_) => Vec::new(),
            };
            if is_zlib_stream(&head) {
                Box::new(ZlibDecoder::new(buffered))
            } else {
                Box::new(DeflateDecoder::new(buffered))
            }
        }
        _ => Box::new(body_reader(body)),
    };

    // The headers Go dropped: the body length, the encoding and the framing are all decided here
    // now, and the injected page is no longer covered by the upstream's CSP.
    parts.headers.remove(http::header::CONTENT_LENGTH);
    parts.headers.remove(CONTENT_ENCODING);
    parts.headers.remove(http::header::TRANSFER_ENCODING);
    parts.headers.remove("content-security-policy");
    parts.headers.remove("content-security-policy-report-only");

    let reader = InjectingReader::new(reader, Injector::new(link.as_bytes().to_vec()));
    let stream = ReaderStream::new(reader).map(|item| {
        item.map(Frame::data)
            .map_err(|err| -> BoxError { Box::new(err) })
    });
    Response::from_parts(parts, StreamBody::new(stream).boxed_unsync())
}

fn body_reader(
    body: Incoming,
) -> StreamReader<impl futures_util::Stream<Item = io::Result<Bytes>>, Bytes> {
    let stream = BodyExt::into_data_stream(body).map(|item| item.map_err(io::Error::other));
    StreamReader::new(stream)
}

/// Whether `head` starts a zlib stream (`RFC 1950`: `CM == 8`, `CINFO <= 7`, `(CMF<<8|FLG) % 31 == 0`).
pub fn is_zlib_stream(head: &[u8]) -> bool {
    if head.len() < 2 {
        return false;
    }
    let cmf = head[0];
    let flg = head[1];
    (cmf & 0x0f) == 8 && (cmf >> 4) <= 7 && (u16::from(cmf) * 256 + u16::from(flg)) % 31 == 0
}

/// `injectingReader`: an `AsyncRead` that runs everything it reads through the cosmetic scanner.
pub struct InjectingReader<R> {
    inner: R,
    injector: Injector,
    /// Bytes the scanner produced that the caller's buffer had no room for.
    pending: Vec<u8>,
    pending_at: usize,
    /// Scratch buffer handed to the upstream/decoder, then to the scanner.
    scratch: Vec<u8>,
    done: bool,
}

impl<R> InjectingReader<R> {
    pub fn new(inner: R, injector: Injector) -> InjectingReader<R> {
        InjectingReader {
            inner,
            injector,
            pending: Vec::new(),
            pending_at: 0,
            scratch: vec![0; READ_CHUNK],
            done: false,
        }
    }

    /// Whether the scanner already spliced the tag in (or gave up scanning).
    pub fn injected(&self) -> bool {
        self.injector.injected()
    }

    /// Moves what the scanner had to park (a splice that did not fit the scratch buffer) into the
    /// adapter's own queue. Without this, a `<head>` close to a chunk boundary would lose the tail of
    /// the tag: `Injector::process` only ever reports `out_len`, the rest waits in its `pending`.
    fn take_injector_pending(&mut self) {
        let want = self.injector.pending_len();
        self.pending.resize(want, 0);
        let written = self.injector.pending_into(&mut self.pending);
        self.pending.truncate(written);
        self.pending_at = 0;
    }

    fn flush_pending(&mut self, buf: &mut ReadBuf<'_>) -> bool {
        let rest = &self.pending[self.pending_at..];
        if rest.is_empty() {
            return false;
        }
        let take = rest.len().min(buf.remaining());
        buf.put_slice(&rest[..take]);
        self.pending_at += take;
        if self.pending_at == self.pending.len() {
            self.pending.clear();
            self.pending_at = 0;
        }
        true
    }
}

impl<R: AsyncRead + Unpin> AsyncRead for InjectingReader<R> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        loop {
            if this.flush_pending(buf) {
                return Poll::Ready(Ok(()));
            }
            if this.injector.pending_len() > 0 {
                this.take_injector_pending();
                continue;
            }
            if this.done {
                return Poll::Ready(Ok(()));
            }

            this.scratch.resize(READ_CHUNK, 0);
            let mut chunk = ReadBuf::new(&mut this.scratch);
            let read = Pin::new(&mut this.inner).poll_read(cx, &mut chunk);
            let n = match read {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Err(err)) => return Poll::Ready(Err(err)),
                Poll::Ready(Ok(())) => chunk.filled().len(),
            };

            let upstream = if n == 0 {
                Upstream::EOF
            } else {
                Upstream::NONE
            };
            let outcome = this.injector.process(&mut this.scratch, n, upstream);
            let produced = outcome.out_len.min(this.scratch.len());
            this.pending.clear();
            this.pending_at = 0;
            this.pending.extend_from_slice(&this.scratch[..produced]);
            if n == 0 && this.pending.is_empty() && this.injector.pending_len() == 0 {
                // Clean end of the upstream body. A partial `<head` still parked in the scanner's
                // carry is dropped here, exactly like the Go reader did.
                this.done = true;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::AsyncReadExt;

    #[tokio::test]
    async fn only_html_requests_lose_accept_encoding() {
        let mut headers = HeaderMap::new();
        headers.insert(ACCEPT_ENCODING, "gzip, br".parse().unwrap());
        headers.insert(http::header::ACCEPT, "text/html,*/*".parse().unwrap());
        strip_accept_encoding(&mut headers);
        assert!(headers.get(ACCEPT_ENCODING).is_none());

        let mut headers = HeaderMap::new();
        headers.insert(ACCEPT_ENCODING, "gzip, br".parse().unwrap());
        headers.insert(http::header::ACCEPT, "application/json".parse().unwrap());
        strip_accept_encoding(&mut headers);
        assert_eq!(headers.get(ACCEPT_ENCODING).unwrap(), "gzip, br");
    }

    #[test]
    fn html_detection_matches_on_the_substring() {
        assert!(is_html("text/html; charset=utf-8"));
        assert!(is_html("TEXT/HTML"));
        assert!(!is_html("text/css"));
        assert!(!is_html(""));
    }

    #[test]
    fn zlib_streams_are_told_apart_from_raw_deflate() {
        assert!(is_zlib_stream(&[0x78, 0x9c]));
        assert!(is_zlib_stream(&[0x78, 0x01]));
        assert!(!is_zlib_stream(&[0x78, 0x00]), "checksum must be valid");
        assert!(!is_zlib_stream(&[0x00, 0x01]), "CM must be 8");
        assert!(!is_zlib_stream(&[0x78]), "one byte cannot be sniffed");
    }

    #[tokio::test]
    async fn the_adapter_splices_the_tag_into_a_streamed_body() {
        let html = b"<html><he".to_vec();
        let rest = b"ad><title>x</title></head></html>".to_vec();
        let reader = Fragmented::new(vec![html, rest], 7);
        let mut reader = InjectingReader::new(reader, Injector::new(b"<link rel=test>".to_vec()));
        let mut out = Vec::new();
        reader.read_to_end(&mut out).await.expect("read");
        assert_eq!(
            String::from_utf8(out).expect("utf-8"),
            "<html><head><link rel=test><title>x</title></head></html>"
        );
        assert!(reader.injected());
    }

    #[tokio::test]
    async fn a_body_without_html_is_forwarded_unchanged() {
        let payload: Vec<u8> = (0..=255u8).cycle().take(40_000).collect();
        let mut reader = InjectingReader::new(
            Fragmented::new(vec![payload.clone()], 1_000),
            Injector::new(b"<link rel=test>".to_vec()),
        );
        let mut out = Vec::new();
        reader.read_to_end(&mut out).await.expect("read");
        assert_eq!(out, payload, "no byte is touched without a <head>");
        // The scanner gives up past its 16 KiB limit, which is what marks the body as "not a page".
        assert!(reader.injector.scanned() > diting_cosmetic_core::SCAN_LIMIT);
    }

    #[tokio::test]
    async fn a_large_page_is_injected_once_and_fully_relayed() {
        let head = b"<html><head>".to_vec();
        let body = vec![b'x'; 200_000];
        let mut page = head.clone();
        page.extend_from_slice(&body);
        let mut reader = InjectingReader::new(
            Fragmented::new(vec![page], 4_096),
            Injector::new(b"<link rel=test>".to_vec()),
        );
        let mut out = Vec::new();
        reader.read_to_end(&mut out).await.expect("read");
        let text = String::from_utf8_lossy(&out).into_owned();
        assert!(text.starts_with("<html><head><link rel=test>x"));
        assert_eq!(
            out.len(),
            head.len() + body.len() + b"<link rel=test>".len()
        );
    }

    /// `<head>` landing inside the last bytes of a full chunk makes the splice overflow the scratch
    /// buffer, so the scanner parks the tail and the adapter has to serve it before reading more.
    #[tokio::test]
    async fn an_injection_at_a_full_chunk_boundary_keeps_every_byte() {
        let filler = vec![b'a'; READ_CHUNK - 10];
        let mut page = filler.clone();
        page.extend_from_slice(b"<head></head><body>tail</body>");
        let mut reader = InjectingReader::new(
            Fragmented::new(vec![page.clone()], usize::MAX),
            Injector::new(b"<link rel=test>".to_vec()),
        );
        let mut out = Vec::new();
        reader.read_to_end(&mut out).await.expect("read");

        let mut expected = filler;
        expected.extend_from_slice(b"<head><link rel=test></head><body>tail</body>");
        assert_eq!(out, expected);
        assert_eq!(reader.injector.pending_len(), 0);
    }

    /// A reader that hands out at most `fragment` bytes per poll, so the scanner sees the splits a
    /// real network delivers.
    struct Fragmented {
        chunks: std::collections::VecDeque<Vec<u8>>,
        current: Vec<u8>,
        offset: usize,
        fragment: usize,
    }

    impl Fragmented {
        fn new(chunks: Vec<Vec<u8>>, fragment: usize) -> Fragmented {
            Fragmented {
                chunks: chunks.into_iter().collect(),
                current: Vec::new(),
                offset: 0,
                fragment,
            }
        }
    }

    impl AsyncRead for Fragmented {
        fn poll_read(
            self: Pin<&mut Self>,
            _cx: &mut Context<'_>,
            buf: &mut ReadBuf<'_>,
        ) -> Poll<io::Result<()>> {
            let this = self.get_mut();
            if this.offset >= this.current.len() {
                let Some(next) = this.chunks.pop_front() else {
                    return Poll::Ready(Ok(()));
                };
                this.current = next;
                this.offset = 0;
                if this.current.is_empty() {
                    return Poll::Ready(Ok(()));
                }
            }
            let rest = &this.current[this.offset..];
            let take = rest.len().min(buf.remaining()).min(this.fragment);
            buf.put_slice(&rest[..take]);
            this.offset += take;
            Poll::Ready(Ok(()))
        }
    }
}
