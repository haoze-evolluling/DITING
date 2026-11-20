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
use tokio::io::{AsyncRead, BufReader, ReadBuf};
use tokio_util::io::{ReaderStream, StreamReader};

use crate::mitm::http::{BoxError, ResponseBody};

pub const READ_CHUNK: usize = 16 * 1024;

pub fn request_accepts_html(accept: &str) -> bool {
    accept.to_ascii_lowercase().contains("text/html")
}

pub fn is_html(content_type: &str) -> bool {
    content_type.to_ascii_lowercase().contains("text/html")
}

pub fn strip_accept_encoding(headers: &mut HeaderMap) {
    let accepts_html = headers
        .get(http::header::ACCEPT)
        .and_then(|value| value.to_str().ok())
        .is_some_and(request_accepts_html);
    if accepts_html {
        headers.remove(ACCEPT_ENCODING);
    }
}

pub fn passthrough(upstream: Response<Incoming>) -> Response<ResponseBody> {
    let (parts, body) = upstream.into_parts();
    Response::from_parts(parts, passthrough_body(body))
}

fn passthrough_body(body: Incoming) -> ResponseBody {
    body.map_err(|error| -> BoxError { Box::new(error) })
        .boxed_unsync()
}

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
            let head = match tokio::io::AsyncBufReadExt::fill_buf(&mut buffered).await {
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

    parts.headers.remove(http::header::CONTENT_LENGTH);
    parts.headers.remove(CONTENT_ENCODING);
    parts.headers.remove(http::header::TRANSFER_ENCODING);
    parts.headers.remove("content-security-policy");
    parts.headers.remove("content-security-policy-report-only");

    let reader = InjectingReader::new(reader, Injector::new(link.as_bytes().to_vec()));
    let stream = ReaderStream::new(reader).map(|item| {
        item.map(Frame::data)
            .map_err(|error| -> BoxError { Box::new(error) })
    });
    Response::from_parts(parts, StreamBody::new(stream).boxed_unsync())
}

fn body_reader(
    body: Incoming,
) -> StreamReader<impl futures_util::Stream<Item = io::Result<Bytes>>, Bytes> {
    let stream = BodyExt::into_data_stream(body).map(|item| item.map_err(io::Error::other));
    StreamReader::new(stream)
}

pub fn is_zlib_stream(head: &[u8]) -> bool {
    if head.len() < 2 {
        return false;
    }
    let cmf = head[0];
    let flg = head[1];
    (cmf & 0x0f) == 8 && (cmf >> 4) <= 7 && (u16::from(cmf) * 256 + u16::from(flg)) % 31 == 0
}

pub struct InjectingReader<R> {
    inner: R,
    injector: Injector,
    pending: Vec<u8>,
    pending_at: usize,
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

    pub fn injected(&self) -> bool {
        self.injector.injected()
    }

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
                Poll::Ready(Err(error)) => return Poll::Ready(Err(error)),
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
                this.done = true;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::AsyncReadExt;

    #[test]
    fn only_html_requests_lose_accept_encoding() {
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
