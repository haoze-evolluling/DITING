//go:build windows

package windows

import (
	"errors"
	"unsafe"

	"golang.org/x/sys/windows"
)

type scmQuerier func(serviceName string) (installed bool, running bool, state string, err error)

// queryStartType 读取服务的启动类型（SERVICE_AUTO_START 等）。
//
// 用于判定服务是否已由 SCM 托管为开机自启：该配置独立于用户图形自启项，
// 是判断"未配置开机启动"是否成立的关键依据。
func queryStartType(serviceName string) (uint32, error) {
	scm, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return 0, err
	}
	defer windows.CloseServiceHandle(scm)

	namePtr, err := windows.UTF16PtrFromString(serviceName)
	if err != nil {
		return 0, err
	}
	svc, err := windows.OpenService(scm, namePtr, windows.SERVICE_QUERY_CONFIG)
	if err != nil {
		return 0, err
	}
	defer windows.CloseServiceHandle(svc)

	var needed uint32
	err = windows.QueryServiceConfig(svc, nil, 0, &needed)
	if err != nil && !errors.Is(err, windows.ERROR_INSUFFICIENT_BUFFER) {
		return 0, err
	}
	if needed == 0 {
		return 0, errors.New("服务配置查询未返回所需缓冲区大小")
	}

	buf := make([]byte, needed)
	cfg := (*windows.QUERY_SERVICE_CONFIG)(unsafe.Pointer(&buf[0]))
	if err := windows.QueryServiceConfig(svc, cfg, needed, &needed); err != nil {
		return 0, err
	}
	return cfg.StartType, nil
}

func defaultSCMQuery(serviceName string) (bool, bool, string, error) {
	scm, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return false, false, "", err
	}
	defer windows.CloseServiceHandle(scm)

	namePtr, _ := windows.UTF16PtrFromString(serviceName)
	svc, err := windows.OpenService(scm, namePtr, windows.SERVICE_QUERY_STATUS)
	if err != nil {
		if errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST) {
			return false, false, "not_installed", nil
		}
		return false, false, "", err
	}
	defer windows.CloseServiceHandle(svc)

	var svcStatus windows.SERVICE_STATUS
	if err := windows.QueryServiceStatus(svc, &svcStatus); err != nil {
		return false, false, "", err
	}

	switch svcStatus.CurrentState {
	case windows.SERVICE_RUNNING:
		return true, true, "running", nil
	case windows.SERVICE_STOPPED:
		return true, false, "stopped", nil
	case windows.SERVICE_START_PENDING:
		return true, false, "start_pending", nil
	case windows.SERVICE_STOP_PENDING:
		return true, false, "stop_pending", nil
	default:
		return true, false, "stopped", nil
	}
}
