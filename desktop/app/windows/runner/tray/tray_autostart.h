#ifndef RUNNER_TRAY_TRAY_AUTOSTART_H_
#define RUNNER_TRAY_TRAY_AUTOSTART_H_

#include <string>

namespace tray_autostart {

bool IsEnabled();

bool SetEnabled(bool enable, std::wstring* error);

}

#endif
