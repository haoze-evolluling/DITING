//! The filter state machine: allow list, bypass rules, blacklist expiry, failure streaks and the
//! persistent file. Every test injects `now_ms`, so nothing here depends on the wall clock.

use std::path::{Path, PathBuf};

use super::*;

/// A path under the system temp dir that no other test shares.
fn temp_path(name: &str) -> PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!("diting-mitm-{}-{}.txt", std::process::id(), name));
    let _ = fs::remove_file(&path);
    path
}

fn as_text(path: &Path) -> &str {
    path.to_str().expect("the temp path is UTF-8")
}

#[test]
fn allowed_uids_parse_like_the_go_csv() {
    let filter = Filter::new();
    assert!(!filter.has_allowed_uids());

    assert_eq!(filter.set_allowed_uids_csv("1001, 1002 ,1001"), 2);
    assert!(filter.has_allowed_uids());
    assert!(filter.is_uid_allowed(1001));
    assert!(filter.is_uid_allowed(1002));
    assert!(!filter.is_uid_allowed(1003));

    // Only the digit characters count, exactly like the Go parser: `1a2` is UID 12, `-3` is 3 and
    // UID 0 is dropped.
    assert_eq!(filter.set_allowed_uids_csv("1a2,0,-3,abc"), 2);
    assert!(filter.is_uid_allowed(12));
    assert!(filter.is_uid_allowed(3));
    assert!(!filter.is_uid_allowed(32));

    assert_eq!(filter.set_allowed_uids_csv(""), 0);
    assert!(!filter.has_allowed_uids());
}

#[test]
fn bypass_rules_drop_comments_and_normalize() {
    let filter = Filter::new();
    let count =
        filter.set_bypass_rules("  # comment\n// comment\n\n Example.COM \n*.blog.example\r\n\t\n");
    assert_eq!(count, 2);

    assert!(!filter.allows_interception("example.com", 0));
    assert!(!filter.allows_interception("www.example.com", 0));
    assert!(!filter.allows_interception("blog.example", 0));
    assert!(!filter.allows_interception("cdn.blog.example", 0));
    assert!(filter.allows_interception("other.org", 0));

    // Replacing the rules drops the previous ones.
    assert_eq!(filter.set_bypass_rules("other.org"), 1);
    assert!(filter.allows_interception("example.com", 0));
    assert!(!filter.allows_interception("other.org", 0));
}

#[test]
fn sensitive_hosts_and_addresses_are_never_intercepted() {
    let filter = Filter::new();
    assert!(!filter.allows_interception("bank.com", 0));
    // The port is stripped after lowercasing, and `bank` is a whole label.
    assert!(!filter.allows_interception("API.BANK.com:443", 0));
    assert!(!filter.allows_interception("1.2.3.4", 0));
    assert!(!filter.allows_interception(" ::1 ", 0));
    assert!(!filter.allows_interception(".", 0));

    assert!(filter.allows_interception("example.com", 0));
    assert!(filter.allows_interception(" Example.COM ", 0));
}

#[test]
fn blacklist_entries_expire() {
    let filter = Filter::new();
    let now = 1_700_000_000_000;

    let added = filter
        .blacklist("Example.COM ", "pinning", now)
        .expect("added");
    assert_eq!(added.host, "example.com");
    assert_eq!(added.reason, "pinning");
    assert_eq!(added.ttl_ms, DEFAULT_BLACKLIST_TTL_MS);
    assert!(added.write_error.is_none());

    assert_eq!(filter.blacklist_count(now), 1);
    assert_eq!(
        filter.blacklist_reason(" example.com ", now).as_deref(),
        Some("pinning")
    );
    assert!(!filter.allows_interception("example.com", now));

    // A live entry is not rewritten.
    assert!(filter
        .blacklist("example.com", "pinning", now + 1)
        .is_none());
    assert_eq!(filter.blacklist_count(now + 1), 1);

    // Live one millisecond before the deadline, gone at it.
    let deadline = now + DEFAULT_BLACKLIST_TTL_MS;
    assert!(!filter.allows_interception("example.com", deadline - 1));
    assert!(filter.allows_interception("example.com", deadline));
    assert_eq!(filter.blacklist_count(deadline), 0);

    // An empty host is refused outright, like the Go early return.
    assert!(filter.blacklist("   ", "pinning", now).is_none());
}

#[test]
fn failure_streaks_blacklist_after_three_generic_errors() {
    let filter = Filter::new();
    let now = 1_000_000;

    let first = filter.record_failure("Example.COM", "connection reset by peer", now);
    assert!(first.recorded);
    assert_eq!((first.count, first.threshold), (1, 3));
    assert_eq!(first.host, "example.com");
    assert!(first.blacklist.is_none());
    assert!(filter.allows_interception("example.com", now));

    assert_eq!(
        filter.record_failure("example.com", "boom", now + 1).count,
        2
    );

    let third = filter.record_failure("example.com", "boom", now + 2);
    assert_eq!(third.count, 3);
    let added = third.blacklist.expect("the third failure blacklists");
    assert_eq!(added.reason, "handshake_failure (3 failures)");
    assert_eq!(added.host, "example.com");
    assert!(!filter.allows_interception("example.com", now + 2));

    // The blacklist entry comes with the usual lifetime.
    assert_eq!(
        filter.blacklist_count(now + 2 + DEFAULT_BLACKLIST_TTL_MS - 1),
        1
    );
}

