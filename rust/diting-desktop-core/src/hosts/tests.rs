use super::*;

fn temp_file(name: &str, content: &str) -> PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "diting-hosts-{}-{}-{name}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::write(&path, content).unwrap();
    path
}

#[test]
fn default_ttl_and_disabled_lookups() {
    let resolver = HostsResolver::new(&HostsConfig {
        enabled: false,
        ..HostsConfig::default()
    });
    assert_eq!(resolver.ttl(), DEFAULT_HOSTS_TTL);
    assert!(!resolver.enabled());
    assert!(resolver.lookup("localhost", 1).is_empty());
    assert!(resolver.ptr("1.0.0.127.in-addr.arpa.").is_empty());
    assert!(!resolver.has_domain("localhost"));
}

#[test]
fn loads_custom_file_and_answers_a_aaaa_and_ptr() {
    let path = temp_file(
        "custom.hosts",
        "127.0.0.1 app.local\n2001:db8::1 app.local\n192.168.1.9 nas.local storage.local\n",
    );
    let resolver = HostsResolver::new(&HostsConfig {
        enabled: true,
        use_system_host: false,
        custom_files: vec![path.display().to_string()],
        ttl: 30,
    });

    let records = resolver.lookup("app.local", 1);
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].owner, "app.local.");
    assert_eq!(records[0].ip, "127.0.0.1".parse::<IpAddr>().unwrap());
    assert_eq!(records[0].ttl, 30);

    let records = resolver.lookup("app.local", 28);
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].ip, "2001:db8::1".parse::<IpAddr>().unwrap());

    assert!(resolver.has_domain("storage.local"));
    let names = resolver.ptr("9.1.168.192.in-addr.arpa");
    assert_eq!(names, vec!["nas.local.", "storage.local."]);

    let stats = resolver.stats();
    assert!(stats.enabled);
    assert_eq!(stats.entries, 3);
    assert_eq!(stats.ttl, 30);
    assert_eq!(stats.loaded_files, vec![path.display().to_string()]);
    let _ = std::fs::remove_file(path);
}

#[test]
fn configure_replaces_the_table_and_unreadable_files_set_error() {
    let first = temp_file("first.hosts", "10.0.0.1 old.home\n");
    let resolver = HostsResolver::new(&HostsConfig {
        enabled: true,
        use_system_host: false,
        custom_files: vec![first.display().to_string()],
        ttl: 0,
    });
    assert!(resolver.has_domain("old.home"));

    let missing = first.with_file_name("does-not-exist.hosts");
    resolver.configure(&HostsConfig {
        enabled: true,
        use_system_host: false,
        custom_files: vec![missing.display().to_string()],
        ttl: 90,
    });
    assert!(!resolver.has_domain("old.home"));
    assert_eq!(resolver.ttl(), 90);
    let stats = resolver.stats();
    assert!(stats.error.is_some());

    let _ = std::fs::remove_file(first);
}

#[test]
fn reload_rereads_the_loaded_files() {
    let path = temp_file("reload.hosts", "10.0.0.1 nas.home\n");
    let resolver = HostsResolver::new(&HostsConfig {
        enabled: true,
        use_system_host: false,
        custom_files: vec![path.display().to_string()],
        ttl: 45,
    });
    assert_eq!(resolver.lookup("nas.home", 1).len(), 1);

    std::fs::write(&path, "10.0.0.9 nas.home\n").unwrap();
    resolver.reload().unwrap();
    let records = resolver.lookup("nas.home", 1);
    assert_eq!(records[0].ip, "10.0.0.9".parse::<IpAddr>().unwrap());
    assert_eq!(records[0].ttl, 45);
    let _ = std::fs::remove_file(path);
}

#[test]
fn reload_without_sources_is_ok() {
    let resolver = HostsResolver::new(&HostsConfig {
        enabled: true,
        use_system_host: false,
        custom_files: Vec::new(),
        ttl: 0,
    });
    assert!(resolver.reload().is_ok());
    assert_eq!(resolver.stats().entries, 0);
}
