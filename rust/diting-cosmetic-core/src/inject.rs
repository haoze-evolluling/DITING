//! The streaming `<head>` scanner.
//!
//! The engine reads a response body the way `net/http` does: the relay hands the reader a buffer and
//! forwards whatever comes back. The `<link>` tag has to be spliced in right after the first
//! `<head ...>` opening tag, which means the scanner may have to hold bytes back:
//!
//! * `carry` holds a trailing partial marker (`<`, `<h`, ...) or the whole `<head ...` fragment
//!   whose `>` has not arrived yet. It is prepended to the next read.
//! * `pending` holds bytes that did not fit into the caller's buffer, because the injected tag made
//!   the output longer than what the upstream read produced.
//!
//! Once the tag is in, or once [`SCAN_LIMIT`] bytes have gone by without a `<head`, the scanner
//! stops touching the stream and everything flows through unchanged.

/// How far into a response the scanner looks for `<head` before giving up.
pub const SCAN_LIMIT: usize = 16 * 1024;

/// The marker that puts the injection point right after it.
pub const HEAD_TAG: &[u8] = b"<head";

/// One byte less than [`HEAD_TAG`]: the longest prefix of it that can be held back.
pub const HEAD_CARRY: usize = HEAD_TAG.len() - 1;

/// ABI flag: the upstream read reported a non-nil error.
pub const UPSTREAM_ERRORED: u32 = 1 << 0;

/// ABI flag: that error was `io.EOF`.
pub const UPSTREAM_EOF: u32 = 1 << 1;

/// What the upstream read that produced the bytes being processed reported.
#[derive(Clone, Copy, Debug)]
pub struct Upstream {
    /// The read returned a non-nil error.
    pub errored: bool,
    /// That error was `io.EOF` (which in Go travels with the last chunk of data).
    pub eof: bool,
}

impl Upstream {
    /// A read that returned data and no error.
    pub const NONE: Upstream = Upstream {
        errored: false,
        eof: false,
    };
    /// A read that returned the last chunk of the body.
    pub const EOF: Upstream = Upstream {
        errored: true,
        eof: true,
    };
    /// A read that failed with something other than EOF.
    pub const FAILED: Upstream = Upstream {
        errored: true,
        eof: false,
    };

    /// Decodes the flags the C ABI passes this value in.
    pub fn from_abi(flags: u32) -> Upstream {
        Upstream {
            errored: flags & UPSTREAM_ERRORED != 0,
            eof: flags & UPSTREAM_EOF != 0,
        }
    }

    /// The flags the C ABI passes this value in.
    pub fn flags(self) -> u32 {
        let mut flags = 0;
        if self.errored {
            flags |= UPSTREAM_ERRORED;
        }
        if self.eof {
            flags |= UPSTREAM_EOF;
        }
        flags
    }
}

/// What the caller should report from one `Read`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Outcome {
    /// Bytes written into the caller's buffer.
    pub out_len: usize,
    /// Whether the upstream error travels with them. False means the caller returns `nil` so the
    /// queued bytes can drain first; the kernel never swallows an error that ends the stream.
    pub keep_error: bool,
}

/// `bytes.Index` over an ASCII case-folded view of the haystack.
///
/// The response may be any byte soup, so nothing is decoded as UTF-8: folding the ASCII range is
/// enough to find an ASCII marker and, unlike `bytes.ToLower`, it cannot change the length of the
/// buffer, which is what keeps the returned index usable on the original bytes.
pub fn find_ignore_ascii_case(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    if haystack.len() < needle.len() {
        return None;
    }
    haystack
        .windows(needle.len())
        .position(|window| window.eq_ignore_ascii_case(needle))
}

/// The injecting reader state.
#[derive(Debug)]
pub struct Injector {
    /// The `<link>` tag, already built for the page's hostname.
    link: Vec<u8>,
    injected: bool,
    pending: Vec<u8>,
    carry: Vec<u8>,
    scanned: usize,
}

impl Injector {
    /// A scanner that will splice `link` in after the first `<head ...>`.
    pub fn new(link: Vec<u8>) -> Injector {
        Injector {
            link,
            injected: false,
            pending: Vec::new(),
            carry: Vec::new(),
            scanned: 0,
        }
    }

    /// Whether the tag has already been spliced in (or scanning gave up).
    pub fn injected(&self) -> bool {
        self.injected
    }

    /// Bytes parked because they did not fit into the caller's buffer.
    pub fn pending_len(&self) -> usize {
        self.pending.len()
    }

    /// Byte count seen by the scanner, for the [`SCAN_LIMIT`] decision.
    pub fn scanned(&self) -> usize {
        self.scanned
    }

    /// Serves queued bytes, exactly like `copy(p, r.pending)` did.
    pub fn pending_into(&mut self, out: &mut [u8]) -> usize {
        let written = self.pending.len().min(out.len());
        out[..written].copy_from_slice(&self.pending[..written]);
        self.pending.drain(..written);
        written
    }

