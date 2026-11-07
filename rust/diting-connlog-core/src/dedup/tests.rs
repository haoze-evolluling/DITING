use super::*;

#[test]
fn the_second_sighting_is_a_duplicate() {
    let dedup = ConnLogDedup::new();
    assert!(!dedup.mark("", "app", "1.2.3.4", 443, 6, ""));
    assert!(dedup.mark("", "app", "1.2.3.4", 443, 6, ""));
    assert_eq!(dedup.size(), 1);
    assert_eq!(dedup.cleared(), 0);
}

#[test]
fn the_blocked_prefix_and_the_reason_are_part_of_the_key() {
    let dedup = ConnLogDedup::new();
    assert!(!dedup.mark("", "app", "1.2.3.4", 443, 6, ""));
    assert!(!dedup.mark("blk|", "app", "1.2.3.4", 443, 6, "uid_blocked"));
    assert!(dedup.mark("blk|", "app", "1.2.3.4", 443, 6, "uid_blocked"));
    assert_eq!(dedup.size(), 2);
}

#[test]
fn reset_empties_the_set_but_keeps_the_overflow_counter() {
    let dedup = ConnLogDedup::new();
    for index in 0..=MAX_ENTRIES {
        dedup.mark("", "app", "dest", index as i32, 6, "");
    }
    assert_eq!(dedup.cleared(), 1);
    assert_eq!(dedup.size(), 1);

    dedup.reset();
    assert_eq!(dedup.size(), 0);
    assert_eq!(dedup.cleared(), 1);
}

#[test]
fn the_set_never_grows_past_the_bound() {
    let dedup = ConnLogDedup::new();
    for index in 0..MAX_ENTRIES {
        assert!(!dedup.mark("", "app", "dest", index as i32, 6, ""));
    }
    assert_eq!(dedup.size(), MAX_ENTRIES as u32);
    assert_eq!(dedup.cleared(), 0);

    // A duplicate at the bound must not trigger the overflow reset.
    assert!(dedup.mark("", "app", "dest", 0, 6, ""));
    assert_eq!(dedup.size(), MAX_ENTRIES as u32);
    assert_eq!(dedup.cleared(), 0);

    // The next *new* key clears the whole set first, then inserts itself.
    assert!(!dedup.mark("", "app", "dest", MAX_ENTRIES as i32, 6, ""));
    assert_eq!(dedup.size(), 1);
    assert_eq!(dedup.cleared(), 1);
}
