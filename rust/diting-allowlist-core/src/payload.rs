pub const LAYOUT_VERSION: u8 = 1;

const CONFIGURE_HEADER: usize = 1 + 4;
const UID_HEADER: usize = 4 + 4;
const DOMAIN_HEADER: usize = 4;

const REMEMBER_HEADER: usize = 1 + 4 + 4;
const RECORD_HEADER: usize = 1 + 4;

#[derive(Debug, Clone, PartialEq)]
pub struct RememberRequest {
    pub uid: i32,
    pub question_name: String,
    pub records: Vec<(Vec<u8>, u32)>,
}

pub fn decode_configure(payload: &[u8]) -> Option<Vec<(i32, Vec<String>)>> {
    if payload.len() < CONFIGURE_HEADER || payload[0] != LAYOUT_VERSION {
        return None;
    }
    let uid_count = u32::from_le_bytes(payload[1..5].try_into().ok()?) as usize;
    if uid_count > (payload.len() - CONFIGURE_HEADER) / UID_HEADER {
        return None;
    }

    let mut entries = Vec::with_capacity(uid_count);
    let mut position = CONFIGURE_HEADER;
    for _ in 0..uid_count {
        if payload.len() - position < UID_HEADER {
            return None;
        }
        let uid = i32::from_le_bytes(payload[position..position + 4].try_into().ok()?);
        let domain_count =
            u32::from_le_bytes(payload[position + 4..position + 8].try_into().ok()?) as usize;
        position += UID_HEADER;
        if domain_count > (payload.len() - position) / DOMAIN_HEADER {
            return None;
        }

        let mut domains = Vec::with_capacity(domain_count);
        for _ in 0..domain_count {
            if payload.len() - position < DOMAIN_HEADER {
                return None;
            }
            let length =
                u32::from_le_bytes(payload[position..position + 4].try_into().ok()?) as usize;
            position += DOMAIN_HEADER;
            if payload.len() - position < length {
                return None;
            }
            let domain = std::str::from_utf8(&payload[position..position + length])
                .ok()?
                .to_string();
            position += length;
            domains.push(domain);
        }
        entries.push((uid, domains));
    }
    if position != payload.len() {
        return None;
    }
    Some(entries)
}

pub fn encode_configure(entries: &[(i32, Vec<String>)]) -> Vec<u8> {
    let mut out = Vec::with_capacity(CONFIGURE_HEADER);
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(&(entries.len() as u32).to_le_bytes());
    for (uid, domains) in entries {
        out.extend_from_slice(&uid.to_le_bytes());
        out.extend_from_slice(&(domains.len() as u32).to_le_bytes());
        for domain in domains {
            out.extend_from_slice(&(domain.len() as u32).to_le_bytes());
            out.extend_from_slice(domain.as_bytes());
        }
    }
    out
}

pub fn decode_remember(payload: &[u8]) -> Option<RememberRequest> {
    if payload.len() < REMEMBER_HEADER || payload[0] != LAYOUT_VERSION {
        return None;
    }
    let uid = i32::from_le_bytes(payload[1..5].try_into().ok()?);
    let qname_len = u32::from_le_bytes(payload[5..9].try_into().ok()?) as usize;
    if payload.len() - REMEMBER_HEADER < qname_len + 4 {
        return None;
    }
    let mut position = REMEMBER_HEADER;
    let question_name = std::str::from_utf8(&payload[position..position + qname_len])
        .ok()?
        .to_string();
    position += qname_len;
    let record_count =
        u32::from_le_bytes(payload[position..position + 4].try_into().ok()?) as usize;
    position += 4;
    if record_count > (payload.len() - position) / RECORD_HEADER {
        return None;
    }

    let mut records = Vec::with_capacity(record_count);
    for _ in 0..record_count {
        if payload.len() - position < RECORD_HEADER {
            return None;
        }
        let address_len = payload[position] as usize;
        position += 1;
        if address_len != 4 && address_len != 16 {
            return None;
        }
        if payload.len() - position < address_len + 4 {
            return None;
        }
        let address = payload[position..position + address_len].to_vec();
        position += address_len;
        let ttl = u32::from_le_bytes(payload[position..position + 4].try_into().ok()?);
        position += 4;
        records.push((address, ttl));
    }
    if position != payload.len() {
        return None;
    }
    Some(RememberRequest {
        uid,
        question_name,
        records,
    })
}

pub fn encode_remember(uid: i32, question_name: &str, records: &[(Vec<u8>, u32)]) -> Vec<u8> {
    let mut out = Vec::with_capacity(REMEMBER_HEADER + question_name.len());
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(&uid.to_le_bytes());
    out.extend_from_slice(&(question_name.len() as u32).to_le_bytes());
    out.extend_from_slice(question_name.as_bytes());
    out.extend_from_slice(&(records.len() as u32).to_le_bytes());
    for (address, ttl) in records {
        out.push(address.len() as u8);
        out.extend_from_slice(address);
        out.extend_from_slice(&ttl.to_le_bytes());
    }
    out
}

#[cfg(test)]
mod tests;
