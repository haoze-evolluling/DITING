//! Unit tests for the streaming scanner's pieces.

use super::*;

/// Feeds `input` through the scanner the way the Go `Read` loop does.
fn inject_all(link: &str, input: &[u8]) -> Vec<u8> {
    let mut injector = Injector::new(link.as_bytes().to_vec());
    let mut buf = vec![0u8; 4096];
    let mut out = Vec::new();
    let mut offset = 0usize;
    for _ in 0..64 {
        if injector.pending_len() > 0 {
            let n = injector.pending_into(&mut buf);
            out.extend_from_slice(&buf[..n]);
            continue;
        }
        let n = (input.len() - offset).min(buf.len());
        buf[..n].copy_from_slice(&input[offset..offset + n]);
        offset += n;
        let upstream = if offset >= input.len() {
            Upstream::EOF
        } else {
            Upstream::NONE
        };
        let outcome = injector.process(&mut buf, n, upstream);
        out.extend_from_slice(&buf[..outcome.out_len]);
        if upstream.eof && outcome.keep_error {
            while injector.pending_len() > 0 {
                let drained = injector.pending_into(&mut buf);
                out.extend_from_slice(&buf[..drained]);
            }
            break;
        }
    }
    out
}

#[test]
fn head_marker_is_matched_without_case() {
    assert_eq!(find_ignore_ascii_case(b"<HEAD>", b"<head"), Some(0));
    assert_eq!(find_ignore_ascii_case(b"xx<HeAd", b"<head"), Some(2));
    assert_eq!(find_ignore_ascii_case(b"<hea", b"<head"), None);
    assert_eq!(find_ignore_ascii_case(b"", b"<head"), None);
    assert_eq!(find_ignore_ascii_case(b"x", b""), Some(0));
}

#[test]
fn partial_marker_picks_the_shortest_suffix() {
    assert_eq!(partial_marker_len(b"abc<"), Some(1));
    assert_eq!(partial_marker_len(b"abc<he"), Some(3));
    // Only the last four bytes can be held back, so a complete `<head` is never a partial marker
    // (the finder already saw it); a four-byte prefix still is.
    assert_eq!(partial_marker_len(b"abc<HEA"), Some(4));
    assert_eq!(partial_marker_len(b"abc<HEAD"), None);
    assert_eq!(partial_marker_len(b"abc"), None);
    assert_eq!(partial_marker_len(b""), None);
    assert_eq!(partial_marker_len(b"<he"), Some(3));
}

#[test]
fn tag_is_spliced_after_the_opening_head() {
    let out = inject_all("[LINK]", b"<html><head><body>x</body></html>");
    assert_eq!(
        String::from_utf8_lossy(&out),
        "<html><head>[LINK]<body>x</body></html>"
    );
}

#[test]
fn attribute_carrying_head_is_spliced_after_its_gt() {
    let out = inject_all("[LINK]", b"<head data-a=\"1\"><body>");
    assert_eq!(
        String::from_utf8_lossy(&out),
        "<head data-a=\"1\">[LINK]<body>"
    );
}

#[test]
fn document_without_head_passes_through() {
    let document = b"<html><body>no head here</body></html>";
    assert_eq!(inject_all("[LINK]", document), document.to_vec());
}

#[test]
fn partial_marker_is_flushed_when_the_stream_ends() {
    // `io.ReadAll` feeds `<html><body><head` and then reads again, so the partial tag is still in
    // carry when the zero-length EOF read arrives; those bytes are the document's tail.
    let mut injector = Injector::new(b"[LINK]".to_vec());
    let mut buf = [0u8; 64];
    let document = b"<html><body><head";
    buf[..document.len()].copy_from_slice(document);
    let outcome = injector.process(&mut buf, document.len(), Upstream::NONE);
    assert_eq!(
        String::from_utf8_lossy(&buf[..outcome.out_len]),
        "<html><body>"
    );

    let outcome = injector.process(&mut buf, 0, Upstream::EOF);
    assert!(outcome.keep_error);
    assert_eq!(String::from_utf8_lossy(&buf[..outcome.out_len]), "<head");
}

#[test]
fn scanning_stops_after_the_limit() {
    let document = vec![b'a'; SCAN_LIMIT + 1];
    assert_eq!(inject_all("[LINK]", &document), document);
}

#[test]
fn pending_drains_before_the_next_upstream_read() {
    let mut injector = Injector::new(b"0123456789".to_vec());
    let mut buf = vec![0u8; 8];
    let document = b"<head>";
    buf[..document.len()].copy_from_slice(document);
    let outcome = injector.process(&mut buf, document.len(), Upstream::NONE);
    assert_eq!(String::from_utf8_lossy(&buf[..outcome.out_len]), "<head>01");
    assert!(injector.pending_len() > 0);

    let mut served = Vec::new();
    let mut chunk = [0u8; 8];
    while injector.pending_len() > 0 {
        let n = injector.pending_into(&mut chunk);
        served.extend_from_slice(&chunk[..n]);
    }
    assert_eq!(String::from_utf8_lossy(&served), "23456789");
}

#[test]
fn non_utf8_bytes_before_the_marker_keep_the_index() {
    // The old reader lower-cased a copy with `bytes.ToLower`, which turns every invalid byte into a
    // three-byte U+FFFD and made the marker index point past the buffer (it panicked outright).
    let document = b"\xb0\xa1<head><body>";
    let out = inject_all("[LINK]", document);
    // The marker survives, the tag lands right after it, and the junk bytes are untouched.
    assert!(out.starts_with(b"\xb0\xa1<head>[LINK]<body>"));
}

#[test]
fn rune_that_shrinks_when_lowered_keeps_the_index() {
    // `İ` (U+0130) lowers to a one-byte `i` in Go's mapping, so the old index walked backwards and
    // the tag landed inside the marker. The byte-wise scan cannot shift.
    let document = "\u{130}<head><body>".as_bytes();
    let out = inject_all("[LINK]", document);
    assert!(out.ends_with(b"<head>[LINK]<body>"));
}
