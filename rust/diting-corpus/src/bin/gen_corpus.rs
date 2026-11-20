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
