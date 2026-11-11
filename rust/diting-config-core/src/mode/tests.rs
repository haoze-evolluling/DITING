//! The mode table and its aliases.

use super::*;

#[test]
fn canonical_names_and_aliases() {
    for (input, expected) in [
        ("single", MODE_SINGLE),
        ("SINGLE", MODE_SINGLE),
        (" single ", MODE_SINGLE),
        ("primary_backup", MODE_PRIMARY_BACKUP),
        ("Primary_Backup", MODE_PRIMARY_BACKUP),
        ("parallel_race", MODE_PARALLEL_RACE),
        ("race", MODE_PARALLEL_RACE),
        ("brute_force_parallel", MODE_PARALLEL_RACE),
        ("smart_prediction", MODE_SMART_PREDICTION),
        ("prediction", MODE_SMART_PREDICTION),
        // Go folds U+0130 to a plain `i`, so this really is `single`.
        ("sİngle", MODE_SINGLE),
    ] {
        assert_eq!(canonical_dns_mode(input).unwrap(), expected, "{input}");
    }
}

#[test]
fn unknown_modes_report_the_original_text() {
    assert_eq!(
        canonical_dns_mode("nope").unwrap_err(),
        "unsupported DNS mode \"nope\""
    );
    // Trimmed first, so a padded unknown mode is reported with its padding.
    assert_eq!(
        canonical_dns_mode(" sing le ").unwrap_err(),
        "unsupported DNS mode \" sing le \""
    );
    assert_eq!(
        canonical_dns_mode("").unwrap_err(),
        "unsupported DNS mode \"\""
    );
}
