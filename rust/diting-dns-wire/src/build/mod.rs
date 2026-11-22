mod edns;
mod message;
mod name;
mod parse;
mod parse_rdata;
mod rdata;
mod types;

pub use edns::{
    pad_to_block, parse_opt, truncate_udp, EcsOption, EdeOption, EdnsOption, OptBuilder, OptInfo,
};
pub use message::{MessageBuilder, ResourceRecord};
pub use name::{encode_name, NameWriter};
pub use parse::ParsedMessage;
pub use parse_rdata::{decode_svc_params, parse_rdata};
pub use rdata::{RData, SvcParam, SvcbRData};
pub use types::*;

#[cfg(test)]
mod tests;

#[cfg(test)]
mod parse_tests;
