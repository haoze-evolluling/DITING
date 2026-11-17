//! Synthesis half of the wire layer: message/record builders and the EDNS option layer.
//!
//! The readers in the crate root stay the single source of truth for parsing. This module only
//! adds the inverse direction the desktop service needs (block/rewrite/hosts/zone/safesearch/DDR/
//! ANY/DNS64/error responses) plus the EDNS helpers (ECS, EDE, padding, cookie, NSID).

mod edns;
mod message;
mod name;
mod rdata;
mod types;

pub use edns::{
    pad_to_block, parse_opt, truncate_udp, EcsOption, EdeOption, EdnsOption, OptBuilder, OptInfo,
};
pub use message::{MessageBuilder, ResourceRecord};
pub use name::{encode_name, NameWriter};
pub use rdata::{RData, SvcParam, SvcbRData};
pub use types::*;

#[cfg(test)]
mod tests;
