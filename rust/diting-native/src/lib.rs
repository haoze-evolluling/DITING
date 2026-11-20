#![allow(unused_imports)]

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};

pub use diting_engine;
pub use diting_kernels;
pub use diting_server;

pub const NATIVE_ABI_VERSION: u32 = 1;

#[no_mangle]
pub extern "C" fn diting_native_abi_version() -> u32 {
    NATIVE_ABI_VERSION
}

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
