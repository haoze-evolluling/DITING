use crate::snapshot::{LoadInput, Row, SnapshotInput};

pub const LAYOUT_VERSION: u8 = 1;

const NULL_TEXT: u32 = u32::MAX;

struct Reader<'a> {
    payload: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(payload: &'a [u8]) -> Option<Self> {
        if payload.first().copied()? != LAYOUT_VERSION {
            return None;
        }
        Some(Self {
            payload,
            position: 1,
        })
    }

    fn take(&mut self, length: usize) -> Option<&'a [u8]> {
        if self.payload.len() - self.position < length {
            return None;
        }
        let slice = &self.payload[self.position..self.position + length];
        self.position += length;
        Some(slice)
    }

    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }

    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }

    fn text(&mut self) -> Option<String> {
        let length = self.u32()? as usize;
        Some(String::from_utf8_lossy(self.take(length)?).into_owned())
    }

    fn optional_text(&mut self) -> Option<Option<String>> {
        if self.u32()? == NULL_TEXT {
            return Some(None);
        }
        self.position -= 4;
        Some(Some(self.text()?))
    }

    fn rows(&mut self) -> Option<Vec<Row>> {
        let count = self.u32()? as usize;
        if count > self.payload.len() {
            return None;
        }
        let mut rows = Vec::with_capacity(count.min(4096));
        for _ in 0..count {
            rows.push(self.row()?);
        }
        Some(rows)
    }

    fn row(&mut self) -> Option<Row> {
        let pattern = self.text()?;
        let source = self.text()?;
        let flags = self.u8()?;
        let app_scope = self.optional_text()?;
        let denyallow = self.optional_text()?;
        let dns_type = self.optional_text()?;
        Some(Row {
            pattern,
            source,
            important: flags & 1 != 0,
            app_scope,
            app_inverted: flags & 2 != 0,
            is_wildcard: flags & 4 != 0,
            denyallow,
            is_regex: flags & 8 != 0,
            dns_type,
        })
    }

    fn finished(&self) -> bool {
        self.position == self.payload.len()
    }
}

pub fn decode(payload: &[u8]) -> Option<SnapshotInput> {
    let mut reader = Reader::new(payload)?;
    let flags = reader.u8()?;
    let block_trie_path = reader.optional_text()?;
    let important_block_trie_path = reader.optional_text()?;
    let allow_trie_path = reader.optional_text()?;
    let important_allow_trie_path = reader.optional_text()?;
    let allowlist_count = reader.u32()? as usize;
    if allowlist_count > payload.len() {
        return None;
    }
    let mut app_allowlist = Vec::with_capacity(allowlist_count.min(1024));
    for _ in 0..allowlist_count {
        let package = reader.text()?;
        let domain_count = reader.u32()? as usize;
        if domain_count > payload.len() {
            return None;
        }
        let mut domains = Vec::with_capacity(domain_count.min(1024));
        for _ in 0..domain_count {
            domains.push(reader.text()?);
        }
        app_allowlist.push((package, domains));
    }
    let block_custom = reader.rows()?;
    let block_subscription = reader.rows()?;
    let allow_custom = reader.rows()?;
    let allow_subscription = reader.rows()?;
    if !reader.finished() {
        return None;
    }
    Some(SnapshotInput {
        filter_enabled: flags & 16 != 0,
        trie_paths: [
            block_trie_path,
            important_block_trie_path,
            allow_trie_path,
            important_allow_trie_path,
        ],
        app_allowlist,
        block: LoadInput {
            index_usable: flags & 1 != 0,
            important_usable: flags & 2 != 0,
            custom: block_custom,
            subscription: block_subscription,
        },
        allow: LoadInput {
            index_usable: flags & 4 != 0,
            important_usable: flags & 8 != 0,
            custom: allow_custom,
            subscription: allow_subscription,
        },
    })
}

#[cfg(test)]
pub fn encode(input: &SnapshotInput) -> Vec<u8> {
    let mut out = Vec::with_capacity(64);
    out.push(LAYOUT_VERSION);
    let mut flags = 0u8;
    if input.block.index_usable {
        flags |= 1;
    }
    if input.block.important_usable {
        flags |= 2;
    }
    if input.allow.index_usable {
        flags |= 4;
    }
    if input.allow.important_usable {
        flags |= 8;
    }
    if input.filter_enabled {
        flags |= 16;
    }
    out.push(flags);
    for path in &input.trie_paths {
        put_optional_text(&mut out, path.as_deref());
    }
    out.extend_from_slice(&(input.app_allowlist.len() as u32).to_le_bytes());
    for (package, domains) in &input.app_allowlist {
        put_text(&mut out, package);
        out.extend_from_slice(&(domains.len() as u32).to_le_bytes());
        for domain in domains {
            put_text(&mut out, domain);
        }
    }
    for rows in [
        &input.block.custom,
        &input.block.subscription,
        &input.allow.custom,
        &input.allow.subscription,
    ] {
        out.extend_from_slice(&(rows.len() as u32).to_le_bytes());
        for row in rows {
            put_row(&mut out, row);
        }
    }
    out
}

#[cfg(test)]
fn put_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

#[cfg(test)]
fn put_optional_text(out: &mut Vec<u8>, text: Option<&str>) {
    match text {
        Some(text) => put_text(out, text),
        None => out.extend_from_slice(&NULL_TEXT.to_le_bytes()),
    }
}

#[cfg(test)]
fn put_row(out: &mut Vec<u8>, row: &Row) {
    put_text(out, &row.pattern);
    put_text(out, &row.source);
    let mut flags = 0u8;
    if row.important {
        flags |= 1;
    }
    if row.app_inverted {
        flags |= 2;
    }
    if row.is_wildcard {
        flags |= 4;
    }
    if row.is_regex {
        flags |= 8;
    }
    out.push(flags);
    put_optional_text(out, row.app_scope.as_deref());
    put_optional_text(out, row.denyallow.as_deref());
    put_optional_text(out, row.dns_type.as_deref());
}

#[cfg(test)]
mod tests;
