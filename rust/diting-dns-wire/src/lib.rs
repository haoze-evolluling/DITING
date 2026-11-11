//! The DNS wire layer shared by the DNS cache and DNS message kernels.
//!
//! Everything here works on the raw bytes an upstream (or a client) sent. Three details are
//! deliberately copied from the Go implementations instead of being "improved":
//!
//! * the cache key is built from the question exactly like `appendQuestionKey` did: labels are
//!   lowercased byte-wise, joined with `.`, compression pointers are followed (up to 64 jumps) and
//!   the key ends in `:qtype:qclass`;
//! * owner/target names are decoded with the same presentation escaping as miekg/dns
//!   `UnpackDomainName` (`.` is re-escaped, bytes outside `' '..='~'` become `\DDD`, the root name
//!   is `"."`), because the chain targets are compared against rule patterns downstream;
//! * the message reader mirrors `dns.Msg.Unpack`'s leniencies: a message may stop on a record
//!   boundary, and a question may stop right after its name.
//!
//! Split into modules so no file carries more than one concern: [`bits`] (integer readers),
//! [`name`] (name decoding), [`key`] (cache keys), [`message`] (header/questions),
//! [`records`] (answer records with owner names) and [`response`] (records, TTLs, chain targets,
//! patches).

mod bits;
mod key;
mod message;
mod name;
mod records;
mod response;

pub use bits::{read_u16, read_u32};
pub use key::{question_key, write_question_key, KeyParts, QuestionKey, MAX_KEY_LEN};
pub use message::{parse_header, parse_question, MessageHeader, Question};
pub use name::{pack_name, unpack_name, MAX_NAME_WIRE_OCTETS};
pub use records::{parse_answer_records, Record};
pub use response::{
    format_ipv4, format_ipv6, parse_response, patch_response, patch_response_into, ChainKind,
    ChainTarget, ResponseMeta,
};

#[cfg(test)]
mod tests;
