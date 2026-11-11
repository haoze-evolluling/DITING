//! Replays the fixtures captured from the Dart implementation before it was replaced.

use serde_json::{Map, Value};

use diting_subscription_core::model::{
    auto_update_status, group_from_row, import_state, item_from_row, kind, record_from_row,
    source_type,
};
use diting_subscription_core::url::{
    build_mirror, count_effective_lines, extract_name, normalize_template, validate, UrlParts,
};

fn fixture(name: &str) -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name);
    let text = std::fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    serde_json::from_str(&text).expect("fixture JSON")
}

fn parts(case: &Value) -> UrlParts {
    UrlParts {
        parsed: case["parsed"].as_bool().unwrap_or(false),
        has_scheme: case["hasScheme"].as_bool().unwrap_or(false),
        scheme: case["scheme"].as_str().unwrap_or_default().to_owned(),
        host: case["host"].as_str().unwrap_or_default().to_owned(),
        path: case["path"].as_str().unwrap_or_default().to_owned(),
        query: case["query"].as_str().unwrap_or_default().to_owned(),
    }
}

fn kind_of<T: std::fmt::Debug>(result: Result<T, impl AsRef<str>>) -> Option<String> {
    result.err().map(|error| error.as_ref().to_owned())
}

fn chosen(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned()
}

#[test]
fn url_fixtures() {
    let fixture = fixture("url.json");

    for case in fixture["urls"].as_array().unwrap() {
        let parts = parts(case);
        let address = chosen(case, "url");
        let error = match validate(&address, &parts) {
            Ok(()) => None,
            Err(kind) => Some(kind.as_str().to_owned()),
        };
        assert_eq!(
            error,
            case["validateKind"].as_str().map(str::to_owned),
            "{address}"
        );

        assert_eq!(
            extract_name(&address, &parts.path, &parts.host),
            chosen(case, "name"),
            "{address}"
        );

        let built = build_mirror("https://m.example.com/{url}", &address, &parts);
        assert_eq!(
            built.as_deref().ok().map(str::to_owned),
            case["build"].as_str().map(str::to_owned),
            "build {address}"
        );
        assert_eq!(
            kind_of(built),
            case["buildKind"].as_str().map(str::to_owned),
            "build kind {address}"
        );

        let example = build_mirror(
            "https://m.example.com/{scheme}/{host}{pathAndQuery}",
            &address,
            &parts,
        );
        assert_eq!(
            example.as_deref().ok().map(str::to_owned),
            case["example"].as_str().map(str::to_owned),
            "example {address}"
        );
        assert_eq!(
            kind_of(example),
            case["exampleKind"].as_str().map(str::to_owned),
            "example kind {address}"
        );
    }

    for case in fixture["templates"].as_array().unwrap() {
        let template = case["template"].as_str();
        let normalized = normalize_template(template);
        assert_eq!(
            normalized.as_ref().ok().cloned().flatten(),
            case["normalized"].as_str().map(str::to_owned),
            "normalize {template:?}"
        );
        assert_eq!(
            kind_of(normalized),
            case["normalizeKind"].as_str().map(str::to_owned),
            "normalize kind {template:?}"
        );

        let example = &case["exampleComponents"];
        let parts = UrlParts {
            parsed: true,
            has_scheme: true,
            scheme: chosen(example, "scheme"),
            host: chosen(example, "host"),
            path: chosen(example, "path"),
            query: chosen(example, "query"),
        };
        let built = build_mirror(
            template.unwrap_or_default(),
            "https://example.com/rules.txt?q=1",
            &parts,
        );
        assert_eq!(
            built.as_deref().ok().map(str::to_owned),
            case["build"].as_str().map(str::to_owned),
            "template build {template:?}"
        );
        assert_eq!(
            kind_of(built),
            case["buildKind"].as_str().map(str::to_owned),
            "template build kind {template:?}"
        );
    }

    for case in fixture["contents"].as_array().unwrap() {
        assert_eq!(
            count_effective_lines(case["content"].as_str().unwrap()),
            case["lines"].as_i64().unwrap(),
            "lines {:?}",
            case["content"]
        );
    }
}

fn without_is_remote(expected: &Value) -> Value {
    let mut map = expected.as_object().cloned().unwrap_or_else(Map::new);
    map.remove("isRemote");
    Value::Object(map)
}

#[test]
fn model_fixtures() {
    let fixture = fixture("model.json");

    for case in fixture["records"].as_array().unwrap() {
        let parsed = record_from_row(&case["row"]);
        assert_eq!(
            parsed,
            without_is_remote(&case["expected"]),
            "{:?}",
            case["row"]
        );
        let expected_remote = case["expected"]["isRemote"].as_bool().unwrap_or(false);
        assert_eq!(
            parsed["sourceType"].as_str() != Some("local"),
            expected_remote,
            "{:?}",
            case["row"]
        );
    }

    for case in fixture["groups"].as_array().unwrap() {
        assert_eq!(
            group_from_row(&case["row"]),
            case["expected"],
            "{:?}",
            case["row"]
        );
    }

    for case in fixture["items"].as_array().unwrap() {
        assert_eq!(
            item_from_row(&case["row"]),
            case["expected"],
            "{:?}",
            case["row"]
        );
    }

    for (key, expected) in fixture["kinds"].as_object().unwrap() {
        let value = (key != "null").then_some(key.as_str());
        assert_eq!(
            kind(value),
            expected["normalize"].as_str().unwrap(),
            "{key}"
        );
        let canonical = matches!(
            value.map(|value| value.trim().to_lowercase()).as_deref(),
            Some("domain") | Some("hosts")
        );
        assert_eq!(canonical, expected["canonical"].as_bool().unwrap(), "{key}");
    }
    for (key, expected) in fixture["sourceTypes"].as_object().unwrap() {
        let value = (key != "null").then_some(key.as_str());
        assert_eq!(source_type(value), expected.as_str().unwrap(), "{key}");
    }
    for (key, expected) in fixture["importStates"].as_object().unwrap() {
        let value = (key != "null").then_some(key.as_str());
        assert_eq!(import_state(value), expected.as_str().unwrap(), "{key}");
    }
    for (key, expected) in fixture["autoUpdateStatuses"].as_object().unwrap() {
        let value = (key != "null").then_some(key.as_str());
        assert_eq!(
            auto_update_status(value),
            expected.as_str().unwrap(),
            "{key}"
        );
    }
}
