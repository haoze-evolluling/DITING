#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The tray exists from the first frame on, so a `--minimized` start is
  // reachable and closing the window behaves like the old Wails desktop
  // (hide to tray) from the very beginning.
  tray_ = std::make_unique<TrayIcon>();
  tray_->SetQuitHandler([this]() {
    quit_requested_ = true;
    PostMessage(GetHandle(), WM_CLOSE, 0, 0);
  });
  if (tray_->Create(GetHandle())) {
    tray_channel_ = std::make_unique<TrayChannel>(
        flutter_controller_->engine()->messenger(), tray_.get());
  } else {
    tray_.reset();
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  tray_channel_.reset();
  if (tray_) {
    tray_->Destroy();
    tray_.reset();
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Closing the window keeps DITING running in the notification area, exactly
  // like the old Wails window: it hides instead of destroying the window. The
  // tray's "quit" item sets |quit_requested_| and posts another WM_CLOSE that
  // falls through to the default handling below.
  if (message == WM_CLOSE && tray_ != nullptr && !quit_requested_) {
    tray_->NotifyFirstClose();
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

  if (tray_ != nullptr && tray_->HandleMessage(message, wparam, lparam)) {
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
