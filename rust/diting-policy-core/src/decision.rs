//! The verdict of one policy query: the Go engine's `(blocked, reason)` pair, with the reason
//! borrowed from the snapshot so a lookup never allocates.

/// The verdict for one query.
#[derive(Debug, PartialEq, Eq)]
pub struct Decision<'a> {
    pub blocked: bool,
    /// Borrowed from the snapshot, so answering a query allocates nothing: the FFI hands the Go
    /// caller a pointer into this string and Go copies it out immediately.
    pub reason: &'a str,
}

impl<'a> Decision<'a> {
    pub(crate) fn pass() -> Decision<'a> {
        Decision {
            blocked: false,
            reason: "",
        }
    }

    pub(crate) fn block(reason: &'a str) -> Decision<'a> {
        Decision {
            blocked: true,
            reason,
        }
    }

    pub(crate) fn allow() -> Decision<'a> {
        Decision {
            blocked: false,
            reason: "__ALLOW__",
        }
    }
}
