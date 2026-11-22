#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusKind {
    Ok,
    RateLimited,
    Other,
}

pub fn status_kind(status: i32) -> StatusKind {
    match status {
        200 => StatusKind::Ok,
        403 => StatusKind::RateLimited,
        _ => StatusKind::Other,
    }
}

pub fn should_retry(attempt: u32, error_text: &str) -> bool {
    attempt == 1 && error_text.contains("EOF")
}

#[cfg(test)]
mod tests;
