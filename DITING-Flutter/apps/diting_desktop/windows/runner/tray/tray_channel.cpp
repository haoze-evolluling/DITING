#include "tray_channel.h"

#include <string>
#include <utility>

namespace {

// Method channel strings arrive UTF-8 encoded; the Win32 menu/tooltip APIs
// take UTF-16.
std::wstring Utf16FromUtf8(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

// Copies |key| into |out| when the map carries it, leaving the zh default in
// place otherwise - a partially translated locale must not blank the menu.
void ReadLabel(const flutter::EncodableMap& map, const char* key,
               std::wstring* out) {
  const auto entry = map.find(flutter::EncodableValue(std::string(key)));
  if (entry == map.end()) {
    return;
  }
  const auto* value = std::get_if<std::string>(&entry->second);
  if (value == nullptr || value->empty()) {
    return;
  }
  *out = Utf16FromUtf8(*value);
}

void ApplyLabels(const flutter::EncodableMap& map, TrayLabels* labels) {
  ReadLabel(map, "tooltip", &labels->tooltip);
  ReadLabel(map, "open_window", &labels->open_window);
  ReadLabel(map, "hide_window", &labels->hide_window);
  ReadLabel(map, "auto_start", &labels->auto_start);
  ReadLabel(map, "service_running", &labels->service_running);
  ReadLabel(map, "service_stopped", &labels->service_stopped);
  ReadLabel(map, "service_unknown", &labels->service_unknown);
  ReadLabel(map, "service_start", &labels->service_start);
  ReadLabel(map, "service_stop", &labels->service_stop);
  ReadLabel(map, "service_restart", &labels->service_restart);
  ReadLabel(map, "quit", &labels->quit);
  ReadLabel(map, "balloon_service_title", &labels->balloon_service_title);
  ReadLabel(map, "balloon_service_started", &labels->balloon_service_started);
  ReadLabel(map, "balloon_service_stopped", &labels->balloon_service_stopped);
  ReadLabel(map, "balloon_service_restarted", &labels->balloon_service_restarted);
  ReadLabel(map, "balloon_autostart_title", &labels->balloon_autostart_title);
  ReadLabel(map, "balloon_autostart_on", &labels->balloon_autostart_on);
  ReadLabel(map, "balloon_autostart_off", &labels->balloon_autostart_off);
  ReadLabel(map, "balloon_failed", &labels->balloon_failed);
  ReadLabel(map, "balloon_minimized_body", &labels->balloon_minimized_body);
}

}  // namespace

TrayChannel::TrayChannel(flutter::BinaryMessenger* messenger, TrayIcon* tray)
    : tray_(tray),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "diting/tray",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) { HandleMethodCall(call, std::move(result)); });
}

TrayChannel::~TrayChannel() {
  // Detach before |tray_| goes away: the engine may still dispatch a queued
  // call during shutdown.
  channel_->SetMethodCallHandler(nullptr);
}

void TrayChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != "configure") {
    result->NotImplemented();
    return;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(call.arguments());
  if (map == nullptr) {
    result->Error("bad-arguments", "configure expects a label map");
    return;
  }

  TrayLabels labels;
  ApplyLabels(*map, &labels);
  if (tray_ != nullptr) {
    tray_->SetLabels(labels);
  }
  result->Success();
}
