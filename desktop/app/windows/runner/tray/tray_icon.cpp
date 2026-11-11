#include "tray_icon.h"

#include <shellapi.h>

#include <mutex>
#include <thread>
#include <utility>

#include "tray_autostart.h"
#include "tray_service.h"

namespace {

// Both live in the WM_APP range, which Flutter does not use for its own
// top-level messages (it registers named messages instead).
constexpr UINT kTrayCallbackMessage = WM_APP + 200;
constexpr UINT kTrayBalloonMessage = WM_APP + 201;
constexpr UINT kTrayIconId = 1;

constexpr UINT kMenuShowWindow = 1001;
constexpr UINT kMenuHideWindow = 1002;
constexpr UINT kMenuAutoStart = 1003;
constexpr UINT kMenuServiceStatus = 1004;
constexpr UINT kMenuServiceStart = 1005;
constexpr UINT kMenuServiceStop = 1006;
constexpr UINT kMenuServiceRestart = 1007;
constexpr UINT kMenuQuit = 1008;

// Pending balloon text, reachable from worker threads without touching the
// TrayIcon instance: a service operation may finish after the window is gone,
// and a raw `this` would then be dangling.
struct BalloonSlot {
  std::mutex mutex;
  std::wstring title;
  std::wstring text;
  bool pending = false;
};

// Intentionally leaked: a detached service operation may outlive static
// destruction, and a freed std::mutex is worse than a leaked one.
BalloonSlot& Balloon() {
  static BalloonSlot* slot = new BalloonSlot();
  return *slot;
}

void PostBalloon(HWND owner, std::wstring title, std::wstring text) {
  BalloonSlot& slot = Balloon();
  {
    std::lock_guard<std::mutex> lock(slot.mutex);
    slot.title = std::move(title);
    slot.text = std::move(text);
    slot.pending = true;
  }
  if (owner != nullptr) {
    PostMessageW(owner, kTrayBalloonMessage, 0, 0);
  }
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

// The icon comes from the executable's own first icon group, which is the
// brand icon compiled in from resources/app_icon.ico. The fallback is the
// system-shared IDI_APPLICATION, which must never be destroyed.
HICON LoadTrayIcon(bool* owned) {
  // rpcndr.h defines `small` as a macro (char), hence the _icon suffixes.
  HICON large_icon = nullptr;
  HICON small_icon = nullptr;
  const std::wstring path = ExecutablePath();
  if (!path.empty() &&
      ExtractIconExW(path.c_str(), 0, &large_icon, &small_icon, 1) > 0) {
    HICON chosen = small_icon != nullptr ? small_icon : large_icon;
    if (small_icon != nullptr && large_icon != nullptr) {
      DestroyIcon(large_icon);
    }
    if (chosen != nullptr) {
      *owned = true;
      return chosen;
    }
  }
  *owned = false;
  return LoadIconW(nullptr, IDI_APPLICATION);
}

void AppendItem(HMENU menu, UINT flags, UINT id, const std::wstring& text) {
  AppendMenuW(menu, flags, id, text.empty() ? nullptr : text.c_str());
}

}  // namespace

TrayIcon::TrayIcon() = default;

TrayIcon::~TrayIcon() {
  Destroy();
}

bool TrayIcon::Create(HWND owner) {
  if (owner == nullptr) {
    return false;
  }
  owner_ = owner;
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");

  // Running elevated would otherwise let UIPI drop the messages Explorer sends
  // to this window, leaving a dead tray icon.
  ChangeWindowMessageFilter(kTrayCallbackMessage, MSGFLT_ADD);
  if (taskbar_created_message_ != 0) {
    ChangeWindowMessageFilter(taskbar_created_message_, MSGFLT_ADD);
  }

  icon_ = LoadTrayIcon(&owns_icon_);
  return AddIcon();
}

void TrayIcon::Destroy() {
  if (owner_ != nullptr && icon_ != nullptr) {
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = owner_;
    data.uID = kTrayIconId;
    Shell_NotifyIconW(NIM_DELETE, &data);
  }
  if (icon_ != nullptr && owns_icon_) {
    DestroyIcon(icon_);
  }
  {
    BalloonSlot& slot = Balloon();
    std::lock_guard<std::mutex> lock(slot.mutex);
    slot.pending = false;
  }
  owner_ = nullptr;
  icon_ = nullptr;
  owns_icon_ = false;
  taskbar_created_message_ = 0;
  version4_ = false;
  menu_active_ = false;
  quit_handler_ = nullptr;
}

void TrayIcon::SetLabels(const TrayLabels& labels) {
  labels_ = labels;
  if (owner_ == nullptr || icon_ == nullptr) {
    return;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = owner_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_TIP;
  wcsncpy_s(data.szTip, labels_.tooltip.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

bool TrayIcon::AddIcon() {
  if (owner_ == nullptr || icon_ == nullptr) {
    return false;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = owner_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = icon_;
  wcsncpy_s(data.szTip, labels_.tooltip.c_str(), _TRUNCATE);

  if (!Shell_NotifyIconW(NIM_ADD, &data)) {
    return false;
  }
  SetVersion();
  return true;
}

// NOTIFYICON_VERSION_4 makes the icon disappear with the process instead of
// lingering, and delivers the semantic NIN_SELECT / WM_CONTEXTMENU events.
void TrayIcon::SetVersion() {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = owner_;
  data.uID = kTrayIconId;
  data.uVersion = NOTIFYICON_VERSION_4;
  version4_ = Shell_NotifyIconW(NIM_SETVERSION, &data) != FALSE;
}

bool TrayIcon::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kTrayCallbackMessage) {
    OnCallback(wparam, lparam);
    return true;
  }
  if (message == kTrayBalloonMessage) {
    ShowPendingBalloon();
    return true;
  }
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    // Explorer restarted: the registration is gone, put the icon back.
    AddIcon();
    return true;
  }
  return false;
}

void TrayIcon::OnCallback(WPARAM wparam, LPARAM lparam) {
  const UINT event = static_cast<UINT>(LOWORD(lparam));

  // Version 4 delivers both WM_RBUTTONUP and the semantic WM_CONTEXTMENU for a
  // single right click; acting on both would pop a second menu right after the
  // first was dismissed.
  if (event == WM_CONTEXTMENU || (!version4_ && event == WM_RBUTTONUP)) {
    ShowContextMenu(wparam);
    return;
  }

  switch (event) {
    case NIN_SELECT:
    case NIN_KEYSELECT:
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
    case NIN_BALLOONUSERCLICK:
      ShowWindowNow();
      break;
    default:
      break;
  }
}

void TrayIcon::ShowContextMenu(WPARAM wparam) {
  if (owner_ == nullptr || menu_active_) {
    return;
  }
  menu_active_ = true;

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    menu_active_ = false;
    return;
  }

  const TrayServiceStatus status = tray_service::QueryStatus();
  const bool auto_started = tray_autostart::IsEnabled();

  AppendItem(menu, MF_STRING, kMenuShowWindow, labels_.open_window);
  AppendItem(menu, MF_STRING, kMenuHideWindow, labels_.hide_window);
  AppendItem(menu, MF_SEPARATOR, 0, std::wstring());
  AppendItem(menu, MF_STRING | (auto_started ? MF_CHECKED : MF_UNCHECKED),
             kMenuAutoStart, labels_.auto_start);
  AppendItem(menu, MF_SEPARATOR, 0, std::wstring());

  const std::wstring status_text = !status.known    ? labels_.service_unknown
                                   : status.running ? labels_.service_running
                                                    : labels_.service_stopped;
  AppendItem(menu, MF_STRING | MF_DISABLED | MF_GRAYED, kMenuServiceStatus,
             status_text);
  if (status.known) {
    if (status.running) {
      AppendItem(menu, MF_STRING, kMenuServiceStop, labels_.service_stop);
      AppendItem(menu, MF_STRING, kMenuServiceRestart, labels_.service_restart);
    } else {
      AppendItem(menu, MF_STRING, kMenuServiceStart, labels_.service_start);
    }
  }

  AppendItem(menu, MF_SEPARATOR, 0, std::wstring());
  AppendItem(menu, MF_STRING, kMenuQuit, labels_.quit);
  SetMenuDefaultItem(menu, kMenuShowWindow, FALSE);

  // Version 4 packs the anchor point in wParam (signed, so secondary monitors
  // with negative coordinates work); fall back to the cursor position.
  POINT cursor{};
  int x = 0;
  int y = 0;
  if (version4_) {
    x = static_cast<int>(static_cast<short>(LOWORD(wparam)));
    y = static_cast<int>(static_cast<short>(HIWORD(wparam)));
  }
  if (x == 0 && y == 0) {
    GetCursorPos(&cursor);
    x = cursor.x;
    y = cursor.y;
  }

  // Win32 requires the owner to be foreground before a popup menu, and a
  // WM_NULL afterwards so the menu does not stay in the taskbar's state.
  SetForegroundWindow(owner_);
  const UINT command = static_cast<UINT>(TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, x, y, 0, owner_,
      nullptr));
  PostMessageW(owner_, WM_NULL, 0, 0);
  DestroyMenu(menu);
  menu_active_ = false;

