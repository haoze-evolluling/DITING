use super::*;

fn temp_root(tag: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "diting-sqlite-migrate-{tag}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|value| value.as_nanos())
            .unwrap_or(0)
    ))
}

fn write_config(root: &Path) {
    let mut config = Config::default();
    config.filter.data_dir = root.join("filters").to_string_lossy().into_owned();
    config.query_log.data_dir = root.join("querylog").to_string_lossy().into_owned();
    config.cache.persist_path = root.join("cache.json").to_string_lossy().into_owned();
    config.takeover.state_file_path = root.join("dns_state.json").to_string_lossy().into_owned();
    fs::write(
        root.join("config.json"),
        serde_json::to_vec(&config).unwrap(),
    )
    .unwrap();
}

#[test]
fn imports_and_deletes_legacy_files() {
    let root = temp_root("basic");
    fs::create_dir_all(root.join("filters")).unwrap();
    fs::create_dir_all(root.join("querylog")).unwrap();
    write_config(&root);
    fs::write(root.join("filters").join("list.txt"), b"||ads.example^\n").unwrap();
    fs::write(
        root.join("querylog").join("querylog-20260101.jsonl"),
        b"{\"ts\":1000,\"domain\":\"a.com\",\"status\":\"allowed\"}\n",
    )
    .unwrap();
    let db = SqliteDb::open(root.join("diting.db")).unwrap();
    let report = migrate(&db, &root.join("config.json"), &root, true).unwrap();
    assert!(report.imported_config);
    assert_eq!(report.imported_lists, 1);
    assert_eq!(report.imported_logs, 1);
    assert!(!root.join("config.json").exists());
    assert!(!root.join("filters").join("list.txt").exists());
    assert!(!root
        .join("querylog")
        .join("querylog-20260101.jsonl")
        .exists());
    let second = migrate(&db, &root.join("config.json"), &root, true).unwrap();
    assert_eq!(second.imported_logs, 0);
    let _ = fs::remove_dir_all(root);
}

#[test]
fn resumes_querylog_import_from_progress_marker() {
    let root = temp_root("resume");
    fs::create_dir_all(root.join("filters")).unwrap();
    write_config(&root);
    let db = SqliteDb::open(root.join("diting.db")).unwrap();
    migrate(&db, &root.join("config.json"), &root, false).unwrap();

    fs::create_dir_all(root.join("querylog")).unwrap();
    let log_path = root.join("querylog").join("querylog-20260101.jsonl");
    fs::write(
        &log_path,
        b"{\"ts\":1000,\"domain\":\"a.com\",\"status\":\"allowed\"}\n\
          {\"ts\":2000,\"domain\":\"b.com\",\"status\":\"allowed\"}\n",
    )
    .unwrap();
    mark(&db, &log_path, "querylog", 1, false).unwrap();

    let report = migrate(&db, &root.join("config.json"), &root, true).unwrap();
    assert_eq!(report.imported_logs, 1);
    let domains: Vec<String> = db
        .read(|connection| {
            let mut statement = connection.prepare("SELECT domain FROM query_log ORDER BY ts")?;
            let rows = statement.query_map([], |row| row.get::<_, String>(0))?;
            rows.collect::<rusqlite::Result<Vec<_>>>()
        })
        .unwrap();
    assert_eq!(domains, vec!["b.com".to_string()]);
    assert!(!log_path.exists());
    let _ = fs::remove_dir_all(root);
}