#[test]
fn a_rejected_certificate_blacklists_after_two_failures() {
    let filter = Filter::new();
    let now = 5_000_000;

    let first = filter.record_failure(
        "pinned.example",
        "remote error: tls: unknown certificate authority",
        now,
    );
    assert_eq!((first.count, first.threshold), (1, 2));
    assert!(first.blacklist.is_none());

    let second = filter.record_failure(
        "pinned.example",
        "remote error: tls: BAD CERTIFICATE",
        now + 1,
    );
    assert_eq!(second.count, 2);
    let added = second.blacklist.expect("the second failure blacklists");
    assert_eq!(added.reason, "cert_rejected (2 failures)");
}

#[test]
fn failure_streaks_restart_after_the_window() {
    let filter = Filter::new();
    let now = 9_000_000;

    filter.record_failure("example.com", "boom", now);
    filter.record_failure("example.com", "boom", now + 1);

    // Exactly one window after the last failure still counts (`now.Sub(lastSeen) > window` is what
    // started a new streak in Go).
    let counted = filter.record_failure("example.com", "boom", now + 1 + FAILURE_WINDOW_MS);
    assert_eq!(counted.count, 3);

    // Past the window *from the last failure* the streak starts over. The third call above moved
    // `lastSeen` to `now + 1 + FAILURE_WINDOW_MS`.
    let restarted =
        filter.record_failure("example.com", "boom", now + 1 + 2 * FAILURE_WINDOW_MS + 1);
    assert_eq!(restarted.count, 1);
}

#[test]
fn an_empty_host_records_nothing() {
    let filter = Filter::new();
    let report = filter.record_failure("   ", "boom", 0);
    assert!(!report.recorded);
    assert!(!report.blacklisted);
    assert!(report.blacklist.is_none());
    assert_eq!(filter.blacklist_count(0), 0);
}

#[test]
fn remove_and_clear() {
    let filter = Filter::new();
    let now = 0;

    filter.blacklist("example.com", "pinning", now);
    filter.blacklist("other.com", "pinning", now);
    filter.record_failure("third.com", "boom", now);

    filter.remove_from_blacklist(" Example.com");
    assert_eq!(filter.blacklist_count(now), 1);
    assert!(filter.allows_interception("example.com", now));
    assert!(!filter.allows_interception("other.com", now));

    filter.clear_blacklist();
    assert_eq!(filter.blacklist_count(now), 0);
    assert!(filter.allows_interception("other.com", now));

    // The streak is gone too: the next failure starts at one.
    assert_eq!(filter.record_failure("third.com", "boom", now).count, 1);
}

#[test]
fn persistent_blacklist_round_trips() {
    let path = temp_path("persist");
    let now = 1_700_000_000_000;

    let filter = Filter::new();
    assert_eq!(filter.load_persistent(as_text(&path), now), 0);
    let added = filter
        .blacklist("Pinned.Example", "EV certificate", now)
        .expect("added");
    assert!(
        added.write_error.is_none(),
        "appending failed: {:?}",
        added.write_error
    );

    // `host|unix_seconds|reason`, exactly the line the Go version wrote: the reason keeps the case
    // it was given, and only loading a line lowercases it (the loader lowercases whole lines).
    let written = fs::read_to_string(&path).expect("read the blacklist file");
    assert_eq!(
        written,
        format!(
            "pinned.example|{}|EV certificate\n",
            (now + DEFAULT_BLACKLIST_TTL_MS).div_euclid(1000)
        )
    );

    // A fresh filter reloads it and keeps refusing interception.
    let reloaded = Filter::new();
    assert_eq!(reloaded.load_persistent(as_text(&path), now + 1_000), 1);
    assert_eq!(reloaded.blacklist_count(now + 1_000), 1);
    assert!(!reloaded.allows_interception("pinned.example", now + 1_000));
    assert_eq!(
        reloaded
            .blacklist_reason("pinned.example", now + 1_000)
            .as_deref(),
        Some("ev certificate")
    );

    // Loading after the deadline drops the expired lines. Exactly at the deadline the line is
    // still kept (Go compared with `now.After(expiry)`) but counts as dead.
    let expired = Filter::new();
    let later = now + DEFAULT_BLACKLIST_TTL_MS;
    assert_eq!(expired.load_persistent(as_text(&path), later), 1);
    assert_eq!(expired.blacklist_count(later), 0);
    assert_eq!(expired.load_persistent(as_text(&path), later + 1), 0);
    assert_eq!(expired.blacklist_count(later + 1), 0);

    // `clear_blacklist` truncates the file, so nothing comes back on the next start.
    reloaded.clear_blacklist();
    assert_eq!(
        fs::read_to_string(&path).expect("read the blacklist file"),
        ""
    );
    let _ = fs::remove_file(&path);
}

#[test]
fn persistent_file_tolerates_comments_and_missing_fields() {
    let path = temp_path("tolerant");
    let now: i64 = 2_000_000_000_000;
    let valid: i64 = (now + 60_000).div_euclid(1000);
    let content = format!(
        "# comment\n\n  Mixed.Case.COM | {valid} | EV Certificate \n\
         no-expiry.example|not-a-number|pinning\n\
         missing-fields.example\n\
         empty-expiry.example|\n\
         |{valid}|no-host\n"
    );
    fs::write(&path, content).expect("write the fixture file");

    let filter = Filter::new();
    assert_eq!(filter.load_persistent(as_text(&path), now), 4);
    assert_eq!(filter.blacklist_count(now), 4);
    assert_eq!(
        filter.blacklist_reason("mixed.case.com", now).as_deref(),
        Some("ev certificate")
    );
    assert_eq!(
        filter.blacklist_reason("no-expiry.example", now).as_deref(),
        Some("pinning")
    );
    assert_eq!(
        filter
            .blacklist_reason("missing-fields.example", now)
            .as_deref(),
        Some("pinning")
    );
    assert_eq!(
        filter
            .blacklist_reason("empty-expiry.example", now)
            .as_deref(),
        Some("pinning")
    );
    let _ = fs::remove_file(&path);
}
