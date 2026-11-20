#ifndef RUNNER_TRAY_TRAY_LABELS_H_
#define RUNNER_TRAY_TRAY_LABELS_H_

#include <string>

struct TrayLabels {
  std::wstring tooltip = L"谛听 (DITING) DNS 控制台";

  std::wstring open_window = L"打开主界面";
  std::wstring hide_window = L"隐藏主界面";
  std::wstring auto_start = L"开机自启动";

  std::wstring service_running = L"核心服务：运行中";
  std::wstring service_stopped = L"核心服务：已停止";
  std::wstring service_unknown = L"核心服务：状态未知";
  std::wstring service_start = L"启动核心服务";
  std::wstring service_stop = L"停止核心服务";
  std::wstring service_restart = L"重启核心服务";

  std::wstring quit = L"退出程序";

  std::wstring balloon_service_title = L"核心服务";
  std::wstring balloon_service_started = L"核心服务已启动";
  std::wstring balloon_service_stopped = L"核心服务已停止";
  std::wstring balloon_service_restarted = L"核心服务已重启";

  std::wstring balloon_autostart_title = L"开机自启动";
  std::wstring balloon_autostart_on = L"已开启开机自启动";
  std::wstring balloon_autostart_off = L"已关闭开机自启动";

  std::wstring balloon_failed = L"操作失败：";
  std::wstring balloon_minimized_body =
      L"谛听已最小化到系统托盘，并在后台继续运行。\n"
      L"点击托盘图标可重新打开主界面。";
};

#endif
