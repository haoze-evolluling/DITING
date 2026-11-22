use std::ffi::OsString;
use std::fs::OpenOptions;
use std::os::windows::io::AsRawHandle;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use windows_service::service::{
    ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus, ServiceType,
};
use windows_service::service_control_handler::{
    self, ServiceControlHandlerResult, ServiceStatusHandle,
};
use windows_service::service_dispatcher;
use windows_service::{define_windows_service, Error};

use diting_desktop_platform::paths;
use diting_desktop_platform::windows::SERVICE_NAME;

use crate::cli::{self, Cli, Command};

const SERVICE_TYPE: ServiceType = ServiceType::OWN_PROCESS;
const MAX_LOG_BYTES: u64 = 2 * 1024 * 1024;

define_windows_service!(ffi_service_main, service_main);

pub fn try_run_as_service(cli: &Cli) -> Option<Result<(), String>> {
    if cli.command != Command::Run {
        return None;
    }
    match service_dispatcher::start(SERVICE_NAME, ffi_service_main) {
        Ok(()) => Some(Ok(())),
        Err(Error::Winapi(error)) if error.raw_os_error() == Some(1063) => None,
        Err(error) => Some(Err(format!("连接 Windows 服务控制器失败: {error}"))),
    }
}

pub fn ensure_std_output() {
    use windows_sys::Win32::Foundation::INVALID_HANDLE_VALUE;
    use windows_sys::Win32::System::Console::{
        GetStdHandle, SetStdHandle, STD_ERROR_HANDLE, STD_OUTPUT_HANDLE,
    };

    let usable = |handle: windows_sys::Win32::Foundation::HANDLE| {
        !handle.is_null() && handle != INVALID_HANDLE_VALUE
    };
    let (stdout, stderr) = unsafe {
        (
            GetStdHandle(STD_OUTPUT_HANDLE),
            GetStdHandle(STD_ERROR_HANDLE),
        )
    };
    if usable(stdout) && usable(stderr) {
        return;
    }
    let Ok(null) = OpenOptions::new().write(true).open("NUL") else {
        return;
    };
    let handle = null.as_raw_handle();
    unsafe {
        if !usable(stdout) {
            SetStdHandle(STD_OUTPUT_HANDLE, handle);
        }
        if !usable(stderr) {
            SetStdHandle(STD_ERROR_HANDLE, handle);
        }
    }
    std::mem::forget(null);
}

fn service_main(arguments: Vec<OsString>) {
    let _ = arguments;
    let stop = Arc::new(tokio::sync::Notify::new());
    let handler_signal = Arc::clone(&stop);
    let status_slot: Arc<Mutex<Option<ServiceStatusHandle>>> = Arc::new(Mutex::new(None));
    let handler_status = Arc::clone(&status_slot);

    let handler = move |control| match control {
        ServiceControl::Stop | ServiceControl::Shutdown => {
            if let Ok(slot) = handler_status.lock() {
                if let Some(status) = slot.as_ref() {
                    report(
                        status,
                        ServiceState::StopPending,
                        ServiceControlAccept::empty(),
                    );
                }
            }
            handler_signal.notify_one();
            ServiceControlHandlerResult::NoError
        }
        ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
        _ => ServiceControlHandlerResult::NotImplemented,
    };
    let status = match service_control_handler::register(SERVICE_NAME, handler) {
        Ok(status) => status,
        Err(_) => return,
    };
    if let Ok(mut slot) = status_slot.lock() {
        *slot = Some(status);
    }

    report(
        &status,
        ServiceState::StartPending,
        ServiceControlAccept::empty(),
    );
    redirect_output();
    println!("[服务] 由 Windows 服务控制器启动");

    let cli = cli::parse(std::env::args()).unwrap_or_else(|error| {
        eprintln!("[服务] 参数解析失败，使用默认运行参数: {error}");
        Cli {
            command: Command::Run,
            ..Cli::default()
        }
    });

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build();
    let runtime = match runtime {
        Ok(runtime) => runtime,
        Err(error) => {
            eprintln!("[服务] 初始化异步运行时失败: {error}");
            report(
                &status,
                ServiceState::Stopped,
                ServiceControlAccept::empty(),
            );
            return;
        }
    };

    report(
        &status,
        ServiceState::Running,
        ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN,
    );
    let result = runtime.block_on(crate::run(&cli, async move { stop.notified().await }));
    report(
        &status,
        ServiceState::Stopped,
        ServiceControlAccept::empty(),
    );
    match result {
        Ok(()) => println!("[服务] 已停止"),
        Err(error) => eprintln!("[服务] 运行失败: {error}"),
    }
}

fn report(status: &ServiceStatusHandle, state: ServiceState, accepted: ServiceControlAccept) {
    let pending = matches!(
        state,
        ServiceState::StartPending | ServiceState::StopPending
    );
    let _ = status.set_service_status(ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: state,
        controls_accepted: accepted,
        exit_code: ServiceExitCode::NO_ERROR,
        checkpoint: u32::from(pending),
        wait_hint: Duration::from_secs(10),
        process_id: None,
    });
}

fn redirect_output() {
    let directory = paths::default_data_dir();
    if let Err(error) = std::fs::create_dir_all(&directory) {
        eprintln!("[服务] 创建日志目录失败: {error}");
    }
    let path = directory.join("service.log");
    if let Ok(metadata) = std::fs::metadata(&path) {
        if metadata.len() > MAX_LOG_BYTES {
            let _ = std::fs::remove_file(&path);
        }
    }
    let log = OpenOptions::new().create(true).append(true).open(&path);
    let log = match log {
        Ok(log) => log,
        Err(error) => {
            eprintln!("[服务] 打开日志文件失败: {error}");
            match OpenOptions::new().write(true).open("NUL") {
                Ok(null) => null,
                Err(_) => return,
            }
        }
    };
    unsafe {
        use windows_sys::Win32::System::Console::{
            SetStdHandle, STD_ERROR_HANDLE, STD_OUTPUT_HANDLE,
        };
        let handle = log.as_raw_handle();
        SetStdHandle(STD_OUTPUT_HANDLE, handle);
        SetStdHandle(STD_ERROR_HANDLE, handle);
    }
    std::mem::forget(log);
}
