//! Pure-Rust cost of parsing a subscription list, without the FFI round trip or Go's decoding.
//!
//! `cargo run --release -p diting-filter-core --example parse_bench -- <corpus>`
//!
//! The corpus is a plain list file (one rule per line). Five runs, best one reported, because the
//! first pass pays for the lazy IDNA tables.

use std::time::Instant;

use diting_filter_core::parse::parse_document;

fn main() {
    let path = std::env::args().nth(1).expect("corpus path");
    let text = std::fs::read_to_string(&path).expect("read corpus");

    let mut best = f64::MAX;
    let mut rules = 0usize;
    for _ in 0..5 {
        let started = Instant::now();
        let parsed = parse_document(&text);
        let elapsed = started.elapsed().as_secs_f64() * 1000.0;
        rules = parsed.len();
        best = best.min(elapsed);
    }

    let megabytes = text.len() as f64 / (1024.0 * 1024.0);
    println!(
        "{} bytes, {rules} rules: {best:.1} ms ({:.1} MB/s)",
        text.len(),
        megabytes / (best / 1000.0)
    );
}
