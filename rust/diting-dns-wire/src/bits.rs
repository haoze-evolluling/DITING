pub fn read_u16(wire: &[u8], offset: usize) -> Option<u16> {
    let bytes = wire.get(offset..offset + 2)?;
    Some(u16::from_be_bytes([bytes[0], bytes[1]]))
}

pub fn read_u32(wire: &[u8], offset: usize) -> Option<u32> {
    let bytes = wire.get(offset..offset + 4)?;
    Some(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
}
