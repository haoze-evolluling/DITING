use std::ffi::{CStr, CString};
use std::fs::File;
use std::os::fd::AsRawFd;
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

type ServerMain = unsafe extern "C" fn(c_int, *const *const c_char) -> c_int;

const NATIVE_LIBRARY: &str = "libditing_native.so";

pub fn run() {
    let code = match launch() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("[启动器] {error}");
            1
        }
    };
    std::process::exit(code);
}

fn launch() -> Result<c_int, String> {
    let executable =
        std::env::current_exe().map_err(|error| format!("无法定位启动器路径: {error}"))?;
    let library = library_path(&executable)?;
    let library_c = CString::new(library.as_os_str().as_bytes())
        .map_err(|_| format!("库路径包含空字节: {}", library.display()))?;

    let file =
        File::open(&library).map_err(|error| format!("无法打开 {}: {error}", library.display()))?;
    let handle = unsafe { open_library(&library_c, &file) }
        .map_err(|error| format!("无法加载 {}: {error}", library.display()))?;
    let symbol = unsafe { lookup(handle, b"diting_server_main\0") }
        .ok_or_else(|| "libditing_native.so 缺少 diting_server_main".to_string());
    let symbol = match symbol {
        Ok(symbol) => symbol,
        Err(error) => {
            unsafe { libc::dlclose(handle) };
            return Err(error);
        }
    };

    let args = std::env::args_os()
        .map(|arg| CString::new(arg.as_bytes()).map_err(|_| "启动参数包含空字节".to_string()))
        .collect::<Result<Vec<_>, _>>()?;
    let mut pointers: Vec<*const c_char> = args.iter().map(|arg| arg.as_ptr()).collect();
    pointers.push(std::ptr::null());
    let entry: ServerMain = unsafe { std::mem::transmute(symbol) };
    let code = unsafe { entry(args.len() as c_int, pointers.as_ptr()) };
    let _ = handle;
    drop(file);
    Ok(code)
}

fn library_path(executable: &Path) -> Result<PathBuf, String> {
    if let Ok(override_path) = std::env::var("DITING_NATIVE_LIB") {
        if !override_path.trim().is_empty() {
            return Ok(PathBuf::from(override_path));
        }
    }
    let directory = executable
        .parent()
        .ok_or_else(|| format!("启动器路径没有父目录: {}", executable.display()))?;
    let candidate = directory.join(NATIVE_LIBRARY);
    if candidate.is_file() {
        let _ = std::fs::set_permissions(&candidate, std::fs::Permissions::from_mode(0o755));
        return Ok(candidate);
    }
    Err(format!(
        "{} 同级目录缺少 {}",
        directory.display(),
        NATIVE_LIBRARY
    ))
}

unsafe fn lookup(handle: *mut c_void, name: &[u8]) -> Option<*mut c_void> {
    let symbol = libc::dlsym(handle, name.as_ptr() as *const c_char);
    if symbol.is_null() {
        None
    } else {
        Some(symbol)
    }
}

#[cfg(target_os = "android")]
unsafe fn open_library(path: &CString, file: &File) -> Result<*mut c_void, String> {
    let mut info = AndroidDlExtInfo {
        flags: ANDROID_DLEXT_USE_LIBRARY_FD,
        reserved_addr: std::ptr::null_mut(),
        reserved_size: 0,
        relro_fd: -1,
        library_fd: file.as_raw_fd(),
        library_fd_offset: 0,
        library_namespace: std::ptr::null_mut(),
    };
    let handle = android_dlopen_ext(path.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL, &mut info);
    if !handle.is_null() {
        return Ok(handle);
    }
    let first_error = linker_error();
    let fallback = libc::dlopen(path.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL);
    if fallback.is_null() {
        return Err(format!(
            "android_dlopen_ext: {first_error}; dlopen: {}",
            linker_error()
        ));
    }
    Ok(fallback)
}

#[cfg(not(target_os = "android"))]
unsafe fn open_library(path: &CString, _file: &File) -> Result<*mut c_void, String> {
    let handle = libc::dlopen(path.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL);
    if handle.is_null() {
        Err(linker_error())
    } else {
        Ok(handle)
    }
}

unsafe fn linker_error() -> String {
    let pointer = libc::dlerror();
    if pointer.is_null() {
        "未知动态链接器错误".to_string()
    } else {
        CStr::from_ptr(pointer).to_string_lossy().into_owned()
    }
}

#[cfg(target_os = "android")]
const ANDROID_DLEXT_USE_LIBRARY_FD: u64 = 0x10;

#[cfg(target_os = "android")]
#[repr(C)]
struct AndroidDlExtInfo {
    flags: u64,
    reserved_addr: *mut c_void,
    reserved_size: usize,
    relro_fd: c_int,
    library_fd: c_int,
    library_fd_offset: i64,
    library_namespace: *mut c_void,
}

#[cfg(target_os = "android")]
extern "C" {
    fn android_dlopen_ext(
        filename: *const c_char,
        flags: c_int,
        extinfo: *const AndroidDlExtInfo,
    ) -> *mut c_void;
}