  switch (command) {
    case kMenuShowWindow:
      ShowWindowNow();
      break;
    case kMenuHideWindow:
      HideWindowNow();
      break;
    case kMenuAutoStart:
      ToggleAutoStart();
      break;
    case kMenuServiceStart:
    case kMenuServiceStop:
    case kMenuServiceRestart:
      RunServiceAction(command);
      break;
    case kMenuQuit:
      if (quit_handler_) {
        quit_handler_();
      }
      break;
    default:
      break;
  }
}

void TrayIcon::ShowWindowNow() {
  if (owner_ == nullptr) {
    return;
  }
  ShowWindow(owner_, SW_RESTORE);
  SetForegroundWindow(owner_);
  BringWindowToTop(owner_);
}

void TrayIcon::HideWindowNow() {
  if (owner_ != nullptr) {
    ShowWindow(owner_, SW_HIDE);
  }
}

void TrayIcon::ToggleAutoStart() {
  const bool enable = !tray_autostart::IsEnabled();
  std::wstring error;
  if (tray_autostart::SetEnabled(enable, &error)) {
    ShowBalloon(labels_.balloon_autostart_title,
                enable ? labels_.balloon_autostart_on
                       : labels_.balloon_autostart_off);
    return;
  }
  ShowBalloon(labels_.balloon_autostart_title, labels_.balloon_failed + error);
}

