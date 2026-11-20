use crate::dtri::{self, Validation};
use crate::index_layout;
use crate::payload::{Reader, Writer};
use crate::snapshot::plan::{self, Half, Outcome};

fn read_half(reader: &mut Reader<'_>) -> Option<Half> {
    let normal = Outcome::from_tag(reader.u8()?)?;
    let important = Outcome::from_tag(reader.u8()?)?;
    Some(Half::new(normal, important))
}

pub fn layout_paths(dataset: u8) -> Option<Vec<u8>> {
    let layout = index_layout::layout(dataset)?;
    let mut writer = Writer::new();
    for path in [
        layout.root,
        layout.domain,
        layout.hosts,
        layout.block,
        layout.block_important,
        layout.allow,
        layout.allow_important,
    ] {
        writer.string(path);
    }
    Some(writer.into_vec())
}

pub fn dtri_validate(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let header = reader.blob()?;
    let file_length = reader.i64()?;
    if !reader.finish() {
        return None;
    }
    let validation = dtri::validate_header(header, file_length.max(0) as u64);
    let (status, expected) = match validation {
        Validation::Ok => (0u8, file_length.max(0) as u64),
        Validation::Header => (1, 0),
        Validation::Version => (2, 0),
        Validation::Counts => (3, 0),
        Validation::Sections { expected } => (4, expected),
    };
    let mut writer = Writer::new();
    writer.u8(status);
    writer.i64(expected as i64);
    Some(writer.into_vec())
}

pub fn snapshot_plan(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let block = read_half(&mut reader)?;
    let allow = read_half(&mut reader)?;
    if !reader.finish() {
        return None;
    }
    let plan = plan::plan(block, allow);
    let flag = |value: bool| if value { 1u8 } else { 0u8 };
    let mut writer = Writer::new();
    writer.u8(flag(plan.compiled));
    writer.u8(flag(plan.settled));
    for half in [plan.block, plan.allow] {
        writer.u8(flag(half.normal.usable()));
        writer.u8(flag(half.important.usable()));
    }
    writer.u8(flag(plan.block.special_rows_only()));
    writer.u8(flag(plan.allow.special_rows_only()));
    Some(writer.into_vec())
}

pub fn trie_paths(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let directory_ok = reader.u8()? != 0;
    let count = reader.u32()? as usize;
    if count != 4 {
        return None;
    }
    let mut entries = Vec::with_capacity(4);
    for _ in 0..count {
        entries.push((reader.string()?, reader.u8()? != 0, reader.i64()?));
    }
    if !reader.finish() {
        return None;
    }
    let mut writer = Writer::new();
    for path in plan::trie_paths(directory_ok, &entries) {
        match path {
            Some(path) => {
                writer.u8(1);
                writer.string(&path);
            }
            None => writer.u8(0),
        }
    }
    Some(writer.into_vec())
}

fn read_packages(reader: &mut Reader<'_>) -> Option<Vec<(String, Vec<String>)>> {
    let count = reader.u32()? as usize;
    let mut packages = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        let package = reader.string()?;
        let domain_count = reader.u32()? as usize;
        let mut domains = Vec::with_capacity(domain_count.min(4096));
        for _ in 0..domain_count {
            domains.push(reader.string()?);
        }
        packages.push((package, domains));
    }
    Some(packages)
}

fn write_packages(writer: &mut Writer, packages: &[(String, Vec<String>)]) {
    writer.u32(packages.len() as u32);
    for (package, domains) in packages {
        writer.string(package);
        writer.u32(domains.len() as u32);
        for domain in domains {
            writer.string(domain);
        }
    }
}

pub fn app_allowlist(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let packages = read_packages(&mut reader)?;
    if !reader.finish() {
        return None;
    }
    let mut writer = Writer::new();
    write_packages(&mut writer, &plan::app_allowlist(packages));
    Some(writer.into_vec())
}

pub fn rule_fingerprint(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut parts = Vec::with_capacity(count.min(64));
    for _ in 0..count {
        let table = reader.string()?;
        let counts = match reader.u8()? {
            0 => None,
            1 => Some((reader.i64()?, reader.i64()?, reader.i64()?)),
            _ => return None,
        };
        parts.push((table, counts));
    }
    if !reader.finish() {
        return None;
    }
    let mut writer = Writer::new();
    writer.string(&plan::fingerprint(&parts));
    Some(writer.into_vec())
}

