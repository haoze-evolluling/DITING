use crate::addr::{
    apply_mask16, apply_mask4, mask16, mask4, parse_addr, parse_digits, to4, Family,
};

pub const DNS64_PREFIX_LENGTHS: [u8; 6] = [32, 40, 48, 56, 64, 96];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrefixError {
    Parse,
    Length,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Net {
    V4 { number: [u8; 4], mask: [u8; 4] },
    V6 { number: [u8; 16], mask: [u8; 16] },
}

impl Net {
    pub fn contains(&self, bytes: &[u8]) -> bool {
        match (self, to4(bytes)) {
            (Net::V4 { number, mask }, Some(ip)) => number
                .iter()
                .zip(mask)
                .zip(&ip)
                .all(|((n, m), i)| n & m == i & m),
            (Net::V6 { number, mask }, None) if bytes.len() == 16 => number
                .iter()
                .zip(mask)
                .zip(bytes)
                .all(|((n, m), i)| n & m == i & m),
            _ => false,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cidr {
    pub net: Net,
    pub addr16: [u8; 16],
    pub ones: u8,
    pub bits: u32,
}

pub fn parse_cidr(text: &str) -> Result<Cidr, PrefixError> {
    let Some((addr, mask)) = text.split_once('/') else {
        return Err(PrefixError::Parse);
    };
    let Some((family, addr16)) = parse_addr(addr) else {
        return Err(PrefixError::Parse);
    };
    let Some(ones) = parse_digits(mask) else {
        return Err(PrefixError::Parse);
    };
    if ones > family.bits() {
        return Err(PrefixError::Parse);
    }
    let ones = ones as u8;

    match family {
        Family::V4 => {
            let mask = mask4(ones);
            let mut low = [0u8; 4];
            low.copy_from_slice(&addr16[12..]);
            let number = apply_mask4(&low, &mask);
            Ok(Cidr {
                net: Net::V4 { number, mask },
                addr16: crate::addr::map_v4(number),
                ones,
                bits: 32,
            })
        }
        Family::V6 => {
            let mask = mask16(ones);
            let number = apply_mask16(&addr16, &mask);
            match to4(&number) {
                Some(mapped) => Ok(Cidr {
                    net: Net::V4 {
                        number: mapped,
                        mask: [mask[12], mask[13], mask[14], mask[15]],
                    },
                    addr16: crate::addr::map_v4(mapped),
                    ones,
                    bits: 128,
                }),
                None => Ok(Cidr {
                    net: Net::V6 { number, mask },
                    addr16: number,
                    ones,
                    bits: 128,
                }),
            }
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Prefix {
    pub addr: [u8; 16],
    pub ones: u8,
}

impl Prefix {
    pub fn embed(&self, v4: [u8; 4]) -> [u8; 16] {
        let mut v6 = self.addr;
        match self.ones {
            96 => v6[12..16].copy_from_slice(&v4),
            64 => {
                v6[9..13].copy_from_slice(&v4);
                v6[8] = 0;
            }
            56 => {
                v6[7] = v4[0];
                v6[9..12].copy_from_slice(&v4[1..4]);
                v6[8] = 0;
            }
            48 => {
                v6[6..8].copy_from_slice(&v4[0..2]);
                v6[9..11].copy_from_slice(&v4[2..4]);
                v6[8] = 0;
            }
            40 => {
                v6[5..8].copy_from_slice(&v4[0..3]);
                v6[9] = v4[3];
                v6[8] = 0;
            }
            32 => {
                v6[4..8].copy_from_slice(&v4);
                v6[8] = 0;
            }
            _ => {}
        }
        v6
    }
}

pub fn well_known_prefix() -> Prefix {
    parse_dns64_prefix("64:ff9b::/96")
        .expect("the well-known prefix parses")
        .0
}

pub fn parse_dns64_prefix(text: &str) -> Result<(Prefix, Net), PrefixError> {
    let cidr = parse_cidr(text)?;
    if cidr.bits != 128 || !DNS64_PREFIX_LENGTHS.contains(&cidr.ones) {
        return Err(PrefixError::Length);
    }
    Ok((
        Prefix {
            addr: cidr.addr16,
            ones: cidr.ones,
        },
        cidr.net,
    ))
}

pub fn is_unspecified(bytes: &[u8]) -> bool {
    match to4(bytes) {
        Some(v4) => v4 == [0, 0, 0, 0],
        None => bytes.len() == 16 && bytes.iter().all(|byte| *byte == 0),
    }
}

#[cfg(test)]
mod tests;
