#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "tray/tray_channel.h"
#include "tray/tray_icon.h"
#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  void SetStartHidden(bool hidden) { start_hidden_ = hidden; }

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  flutter::DartProject project_;

  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<TrayIcon> tray_;
  std::unique_ptr<TrayChannel> tray_channel_;

  bool start_hidden_ = false;
  bool quit_requested_ = false;
};

#endif
