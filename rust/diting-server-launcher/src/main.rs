//! Minimal launcher for server mode. It keeps the DNS runtime inside `libditing_native.so` so the
//! APK does not carry a second statically linked copy of the resolver/TLS/HTTP stack.

#[cfg(unix)]
mod unix;

#[cfg(unix)]
fn main() {
    unix::run();
}

#[cfg(not(unix))]
fn main() {
    eprintln!("服务器模式启动器仅支持 Unix/Android");
    std::process::exit(1);
}
