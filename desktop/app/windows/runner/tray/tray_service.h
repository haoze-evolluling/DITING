#ifndef RUNNER_TRAY_TRAY_SERVICE_H_
#define RUNNER_TRAY_TRAY_SERVICE_H_

#include <string>

constexpr wchar_t kTrayServiceName[] = L"DitingDNSService";
constexpr wchar_t kTrayServiceExecutable[] = L"diting-service.exe";

struct TrayServiceStatus {
  bool known = false;
  bool installed = false;
  bool running = false;
};

namespace tray_service {

TrayServiceStatus QueryStatus();

std::wstring LocateExecutable();

bool Start(std::wstring* error);
bool Stop(std::wstring* error);
bool Restart(std::wstring* error);

}

#endif
