#include "tray_service.h"

#include <windows.h>

#include <shellapi.h>

#include <algorithm>
#include <cwchar>
#include <cwctype>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kServiceRegistryPath[] =
    L"SYSTEM\\CurrentControlSet\\Services\\DitingDNSService";

// How far up the directory chain the development build layout is searched:
// Release -> runner -> x64 -> windows -> build -> diting_desktop -> apps ->
// DITING-Flutter -> DITING (where Server\build\bin\diting-service.exe lives).
constexpr int kMaxParentLevels = 12;

std::wstring SystemMessage(DWORD code) {
  wchar_t* buffer = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<LPWSTR>(&buffer), 0, nullptr);
  std::wstring message;
  if (length != 0 && buffer != nullptr) {
    message.assign(buffer, length);
    while (!message.empty() &&
           (message.back() == L'\r' || message.back() == L'\n' ||
            message.back() == L' ')) {
      message.pop_back();
    }
  }
  if (buffer != nullptr) {
    LocalFree(buffer);
  }
  if (message.empty()) {
    message = L"错误代码 " + std::to_wstring(code);
  }
  return message;
}

bool FileExists(const std::wstring& path) {
  if (path.empty()) {
    return false;
  }
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring ExpandEnvironment(const std::wstring& value) {
  if (value.empty()) {
    return value;
  }
  wchar_t buffer[1024];
  const DWORD length = ExpandEnvironmentStringsW(value.c_str(), buffer,
                                                 ARRAYSIZE(buffer));
  if (length == 0 || length > ARRAYSIZE(buffer)) {
    return value;
  }
  return std::wstring(buffer, length - 1);
}

std::wstring TrimQuotes(std::wstring value) {
  const size_t first = value.find_first_not_of(L" \t\"");
  if (first == std::wstring::npos) {
    return std::wstring();
  }
  const size_t last = value.find_last_not_of(L" \t\"");
  return value.substr(first, last - first + 1);
}

// The SCM ImagePath may carry arguments; the executable itself ends at ".exe".
std::wstring CutAtExecutable(std::wstring path) {
  std::wstring lowered = path;
  std::transform(lowered.begin(), lowered.end(), lowered.begin(),
                 [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
  const size_t index = lowered.find(L".exe");
  if (index == std::wstring::npos) {
    return path;
  }
  return path.substr(0, index + 4);
}

std::wstring ImagePathFromScm() {
  DWORD size = 0;
  if (RegGetValueW(HKEY_LOCAL_MACHINE, kServiceRegistryPath, L"ImagePath",
                   RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ, nullptr, nullptr,
                   &size) != ERROR_SUCCESS ||
      size < sizeof(wchar_t)) {
    return std::wstring();
  }
  std::wstring buffer(size / sizeof(wchar_t), L'\0');
  if (RegGetValueW(HKEY_LOCAL_MACHINE, kServiceRegistryPath, L"ImagePath",
                   RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ, nullptr,
                   buffer.data(), &size) != ERROR_SUCCESS) {
    return std::wstring();
  }
  buffer.resize(wcslen(buffer.c_str()));
  return CutAtExecutable(TrimQuotes(ExpandEnvironment(buffer)));
}

std::wstring ExecutableDirectory() {
  std::wstring buffer(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length =
        GetModuleFileNameW(nullptr, buffer.data(),
                           static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return std::wstring();
    }
    if (static_cast<size_t>(length) < buffer.size()) {
      buffer.resize(length);
      break;
    }
    buffer.resize(buffer.size() * 2);
  }
  const size_t separator = buffer.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return std::wstring();
  }
  return buffer.substr(0, separator);
}

std::wstring FindInBuildLayout(std::wstring directory) {
  for (int level = 0; level < kMaxParentLevels; ++level) {
    if (directory.empty()) {
      break;
    }
    const std::vector<std::wstring> candidates = {
        directory + L"\\" + kTrayServiceExecutable,
        directory + L"\\build\\bin\\" + kTrayServiceExecutable,
        directory + L"\\Server\\build\\bin\\" + kTrayServiceExecutable,
    };
    for (const std::wstring& candidate : candidates) {
      if (FileExists(candidate)) {
        return candidate;
      }
    }
    const size_t separator = directory.find_last_of(L"\\/");
    if (separator == std::wstring::npos) {
      break;
    }
    directory.resize(separator);
  }
  return std::wstring();
}

std::wstring FindOnPath() {
  wchar_t buffer[MAX_PATH];
  const DWORD length =
      SearchPathW(nullptr, kTrayServiceExecutable, nullptr, ARRAYSIZE(buffer),
                  buffer, nullptr);
  if (length == 0 || length >= ARRAYSIZE(buffer)) {
    return std::wstring();
  }
  return std::wstring(buffer, length);
}

bool IsProcessElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION elevation{};
  DWORD size = sizeof(elevation);
  const BOOL ok =
      GetTokenInformation(token, TokenElevation, &elevation, size, &size);
  CloseHandle(token);
  return ok != FALSE && elevation.TokenIsElevated != 0;
}

// Runs |executable| with |arguments| through the UAC prompt and waits for it,
// exactly like the old desktop's runElevatedNative.
bool RunElevated(const std::wstring& executable, const std::wstring& arguments,
                 std::wstring* error) {
  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
  info.lpVerb = L"runas";
  info.lpFile = executable.c_str();
  info.lpParameters = arguments.empty() ? nullptr : arguments.c_str();
  info.nShow = SW_HIDE;

  if (!ShellExecuteExW(&info)) {
    const DWORD code = GetLastError();
    if (code == ERROR_CANCELLED) {
      *error = L"已取消管理员授权";
    } else {
      *error = L"无法启动提权进程: " + SystemMessage(code);
    }
    return false;
  }
  if (info.hProcess == nullptr) {
    return true;
  }

  WaitForSingleObject(info.hProcess, INFINITE);
  DWORD exit_code = 0;
  const BOOL ok = GetExitCodeProcess(info.hProcess, &exit_code);
  CloseHandle(info.hProcess);
  if (!ok) {
    *error = L"无法获取提权进程退出代码: " + SystemMessage(GetLastError());
    return false;
  }
  if (exit_code != 0) {
    *error = L"提权服务操作失败（退出代码 " + std::to_wstring(exit_code) + L"）";
    return false;
  }
  return true;
}

bool RunElevatedServiceCommand(const std::wstring& verb, std::wstring* error) {
  const std::wstring executable = tray_service::LocateExecutable();
  if (executable.empty()) {
    *error = L"未找到 diting-service.exe，无法操作核心服务";
    return false;
  }
  return RunElevated(executable, L"-service " + verb, error);
}

bool StartDirect(std::wstring* error) {
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (manager == nullptr) {
    *error = L"打开服务控制管理器失败: " + SystemMessage(GetLastError());
    return false;
  }
  SC_HANDLE service =
      OpenServiceW(manager, kTrayServiceName, SERVICE_START);
  if (service == nullptr) {
    const DWORD code = GetLastError();
    CloseServiceHandle(manager);
    *error = L"打开核心服务失败: " + SystemMessage(code);
    return false;
  }

  const BOOL started = StartServiceW(service, 0, nullptr);
  const DWORD code = started ? ERROR_SUCCESS : GetLastError();
  CloseServiceHandle(service);
  CloseServiceHandle(manager);

  if (started || code == ERROR_SERVICE_ALREADY_RUNNING) {
    return true;
  }
  *error = L"启动核心服务失败: " + SystemMessage(code);
  return false;
}

bool StopDirect(std::wstring* error) {
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (manager == nullptr) {
    *error = L"打开服务控制管理器失败: " + SystemMessage(GetLastError());
    return false;
  }
  SC_HANDLE service = OpenServiceW(manager, kTrayServiceName,
                                   SERVICE_STOP | SERVICE_QUERY_STATUS);
  if (service == nullptr) {
    const DWORD code = GetLastError();
    CloseServiceHandle(manager);
    *error = L"打开核心服务失败: " + SystemMessage(code);
    return false;
  }

  SERVICE_STATUS status{};
  const BOOL stopped = ControlService(service, SERVICE_CONTROL_STOP, &status);
  const DWORD code = stopped ? ERROR_SUCCESS : GetLastError();
  CloseServiceHandle(service);
  CloseServiceHandle(manager);

  if (stopped || code == ERROR_SERVICE_NOT_ACTIVE) {
    return true;
  }
  *error = L"停止核心服务失败: " + SystemMessage(code);
  return false;
}

// Restarting in-process means waiting for the SCM to settle; the caller is a
// worker thread, so a bounded poll (3s, like the old Go manager) is safe.
bool RestartDirect(std::wstring* error) {
  if (!StopDirect(error)) {
    return false;
  }
  for (int attempt = 0; attempt < 30; ++attempt) {
    if (!tray_service::QueryStatus().running) {
      break;
    }
    Sleep(100);
  }
  return StartDirect(error);
}

}  // namespace

