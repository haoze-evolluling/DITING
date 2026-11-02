#include "tray_autostart.h"

#include <windows.h>

#include <string>

namespace {

// Kept identical to the old desktop so an existing install keeps its entry
// (the service's own login check also looks for this exact value name).
constexpr wchar_t kRunKeyPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValueName[] = L"DitingDNS";

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

std::wstring ExecutablePath() {
  std::wstring buffer(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return std::wstring();
    }
    if (static_cast<size_t>(length) < buffer.size()) {
      buffer.resize(length);
      return buffer;
    }
    buffer.resize(buffer.size() * 2);
  }
}

}  // namespace

namespace tray_autostart {

bool IsEnabled() {
  DWORD size = 0;
  return RegGetValueW(HKEY_CURRENT_USER, kRunKeyPath, kRunValueName,
                      RRF_RT_REG_SZ, nullptr, nullptr, &size) == ERROR_SUCCESS;
}

bool SetEnabled(bool enable, std::wstring* error) {
  error->clear();
  if (!enable) {
    HKEY key = nullptr;
    const LSTATUS opened = RegOpenKeyExW(HKEY_CURRENT_USER, kRunKeyPath, 0,
                                         KEY_SET_VALUE, &key);
    if (opened == ERROR_FILE_NOT_FOUND) {
      return true;
    }
    if (opened != ERROR_SUCCESS) {
      *error = L"访问注册表失败: " + SystemMessage(opened);
      return false;
    }
    const LSTATUS deleted = RegDeleteValueW(key, kRunValueName);
    RegCloseKey(key);
    if (deleted != ERROR_SUCCESS && deleted != ERROR_FILE_NOT_FOUND) {
      *error = L"删除自启注册表失败: " + SystemMessage(deleted);
      return false;
    }
    return true;
  }

  const std::wstring executable = ExecutablePath();
  if (executable.empty()) {
    *error = L"获取执行路径失败";
    return false;
  }

  HKEY key = nullptr;
  const LSTATUS created = RegCreateKeyExW(
      HKEY_CURRENT_USER, kRunKeyPath, 0, nullptr, REG_OPTION_NON_VOLATILE,
      KEY_SET_VALUE, nullptr, &key, nullptr);
  if (created != ERROR_SUCCESS) {
    *error = L"访问注册表失败: " + SystemMessage(created);
    return false;
  }
  const std::wstring command = L"\"" + executable + L"\" --minimized";
  const LSTATUS written = RegSetValueExW(
      key, kRunValueName, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(command.c_str()),
      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  if (written != ERROR_SUCCESS) {
    *error = L"写入自启注册表失败: " + SystemMessage(written);
    return false;
  }
  return true;
}

}  // namespace tray_autostart
