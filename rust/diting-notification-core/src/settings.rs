//! Reader-side rules for the notification preferences Flutter writes.

/// Ordered detail ids. Older installs only had the `speed` switch, so a missing `stats_items`
/// key still falls back to it; an explicitly empty value means "no detail line".
pub fn stats_items(raw: &str, has_raw: bool, legacy_speed: bool) -> Vec<String> {
    if !has_raw {
        return if legacy_speed {
            vec!["speed".to_string()]
        } else {
            Vec::new()
        };
    }
    let mut items: Vec<String> = Vec::new();
    for part in raw.split(',') {
        let id = part.trim();
        if !id.is_empty() && !items.iter().any(|existing| existing == id) {
            items.push(id.to_string());
        }
    }
    items
}

/// Custom text wins, then the mode-specific body Dart composed, then the caller's fallback. A
/// blank body looks like a rendering bug, hence the chain.
pub fn running_text(custom: &str, mode_default: &str, fallback: &str) -> String {
    if !custom.trim().is_empty() {
        return custom.to_string();
    }
    if !mode_default.trim().is_empty() {
        return mode_default.to_string();
    }
    fallback.to_string()
}

#[cfg(test)]
mod tests {
    use super::{running_text, stats_items};

    #[test]
    fn missing_items_use_the_legacy_speed_switch() {
        assert_eq!(stats_items("", false, true), vec!["speed"]);
        assert!(stats_items("", false, false).is_empty());
    }

    #[test]
    fn present_items_are_trimmed_deduplicated_and_ordered() {
        assert_eq!(
            stats_items(" total, ,passed,total, speed ", true, true),
            vec!["total", "passed", "speed"]
        );
        assert!(stats_items("", true, true).is_empty());
    }

    #[test]
    fn running_text_prefers_custom_then_mode_then_fallback() {
        assert_eq!(running_text("  custom  ", "mode", "fallback"), "  custom  ");
        assert_eq!(running_text("  ", "mode", "fallback"), "mode");
        assert_eq!(running_text("", " ", "fallback"), "fallback");
    }
}
