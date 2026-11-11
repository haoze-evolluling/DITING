//! XOR masks plus Base64, byte-compatible with the legacy `KeyObfuscator.kt`: `agent_ai_providers_json`
//! holds ciphertext written by 1.4.3, so an upgrade install must decrypt it. Obfuscation, not
//! encryption -- the three masks are as public as the format.

use base64::engine::general_purpose::STANDARD;
use base64::Engine;

const KA: [u8; 8] = [0x4D, 0x1A, 0xC8, 0x37, 0x62, 0x9E, 0xFB, 0x54];
const KB: [u8; 8] = [0x29, 0x6C, 0xD3, 0x8E, 0x71, 0x05, 0xBA, 0x4F];
const KC: [u8; 8] = [0xBE, 0x34, 0x65, 0x8A, 0x71, 0x22, 0xD9, 0x46];

fn mix(index: usize, byte: u8) -> u8 {
    byte ^ KA[index % KA.len()] ^ KB[index % KB.len()] ^ KC[index % KC.len()]
}

/// Seals a plaintext key. Blank input stays blank, so "no key configured" is an empty string
/// rather than a ciphertext of nothing.
pub fn seal(plain: &str) -> String {
    if plain.trim().is_empty() {
        return String::new();
    }
    let mixed: Vec<u8> = plain
        .as_bytes()
        .iter()
        .enumerate()
        .map(|(index, byte)| mix(index, *byte))
        .collect();
    STANDARD.encode(mixed)
}

/// Restores a sealed key. Undecodable input (bad Base64 or non-UTF-8 plaintext) yields an empty
/// string instead of an error: one bad row must not blank the whole provider list.
pub fn open(sealed: &str) -> String {
    if sealed.trim().is_empty() {
        return String::new();
    }
    // `dart:convert`'s decoder accepts the URL-safe alphabet but insists on correct padding, so
    // translate the two letters and keep the strict decoder.
    let normalized: String = sealed
        .chars()
        .map(|character| match character {
            '-' => '+',
            '_' => '/',
            other => other,
        })
        .collect();
    let Ok(mixed) = STANDARD.decode(normalized.as_bytes()) else {
        return String::new();
    };
    let plain: Vec<u8> = mixed
        .iter()
        .enumerate()
        .map(|(index, byte)| mix(index, *byte))
        .collect();
    String::from_utf8(plain).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        assert_eq!(open(&seal("sk-abc")), "sk-abc");
        assert_eq!(seal(""), "");
        assert_eq!(open(""), "");
        assert_eq!(seal("   "), "");
        assert_eq!(open("   "), "");
    }

    #[test]
    fn ciphertext_matches_the_legacy_masks() {
        // Hand-computed with the Kotlin algorithm: changing it strands keys saved by upgraders.
        // The mixed bytes for "sk-abc" are a9 29 53 52 00 da; Base64 of those six bytes is
        // asserted separately so a mask change fails here with the raw bytes, not a string.
        let mixed = STANDARD
            .decode(seal("sk-abc"))
            .expect("sealed key is Base64");
        assert_eq!(mixed, vec![0xA9, 0x29, 0x53, 0x52, 0x00, 0xDA]);
    }

    #[test]
    fn non_ascii_plaintext_round_trips_through_utf8() {
        let plain = "sk-密钥-🔑";
        assert_eq!(open(&seal(plain)), plain);
    }

    #[test]
    fn bad_ciphertext_is_empty_rather_than_an_error() {
        assert_eq!(open("!!!not-base64!!!"), "");
        // Valid Base64 from another encoder decodes to invalid UTF-8.
        assert_eq!(open("YWJj"), "");
        // Dart's decoder rejects missing padding, and so does this one.
        assert_eq!(open("YWJjZA"), "");
        assert_eq!(open("YWJjZA==="), "");
    }
}
