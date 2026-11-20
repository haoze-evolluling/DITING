const SNI_EXTENSION: u16 = 0x0000;

pub fn parse_client_hello_sni(record: &[u8]) -> &[u8] {
    if record.len() < 5 || record[0] != 0x16 {
        return &[];
    }
    let mut record_len = usize::from(u16::from_be_bytes([record[3], record[4]]));
    if record_len > record.len() - 5 {
        record_len = record.len() - 5;
    }
    let body = &record[5..5 + record_len];

    if body.len() < 4 || body[0] != 0x01 {
        return &[];
    }

    let ch = &body[4..];

    if ch.len() < 2 + 32 + 1 {
        return &[];
    }
    let mut p = 34;
    let session_len = usize::from(ch[p]);
    p += 1 + session_len;
    if p + 2 > ch.len() {
        return &[];
    }
    let cipher_len = usize::from(u16::from_be_bytes([ch[p], ch[p + 1]]));
    p += 2 + cipher_len;
    if p + 1 > ch.len() {
        return &[];
    }
    let compression_len = usize::from(ch[p]);
    p += 1 + compression_len;
    if p + 2 > ch.len() {
        return &[];
    }
    let mut extension_len = usize::from(u16::from_be_bytes([ch[p], ch[p + 1]]));
    p += 2;
    if p + extension_len > ch.len() {
        extension_len = ch.len() - p;
    }
    let mut ext = &ch[p..p + extension_len];

    while ext.len() >= 4 {
        let extension_type = u16::from_be_bytes([ext[0], ext[1]]);
        let extension_data_len = usize::from(u16::from_be_bytes([ext[2], ext[3]]));
        if 4 + extension_data_len > ext.len() {
            return &[];
        }
        let extension_data = &ext[4..4 + extension_data_len];

        if extension_type == SNI_EXTENSION {
            if extension_data.len() < 5 {
                return &[];
            }
            let list_len = usize::from(u16::from_be_bytes([extension_data[0], extension_data[1]]));
            if 2 + list_len > extension_data.len() {
                return &[];
            }
            let list = &extension_data[2..2 + list_len];
            if list.len() < 3 || list[0] != 0x00 {
                return &[];
            }
            let name_len = usize::from(u16::from_be_bytes([list[1], list[2]]));
            if 3 + name_len > list.len() {
                return &[];
            }
            return &list[3..3 + name_len];
        }
        ext = &ext[4 + extension_data_len..];
    }
    &[]
}

#[cfg(test)]
mod tests;
