#ifndef RUNNER_TRAY_TRAY_CHANNEL_H_
#define RUNNER_TRAY_TRAY_CHANNEL_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "tray_icon.h"

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

#endif
