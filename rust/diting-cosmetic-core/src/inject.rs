pub const SCAN_LIMIT: usize = 16 * 1024;

pub const HEAD_TAG: &[u8] = b"<head";

pub const HEAD_CARRY: usize = HEAD_TAG.len() - 1;

pub const UPSTREAM_ERRORED: u32 = 1 << 0;

pub const UPSTREAM_EOF: u32 = 1 << 1;

#[derive(Clone, Copy, Debug)]
pub struct Upstream {
    pub errored: bool,
    pub eof: bool,
}

impl Upstream {
    pub const NONE: Upstream = Upstream {
        errored: false,
        eof: false,
    };
    pub const EOF: Upstream = Upstream {
        errored: true,
        eof: true,
    };
    pub const FAILED: Upstream = Upstream {
        errored: true,
        eof: false,
    };

    pub fn from_abi(flags: u32) -> Upstream {
        Upstream {
            errored: flags & UPSTREAM_ERRORED != 0,
            eof: flags & UPSTREAM_EOF != 0,
        }
    }

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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Outcome {
    pub out_len: usize,
    pub keep_error: bool,
}

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

#[derive(Debug)]
pub struct Injector {
    link: Vec<u8>,
    injected: bool,
    pending: Vec<u8>,
    carry: Vec<u8>,
    scanned: usize,
}

impl Injector {
    pub fn new(link: Vec<u8>) -> Injector {
        Injector {
            link,
            injected: false,
            pending: Vec::new(),
            carry: Vec::new(),
            scanned: 0,
        }
    }

    pub fn injected(&self) -> bool {
        self.injected
    }

    pub fn pending_len(&self) -> usize {
        self.pending.len()
    }

    pub fn scanned(&self) -> usize {
        self.scanned
    }

    pub fn pending_into(&mut self, out: &mut [u8]) -> usize {
        let written = self.pending.len().min(out.len());
        out[..written].copy_from_slice(&self.pending[..written]);
        self.pending.drain(..written);
        written
    }

    pub fn process(&mut self, buf: &mut [u8], n: usize, upstream: Upstream) -> Outcome {
        let capacity = buf.len();
        let n = n.min(capacity);

        if n == 0 {
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
            self.injected = true;
            return self.deliver(buf, &data, upstream);
        }

        let Some(index) = find_ignore_ascii_case(&data, HEAD_TAG) else {
            let Some(partial) = partial_marker_len(&data) else {
                return self.deliver(buf, &data, upstream);
            };
            let keep = data.len() - partial;
            self.carry = data[keep..].to_vec();
            return self.deliver_prefix(buf, &data[..keep], upstream);
        };

        let Some(close) = data[index..].iter().position(|byte| *byte == b'>') else {
            self.carry = data[index..].to_vec();
            return self.deliver_prefix(buf, &data[..index], upstream);
        };

        self.do_inject(buf, &data, index + close + 1, upstream)
    }

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

    fn deliver_prefix(&mut self, buf: &mut [u8], data: &[u8], upstream: Upstream) -> Outcome {
        if data.is_empty() {
            return Outcome {
                out_len: 0,
                keep_error: true,
            };
        }
        self.deliver(buf, data, upstream)
    }

    fn do_inject(
        &mut self,
        buf: &mut [u8],
        data: &[u8],
        tag_end: usize,
        upstream: Upstream,
    ) -> Outcome {
        self.injected = true;

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

pub fn partial_marker_len(data: &[u8]) -> Option<usize> {
    let window = HEAD_CARRY.min(data.len());
    let tail = &data[data.len() - window..];
    (1..=window).find(|i| tail[window - i..].eq_ignore_ascii_case(&HEAD_TAG[..*i]))
}

fn copy_into(buffer: &mut [u8], data: &[u8]) -> usize {
    let written = buffer.len().min(data.len());
    buffer[..written].copy_from_slice(&data[..written]);
    written
}

#[cfg(test)]
mod tests;
