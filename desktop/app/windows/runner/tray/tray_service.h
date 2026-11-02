#ifndef RUNNER_TRAY_TRAY_SERVICE_H_
#define RUNNER_TRAY_TRAY_SERVICE_H_

#include <string>

// Windows service name of the privileged DNS core (`desktop/service/internal/
// platform/windows/service_privilege.go`) and the executable that owns it.
constexpr wchar_t kTrayServiceName[] = L"DitingDNSService";
constexpr wchar_t kTrayServiceExecutable[] = L"diting-service.exe";

// What the tray menu needs to decide which service actions to offer.
struct TrayServiceStatus {
  // False when the SCM itself could not be queried; the menu then says so
  // instead of pretending the service is stopped.
  bool known = false;
  bool installed = false;
  bool running = false;
};

namespace tray_service {

// Queries the SCM. Cheap enough (a few milliseconds) to run whenever the
// context menu opens, so the menu never shows a stale state.
TrayServiceStatus QueryStatus();

// Locates diting-service.exe the same way the old Wails desktop did: the SCM
// ImagePath first, then next to the GUI, then the repository build layout, and
// finally PATH. Returns an empty string when it cannot be found.
std::wstring LocateExecutable();

// Service lifecycle, mirroring the old Go ServiceManager: try the SCM directly
// and fall back to `diting-service.exe -service <verb>` through a UAC prompt.
// These block for seconds (elevation prompt included), so callers must never
// run them on the window thread. |error| receives a localized failure reason.
bool Start(std::wstring* error);
bool Stop(std::wstring* error);
bool Restart(std::wstring* error);

}  // namespace tray_service

#endif  // RUNNER_TRAY_TRAY_SERVICE_H_
