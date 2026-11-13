//! A one-line panic record on Android logcat.
//!
//! Every JNI entry point wraps its body in `catch_unwind`, so an engine panic is turned into a Java
//! exception and never reaches the app's crash reporter. This hook writes the panic to logcat before
//! unwinding; the `--uid` runtime-log capture then keeps that line, so an engine failure below the
//! crash threshold is still diagnosable. On non-Android targets it is a no-op, so host tests are
//! unaffected and the hook is never installed there in a way that changes test output.

use std::sync::Once;

static INSTALL: Once = Once::new();

/// Installs the hook once. Safe to call from every `nativeNew`; later calls do nothing.
pub fn install() {
    INSTALL.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            log_fatal(&info.to_string());
            previous(info);
        }));
    });
}

#[cfg(target_os = "android")]
fn log_fatal(message: &str) {
    use std::ffi::CString;
    let Ok(text) = CString::new(message.replace('\0', " ")) else {
        return;
    };
    let tag = CString::new("diting-engine").expect("static tag has no NUL");
    // ANDROID_LOG_ERROR = 6.
    unsafe {
        __android_log_write(6, tag.as_ptr(), text.as_ptr());
    }
}

#[cfg(not(target_os = "android"))]
fn log_fatal(_message: &str) {}

#[cfg(target_os = "android")]
#[link(name = "log")]
extern "C" {
    fn __android_log_write(
        prio: std::os::raw::c_int,
        tag: *const std::os::raw::c_char,
        text: *const std::os::raw::c_char,
    ) -> std::os::raw::c_int;
}
