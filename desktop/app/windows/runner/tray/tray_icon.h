#ifndef RUNNER_TRAY_TRAY_ICON_H_
#define RUNNER_TRAY_TRAY_ICON_H_

#include <windows.h>

#include <functional>
#include <string>

#include "tray_labels.h"

class TrayIcon {
 public:
  TrayIcon();
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  bool Create(HWND owner);

  void Destroy();

  void SetLabels(const TrayLabels& labels);

  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  void ShowBalloon(const std::wstring& title, const std::wstring& text);

  void NotifyFirstClose();

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

#endif