pub fn rewrite_rules(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut rows = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        rows.push((reader.string()?, reader.string()?));
    }
    if !reader.finish() {
        return None;
    }
    let deduped = plan::rewrite_rules(rows);
    let mut writer = Writer::new();
    writer.u32(deduped.len() as u32);
    for (pattern, target) in deduped {
        writer.string(&pattern);
        writer.string(&target);
    }
    Some(writer.into_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_layout_paths_are_the_legacy_names() {
        let paths = layout_paths(1).unwrap();
        let mut reader = Reader::new(&paths);
        for expected in [
            "rule-index/express",
            "domain",
            "hosts",
            "block.trie",
            "block.important.trie",
            "allow.trie",
            "allow.important.trie",
        ] {
            assert_eq!(reader.string().as_deref(), Some(expected));
        }
        assert!(reader.finish());
        assert_eq!(layout_paths(9), None);
    }

    #[test]
    fn dtri_validation_answers_a_status_and_the_expected_length() {
        let image = crate::dtri::compile(&[crate::dtri::Rule {
            pattern: "ads.example.com",
            source: "sub_1",
            app_scope: None,
            app_inverted: false,
            is_wildcard: false,
            denyallow: None,
            is_regex: false,
            dns_type: None,
        }]);
        let header = &image[..dtri::HEADER_SIZE as usize];

        let mut writer = Writer::new();
        writer.blob(header);
        writer.i64(image.len() as i64);
        let packed = writer.into_vec();
        let answer = dtri_validate(&packed).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(reader.i64(), Some(image.len() as i64));
        assert!(reader.finish());

        let mut writer = Writer::new();
        writer.blob(header);
        writer.i64(image.len() as i64 - 1);
        let packed = writer.into_vec();
        let answer = dtri_validate(&packed).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(4));
        assert_eq!(reader.i64(), Some(image.len() as i64));

        let mut writer = Writer::new();
        writer.blob(&header[..8]);
        writer.i64(8);
        let packed = writer.into_vec();
        let answer = dtri_validate(&packed).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(1));
    }

    #[test]
    fn the_snapshot_plan_flags_the_usable_halves() {
        let mut writer = Writer::new();
        for tag in [2u8, 1, 1, 0] {
            writer.u8(tag);
        }
        let packed = writer.into_vec();
        let answer = snapshot_plan(&packed).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u8(), Some(0));
        assert!(reader.finish());

        let mut writer = Writer::new();
        for tag in [2u8, 1, 3, 1] {
            writer.u8(tag);
        }
        let packed = writer.into_vec();
        let answer = snapshot_plan(&packed).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u8(), Some(0));
    }

    #[test]
    fn the_plan_rejects_drift() {
        assert_eq!(snapshot_plan(&[0]), None);
        assert_eq!(snapshot_plan(&[0, 0, 0, 9]), None);
        let mut writer = Writer::new();
        for tag in [0u8, 0, 0, 0, 0] {
            writer.u8(tag);
        }
        assert_eq!(snapshot_plan(&writer.into_vec()), None);
    }

    #[test]
    fn trie_paths_round_trip_four_entries() {
        let mut writer = Writer::new();
        writer.u8(1);
        writer.u32(4);
        for (path, exists, length) in [
            ("block.trie", 1u8, 100i64),
            ("block.important.trie", 1, 0),
            ("allow.trie", 0, 0),
            ("allow.important.trie", 1, 7),
        ] {
            writer.string(path);
            writer.u8(exists);
            writer.i64(length);
        }
        let payload = writer.into_vec();
        let answer = trie_paths(&payload).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("block.trie"));
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("allow.important.trie"));
        assert!(reader.finish());

        let mut writer = Writer::new();
        writer.u8(1);
        writer.u32(3);
        assert_eq!(trie_paths(&writer.into_vec()), None);
    }

    #[test]
    fn the_app_allowlist_is_normalized_on_the_way_through() {
        let mut writer = Writer::new();
        writer.u32(2);
        writer.string("com.a");
        writer.u32(3);
        writer.string(" example.com ");
        writer.string("example.com");
        writer.string("   ");
        writer.string("com.b");
        writer.u32(1);
        writer.string("");
        let packed = writer.into_vec();
        let answer = app_allowlist(&packed).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u32(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("com.a"));
        assert_eq!(reader.u32(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("example.com"));
        assert!(reader.finish());
    }

    #[test]
    fn the_fingerprint_comes_back_as_one_line() {
        let mut writer = Writer::new();
        writer.u32(2);
        writer.string("block_rule");
        writer.u8(1);
        writer.i64(10);
        writer.i64(55);
        writer.i64(9);
        writer.string("gone");
        writer.u8(0);
        let packed = writer.into_vec();
        let answer = rule_fingerprint(&packed).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(
            reader.string().as_deref(),
            Some("block_rule:10:55:9|gone:-")
        );
        assert!(reader.finish());

        let mut writer = Writer::new();
        writer.u32(1);
        writer.string("block_rule");
        writer.u8(2);
        assert_eq!(rule_fingerprint(&writer.into_vec()), None);
    }

    #[test]
    fn rewrite_rules_come_back_deduplicated() {
        let mut writer = Writer::new();
        writer.u32(3);
        writer.string(" ads.example.com ");
        writer.string(" 0.0.0.0 ");
        writer.string("ads.example.com");
        writer.string("1.1.1.1");
        writer.string("");
        writer.string("0.0.0.0");
        let packed = writer.into_vec();
        let answer = rewrite_rules(&packed).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u32(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("ads.example.com"));
        assert_eq!(reader.string().as_deref(), Some("0.0.0.0"));
        assert!(reader.finish());
    }
}
