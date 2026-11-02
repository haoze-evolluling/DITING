#ifndef RUNNER_TRAY_TRAY_AUTOSTART_H_
#define RUNNER_TRAY_TRAY_AUTOSTART_H_

#include <string>

// Current-user sign-in launch, ported from the old Wails desktop
// (`WindowsAutoStartManager`): one value under the per-user Run key, pointing at
// the GUI with `--minimized` so a sign-in launch lands in the notification area
// instead of a window on top of the desktop.
namespace tray_autostart {

// True when this user's Run key already carries the DITING entry.
bool IsEnabled();

// Writes or removes the entry. |error| receives the failure reason.
bool SetEnabled(bool enable, std::wstring* error);

}  // namespace tray_autostart

#endif  // RUNNER_TRAY_TRAY_AUTOSTART_H_
