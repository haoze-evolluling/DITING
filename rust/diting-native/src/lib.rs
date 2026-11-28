#![allow(unused_imports)]

pub use diting_engine;
pub use diting_kernels;

pub const NATIVE_ABI_VERSION: u32 = 1;

#[no_mangle]
pub extern "C" fn diting_native_abi_version() -> u32 {
    NATIVE_ABI_VERSION
}