// The SCM call and especially the UAC prompt must not block the message loop,
// which is also what keeps Flutter rendering while the user answers the prompt.
void TrayIcon::RunServiceAction(UINT command) {
  const HWND owner = owner_;
  const TrayLabels labels = labels_;
  std::thread([owner, labels, command]() {
    std::wstring error;
    std::wstring success;
    bool ok = false;
    switch (command) {
      case kMenuServiceStart:
        ok = tray_service::Start(&error);
        success = labels.balloon_service_started;
        break;
      case kMenuServiceStop:
        ok = tray_service::Stop(&error);
        success = labels.balloon_service_stopped;
        break;
      default:
        ok = tray_service::Restart(&error);
        success = labels.balloon_service_restarted;
        break;
    }
    PostBalloon(owner, labels.balloon_service_title,
                ok ? success : labels.balloon_failed + error);
  }).detach();
}

void TrayIcon::ShowBalloon(const std::wstring& title, const std::wstring& text) {
  PostBalloon(owner_, title, text);
}

void TrayIcon::ShowPendingBalloon() {
  std::wstring title;
  std::wstring text;
  {
    BalloonSlot& slot = Balloon();
    std::lock_guard<std::mutex> lock(slot.mutex);
    if (!slot.pending) {
      return;
    }
    title = slot.title;
    text = slot.text;
    slot.pending = false;
  }
  if (owner_ == nullptr || icon_ == nullptr) {
    return;
  }

  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = owner_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_INFO;
  data.dwInfoFlags = NIIF_INFO;
  wcsncpy_s(data.szInfoTitle, title.c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, text.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void TrayIcon::NotifyFirstClose() {
  if (first_close_notified_) {
    return;
  }
  first_close_notified_ = true;
  ShowBalloon(labels_.tooltip, labels_.balloon_minimized_body);
}

void TrayIcon::SetQuitHandler(std::function<void()> handler) {
  quit_handler_ = std::move(handler);
}
