fn main() {
    if let Err(error) = diting_server::run_from_env() {
        eprintln!("[错误] {error}");
        std::process::exit(1);
    }
}
