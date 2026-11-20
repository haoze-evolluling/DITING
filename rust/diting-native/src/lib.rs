//! The single Android native artifact.
//!
//! `libditing_native.so` contains the tunnel engine's JNI facade, every Flutter/Kotlin UI kernel
//! and the LAN server runtime. Sharing one LTO unit removes the duplicate DNS/TLS/HTTP code that
//! used to be linked into `libditing_engine.so` and `libditing_server.so` separately.
//!
//! Server mode still needs its own process (root bind and privilege drop), so the APK also ships a
//! tiny `libditing_server.so` launcher. The launcher loads this library and calls
//! [`diting_server_main`]; it does not link the runtime statically.
//!
//! The `pub use` statements keep the dependency rlibs in the final link. Their `#[no_mangle]`
//! JNI/C ABI entry points remain exported; the merged library was verified with `llvm-nm` to export
//! the full union of the former engine and kernels symbols.

#![allow(unused_imports)]

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};

pub use diting_engine;
pub use diting_kernels;
pub use diting_server;

/// Version of the merged artifact. Loaders can probe this before looking up other symbols.
pub const NATIVE_ABI_VERSION: u32 = 1;

/// Returns [`NATIVE_ABI_VERSION`] so a `dart:ffi` / JNI loader can validate the merged library.
#[no_mangle]
pub extern "C" fn diting_native_abi_version() -> u32 {
    NATIVE_ABI_VERSION
}

/// Server entry point used by the tiny launcher. `argv[0]` is the launcher path and is ignored.
///
/// # Safety
/// `argv` must point to `argc` valid NUL-terminated strings, as passed to a normal `main`.
#[no_mangle]
pub unsafe extern "C" fn diting_server_main(argc: c_int, argv: *const *const c_char) -> c_int {
    if argc < 0 || (argc > 0 && argv.is_null()) {
        eprintln!("[错误] 启动器传入的参数无效");
        return 2;
    }
    let mut args = Vec::with_capacity(argc.max(0) as usize);
    for index in 1..argc {
        let pointer = *argv.add(index as usize);
        if pointer.is_null() {
            eprintln!("[错误] 启动器传入的参数包含空指针");
            return 2;
        }
        args.push(CStr::from_ptr(pointer).to_string_lossy().into_owned());
    }
    match catch_unwind(AssertUnwindSafe(|| {
        diting_server::run_with_args(args.into_iter())
    })) {
        Ok(Ok(())) => 0,
        Ok(Err(error)) => {
            eprintln!("[错误] {error}");
            1
        }
        Err(payload) => {
            eprintln!(
                "[错误] 服务器运行时 panic: {}",
                panic_message(payload.as_ref())
            );
            1
        }
    }
}

fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "未知 panic".to_string()
    }
}
