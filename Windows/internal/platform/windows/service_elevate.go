package windows

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
)

func runElevatedNative(ctx context.Context, exePath string, args string) error {
	if ctx != nil && ctx.Err() != nil {
		return ctx.Err()
	}

	verbPtr, _ := windows.UTF16PtrFromString("runas")
	filePtr, _ := windows.UTF16PtrFromString(exePath)
	var argsPtr *uint16
	if args != "" {
		argsPtr, _ = windows.UTF16PtrFromString(args)
	}

	var sei shellExecuteInfo
	sei.cbSize = uint32(unsafe.Sizeof(sei))
	sei.fMask = seeMaskNoCloseProcess
	sei.lpVerb = verbPtr
	sei.lpFile = filePtr
	sei.lpParameters = argsPtr
	sei.nShow = swHide

	r1, _, err := procShellExecuteExW.Call(uintptr(unsafe.Pointer(&sei)))
	if r1 == 0 {
		if errors.Is(err, windows.ERROR_CANCELLED) || strings.Contains(err.Error(), "1223") {
			return ErrUACCancelled
		}
		return fmt.Errorf("特权操作执行失败: %w", err)
	}

	if sei.hProcess != 0 {
		defer windows.CloseHandle(sei.hProcess)
		for {
			event, errWait := windows.WaitForSingleObject(sei.hProcess, 100)
			if errWait != nil {
				return fmt.Errorf("等待提权进程退出失败: %w", errWait)
			}
			if event == windows.WAIT_OBJECT_0 {
				break
			}
			if ctx != nil && ctx.Err() != nil {
				_ = windows.TerminateProcess(sei.hProcess, 1)
				return ctx.Err()
			}
		}

		var exitCode uint32
		if errExit := windows.GetExitCodeProcess(sei.hProcess, &exitCode); errExit == nil && exitCode != 0 {
			return fmt.Errorf("特权操作执行失败 (退出代码: %d)", exitCode)
		}
	}
	return nil
}
