use std::sync::Once;

static INSTALL: Once = Once::new();

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
