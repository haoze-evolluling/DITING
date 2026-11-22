mod bits;
pub mod build;
mod key;
mod message;
mod name;
mod records;
mod response;

pub use bits::{read_u16, read_u32};
pub use build::*;
pub use key::{question_key, write_question_key, KeyParts, QuestionKey, MAX_KEY_LEN};
pub use message::{parse_header, parse_question, MessageHeader, Question};
pub use name::{pack_name, skip_name, unpack_name, MAX_NAME_WIRE_OCTETS};
pub use records::{parse_answer_records, Record};
pub use response::{
    format_ipv4, format_ipv6, parse_response, patch_response, patch_response_into, ChainKind,
    ChainTarget, ResponseMeta,
};

#[cfg(test)]
mod tests;