namespace tray_service {

TrayServiceStatus QueryStatus() {
  TrayServiceStatus status;
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (manager == nullptr) {
    return status;
  }
  SC_HANDLE service =
      OpenServiceW(manager, kTrayServiceName, SERVICE_QUERY_STATUS);
  if (service == nullptr) {
    const DWORD code = GetLastError();
    CloseServiceHandle(manager);
    // "Not installed" is still a known answer (it is not running); only a
    // manager we cannot talk to leaves the state unknown.
    status.known = code == ERROR_SERVICE_DOES_NOT_EXIST;
    return status;
  }

  SERVICE_STATUS service_status{};
  if (QueryServiceStatus(service, &service_status)) {
    status.known = true;
    status.installed = true;
    status.running = service_status.dwCurrentState == SERVICE_RUNNING ||
                     service_status.dwCurrentState == SERVICE_START_PENDING ||
                     service_status.dwCurrentState == SERVICE_CONTINUE_PENDING;
  }
  CloseServiceHandle(service);
  CloseServiceHandle(manager);
  return status;
}

std::wstring LocateExecutable() {
  const std::wstring from_scm = ImagePathFromScm();
  if (FileExists(from_scm)) {
    return from_scm;
  }

  const std::wstring directory = ExecutableDirectory();
  if (!directory.empty()) {
    const std::wstring beside_gui = directory + L"\\" + kTrayServiceExecutable;
    if (FileExists(beside_gui)) {
      return beside_gui;
    }
  }

  const std::wstring in_layout = FindInBuildLayout(directory);
  if (!in_layout.empty()) {
    return in_layout;
  }
  return FindOnPath();
}

bool Start(std::wstring* error) {
  error->clear();
  if (IsProcessElevated() && StartDirect(error)) {
    return true;
  }
  return RunElevatedServiceCommand(L"start", error);
}

bool Stop(std::wstring* error) {
  error->clear();
  if (IsProcessElevated() && StopDirect(error)) {
    return true;
  }
  return RunElevatedServiceCommand(L"stop", error);
}

bool Restart(std::wstring* error) {
  error->clear();
  if (IsProcessElevated() && RestartDirect(error)) {
    return true;
  }
  return RunElevatedServiceCommand(L"restart", error);
}

}  // namespace tray_service
