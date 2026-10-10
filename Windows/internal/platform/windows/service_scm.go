package windows

import (
	"errors"

	"golang.org/x/sys/windows"
)

type scmQuerier func(serviceName string) (installed bool, running bool, state string, err error)

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