    /// Post-processes the `n` bytes a `Read` just put into `buf`.
    ///
    /// `buf` is the caller's whole buffer, `n` how much of it the upstream filled; the result says
    /// how much to report and whether the upstream error should travel with it.
    pub fn process(&mut self, buf: &mut [u8], n: usize, upstream: Upstream) -> Outcome {
        let capacity = buf.len();
        let n = n.min(capacity);

        if n == 0 {
            // The upstream is exhausted. A partial `<head` prefix parked in carry is the tail of the
            // document, not a marker, so it still has to reach the client.
            if !self.carry.is_empty() && upstream.errored {
                let data = std::mem::take(&mut self.carry);
                let written = copy_into(buf, &data);
                if written < data.len() {
                    self.pending = data[written..].to_vec();
                    return Outcome {
                        out_len: written,
                        keep_error: false,
                    };
                }
                return Outcome {
                    out_len: written,
                    keep_error: true,
                };
            }
            return Outcome {
                out_len: 0,
                keep_error: true,
            };
        }

        if self.injected {
            return Outcome {
                out_len: n,
                keep_error: true,
            };
        }

        let mut data = Vec::with_capacity(self.carry.len() + n);
        data.extend_from_slice(&self.carry);
        data.extend_from_slice(&buf[..n]);
        self.carry.clear();

        self.scanned += data.len();
        if self.scanned > SCAN_LIMIT {
            // Too far in to still be in `<head`; let the rest of the document through untouched.
            self.injected = true;
            return self.deliver(buf, &data, upstream);
        }

        let Some(index) = find_ignore_ascii_case(&data, HEAD_TAG) else {
            let Some(partial) = partial_marker_len(&data) else {
                return self.deliver(buf, &data, upstream);
            };
            // Hold the partial marker back until the next read can complete or refute it.
            let keep = data.len() - partial;
            self.carry = data[keep..].to_vec();
            return self.deliver_prefix(buf, &data[..keep], upstream);
        };

        let Some(close) = data[index..].iter().position(|byte| *byte == b'>') else {
            // `<head` is here but the tag is not closed yet: hold the whole tag fragment back.
            self.carry = data[index..].to_vec();
            return self.deliver_prefix(buf, &data[..index], upstream);
        };

        self.do_inject(buf, &data, index + close + 1, upstream)
    }

    /// Copies `data` out, queueing whatever does not fit, and decides about the upstream error.
    fn deliver(&mut self, buf: &mut [u8], data: &[u8], upstream: Upstream) -> Outcome {
        let written = copy_into(buf, data);
        if written < data.len() {
            self.pending = data[written..].to_vec();
        }
        Outcome {
            out_len: written,
            keep_error: !(upstream.eof && !self.pending.is_empty()),
        }
    }

    /// `deliver` for a fragment that may be empty, in which case there is nothing to report yet.
    fn deliver_prefix(&mut self, buf: &mut [u8], data: &[u8], upstream: Upstream) -> Outcome {
        if data.is_empty() {
            return Outcome {
                out_len: 0,
                keep_error: true,
            };
        }
        self.deliver(buf, data, upstream)
    }

    /// Splices the tag in after the `>` at `tag_end` and stops scanning.
    fn do_inject(
        &mut self,
        buf: &mut [u8],
        data: &[u8],
        tag_end: usize,
        upstream: Upstream,
    ) -> Outcome {
        self.injected = true;

        // The marker was found on the original bytes, so `tag_end` is a real index. The Go version
        // searched a lower-cased copy that `bytes.ToLower` may have resized; it is clamped here so a
        // non-UTF-8 page cannot slice past the buffer (see rust/README.md).
        let tag_end = tag_end.min(data.len());
        let before = &data[..tag_end];
        let after = &data[tag_end..];

        let mut combined = Vec::with_capacity(before.len() + self.link.len() + after.len());
        combined.extend_from_slice(before);
        combined.extend_from_slice(&self.link);
        combined.extend_from_slice(after);

        if combined.len() <= buf.len() {
            buf[..combined.len()].copy_from_slice(&combined);
            return Outcome {
                out_len: combined.len(),
                keep_error: true,
            };
        }

        let written = copy_into(buf, &combined);
        self.pending = combined[written..].to_vec();
        Outcome {
            out_len: written,
            keep_error: !(upstream.eof && !self.pending.is_empty()),
        }
    }
}

/// How many trailing bytes of `data` are a prefix of [`HEAD_TAG`], if any.
///
/// Only the last [`HEAD_CARRY`] bytes can be, and the shortest match wins, because that is what the
/// Go loop returned: it walked `i` from 1 upwards and stopped at the first suffix that matched.
pub fn partial_marker_len(data: &[u8]) -> Option<usize> {
    let window = HEAD_CARRY.min(data.len());
    let tail = &data[data.len() - window..];
    (1..=window).find(|i| tail[window - i..].eq_ignore_ascii_case(&HEAD_TAG[..*i]))
}

/// `copy(dst, src)` returning how many bytes were written.
fn copy_into(buffer: &mut [u8], data: &[u8]) -> usize {
    let written = buffer.len().min(data.len());
    buffer[..written].copy_from_slice(&data[..written]);
    written
}

#[cfg(test)]
mod tests;
