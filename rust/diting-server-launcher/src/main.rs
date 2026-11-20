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
