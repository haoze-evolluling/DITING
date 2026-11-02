#ifndef RUNNER_TRAY_TRAY_CHANNEL_H_
#define RUNNER_TRAY_TRAY_CHANNEL_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "tray_icon.h"

// The `diting/tray` method channel.
//
// Only localization crosses the channel: Dart pushes the strings of the active
// locale via `configure` and native code owns everything else (menu structure,
// SCM calls, balloons). That keeps the tray functional for a `--minimized`
// start even before Flutter has produced its first frame.
class TrayChannel {
 public:
  TrayChannel(flutter::BinaryMessenger* messenger, TrayIcon* tray);
  ~TrayChannel();

  TrayChannel(const TrayChannel&) = delete;
  TrayChannel& operator=(const TrayChannel&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  TrayIcon* tray_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_TRAY_TRAY_CHANNEL_H_
