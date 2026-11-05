//! Pure-Rust timing of the parse + payload encode, so the Dart benchmark can attribute the cost
//! between "native parse" and "FFI + decode".
//!
//! ```bash
//! cd rust && cargo run --release --example bench [lines]
//! ```

use diting_rule_core::document::parse_document;
use diting_rule_core::ffi::encode;

const DEFAULT_LINES: usize = 100_000;
const RUNS: usize = 4;

fn synthetic_list(count: usize) -> String {
    let mut text = String::with_capacity(count * 40);
    for index in 0..count {
        let line = match index % 8 {
            0 => format!("||ads{index}.example.com^"),
            1 => format!("0.0.0.0 tracker{index}.example.net"),
            2 => format!("example{index}.org##.ad-banner"),
            3 => format!("@@||safe{index}.example.com^$app=com.a|com.b"),
            4 => format!("/^ad[0-9]+{index}\\.example\\.com$/"),
            5 => format!("address=/masq{index}.example.com/"),
            6 => format!("||ads{}.example.com^", index - 6),
            _ => format!("! comment {index}"),
        };
        text.push_str(&line);
        text.push('\n');
    }
    text
}

fn main() {
    let lines: usize = std::env::args()
        .nth(1)
        .and_then(|value| value.parse().ok())
        .unwrap_or(DEFAULT_LINES);
    let text = synthetic_list(lines);
    println!("lines: {lines}, bytes: {}", text.len());

    let mut best_parse = u128::MAX;
    let mut best_encode = u128::MAX;
    for run in 0..RUNS {
        let started = std::time::Instant::now();
        let parsed = parse_document(&text);
        let parse_elapsed = started.elapsed().as_micros();

        let started = std::time::Instant::now();
        let payload = encode(&parsed);
        let encode_elapsed = started.elapsed().as_micros();

        // The first run also allocates the arena/string buffers for every rule, so it is dropped.
        if run > 0 {
            best_parse = best_parse.min(parse_elapsed);
            best_encode = best_encode.min(encode_elapsed);
        } else {
            println!("rules: {} (payload {} bytes)", parsed.size(), payload.len());
        }
    }
    println!(
        "rust parse: {:.1} ms ({:.0}k lines/s)",
        best_parse as f64 / 1000.0,
        lines as f64 / (best_parse as f64 / 1_000_000.0) / 1000.0
    );
    println!("rust encode: {:.1} ms", best_encode as f64 / 1000.0);
}
