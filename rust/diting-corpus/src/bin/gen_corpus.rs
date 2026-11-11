//! Regenerates the stage 0 baseline corpus.
//!
//! ```bash
//! cargo run -p diting-corpus --bin gen-corpus
//! cargo test -p diting-corpus
//! ```
//!
//! Every file is written from the current implementation, so this command is run **after** a
//! deliberate semantic change, never to make a failing test pass. `tests/corpus.rs` fails when a
//! fixture and a rebuild disagree, which is what keeps the freeze honest.

use std::fs;
use std::path::{Path, PathBuf};

use diting_corpus::{contract, dns, fixture_dir, mitm, tun};

fn main() {
    let dir = fixture_dir();
    if let Err(err) = fs::create_dir_all(&dir) {
        eprintln!("cannot create {}: {err}", dir.display());
        std::process::exit(1);
    }

    let written = [
        write(&dir, "dns_answers.json", dns::build().into_bytes()),
        write(
            &dir,
            "contract_documents.json",
            contract::build().into_bytes(),
        ),
        write(&dir, "tun_flows.pcap", tun::pcap()),
        write(&dir, "mitm_exchanges.json", mitm::build().into_bytes()),
    ];
    for entry in written.into_iter().flatten() {
        println!("wrote {}", entry.display());
    }
}

fn write(dir: &Path, name: &str, bytes: Vec<u8>) -> Option<PathBuf> {
    let path = dir.join(name);
    match fs::write(&path, &bytes) {
        Ok(()) => Some(path),
        Err(err) => {
            eprintln!("cannot write {}: {err}", path.display());
            None
        }
    }
}
