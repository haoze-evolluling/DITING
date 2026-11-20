#[derive(Debug, PartialEq, Eq)]
pub struct Decision<'a> {
    pub blocked: bool,
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
