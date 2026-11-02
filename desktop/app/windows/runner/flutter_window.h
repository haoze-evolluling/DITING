#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "tray/tray_channel.h"
#include "tray/tray_icon.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Keep the window hidden after the first frame (`--minimized`), so a
  // sign-in start from the Run key lands in the notification area.
  void SetStartHidden(bool hidden) { start_hidden_ = hidden; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Notification-area icon and the channel that feeds it localized labels.
  // Both are null when the icon could not be registered, in which case closing
  // the window quits as before instead of hiding an unreachable window.
  std::unique_ptr<TrayIcon> tray_;
  std::unique_ptr<TrayChannel> tray_channel_;

  bool start_hidden_ = false;
  // Set by the tray's "quit" item: the next WM_CLOSE closes for real.
  bool quit_requested_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
