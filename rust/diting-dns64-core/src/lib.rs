//! DNS64 synthesizer kernel for the desktop service (`desktop/service/internal/core/dns64.go`).
//!
//! This crate owns RFC 6052 embedding and the RFC 6147 exclusion set: parsing the configured
//! prefixes (with `net.ParseCIDR`'s exact accept / reject outcomes), the `IP.To4` folding that
//! decides which answers count as excluded, and the AAAA check that gates synthesis.
//!
//! The Go side keeps what needs the resolver or `dns.Msg`: querying A records, the minimum-TTL walk
//! over A / CNAME / DNAME answers, appending CNAME / DNAME aliases to the response, and building
//! the `dns.AAAA` records (name, class, TTL). Those are orchestrations around the arithmetic, not
//! the arithmetic itself.
//!
//! Layout:
//! * [`addr`] — `netip.ParseAddr` text rules, `To4` folding, CIDR masks.
//! * [`prefix`] — `net.ParseCIDR`, the RFC 6052 prefix set, `IPNet.Contains`.
//! * [`engine`] — prefixes, exclusions, embed / synthesize / excluded / has-valid.
//! * [`payload`] — the binary layouts shared with `dns64_native*.go`.
//! * [`ffi`] — the C ABI [`ffi::ABI_VERSION`] the Go loader validates.
//!
//! The library is required: a missing library fails `NewDNS64Synthesizer`. The old code only
//! *warned* about a bad prefix, so a broken configuration still starts the service — what changes
//! is that it can no longer start with a silently disabled synthesizer.

pub mod addr;
pub mod engine;
pub mod ffi;
pub mod payload;
pub mod prefix;

pub use addr::{map_v4, mask16, parse_addr, parse_digits, to4, Family};
pub use engine::{Engine, PrefixRejection};
pub use ffi::ABI_VERSION;
pub use payload::LAYOUT_VERSION;
pub use prefix::{
    is_unspecified, parse_cidr, parse_dns64_prefix, well_known_prefix, Cidr, Net, Prefix,
    PrefixError, DNS64_PREFIX_LENGTHS,
};
