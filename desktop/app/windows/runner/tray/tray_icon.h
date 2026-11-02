#ifndef RUNNER_TRAY_TRAY_ICON_H_
#define RUNNER_TRAY_TRAY_ICON_H_

#include <windows.h>

#include <functional>
#include <string>

#include "tray_labels.h"

// The window's notification-area icon: Shell_NotifyIcon registration, its
// context menu and its balloons.
//
// Ported from the old Wails desktop tray (`Desktop/internal/platform/windows/
// tray*.go`), keeping the design decisions that made it work there:
//
//   * Showing the window is an idempotent "restore + foreground" action, so
//     every click-like event (NIN_SELECT, keyboard select, double click,
//     balloon click) maps to it without single/double-click detection or time
//     debouncing - there is no double dispatch to suppress.
//   * Tray messages arrive on the window's own WndProc, i.e. on the GUI thread,
//     so ShowWindow/SetForegroundWindow run while the window still owns the
//     foreground token instead of being rejected as a background activation.
//   * Service start/stop/restart and the UAC prompt block for seconds, so they
//     run on a worker thread and report back through a balloon.
class TrayIcon {
 public:
  TrayIcon();
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  // Registers the icon on |owner| and wires the TaskbarCreated message, so the
  // icon reappears after an Explorer restart.
  bool Create(HWND owner);

  // Removes the icon and releases the extracted icon handle. Safe to repeat.
  void Destroy();

  // Replaces the localized strings; the tooltip is refreshed right away.
  void SetLabels(const TrayLabels& labels);

  // Handles tray messages on the window procedure. Returns true when the
  // message belonged to the tray and must not reach Flutter nor DefWindowProc.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  // Queues a balloon; Shell_NotifyIcon must run on the icon's own thread, so
  // this only stores the text and posts an internal message.
  void ShowBalloon(const std::wstring& title, const std::wstring& text);

  // First close of the window: tell the user it keeps running in the tray.
  void NotifyFirstClose();

  // Invoked on the GUI thread when the user picks "quit" in the menu.
  void SetQuitHandler(std::function<void()> handler);

 private:
  void OnCallback(WPARAM wparam, LPARAM lparam);
  void ShowContextMenu(WPARAM wparam);
  void ShowPendingBalloon();
  void ShowWindowNow();
  void HideWindowNow();
  void ToggleAutoStart();
  void RunServiceAction(UINT command);
  bool AddIcon();
  void SetVersion();

  HWND owner_ = nullptr;
  HICON icon_ = nullptr;
  bool owns_icon_ = false;
  UINT taskbar_created_message_ = 0;
  bool version4_ = false;
  bool menu_active_ = false;
  bool first_close_notified_ = false;
  TrayLabels labels_;
  std::function<void()> quit_handler_;
};

#endif  // RUNNER_TRAY_TRAY_ICON_H_
