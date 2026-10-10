package windows

import (
	"context"
	"fmt"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	procControlService       = modAdvapi32.NewProc("ControlService")
	procChangeServiceConfigW = modAdvapi32.NewProc("ChangeServiceConfigW")
)

const (
	serviceControlStop  = 0x00000001
	serviceStopped      = 0x00000001
	serviceStop         = 0x0020
	serviceChangeConfig = 0x0002
	serviceDisabled     = 0x00000004
	serviceNoChange     = 0xFFFFFFFF
)

// StopAndDisableSharedAccessNative 调用 Win32 SCM 原生 API 停止并禁用 Windows SharedAccess (ICS) 服务
func StopAndDisableSharedAccessNative() error {
	scm, _, err := procOpenSCManagerW.Call(0, 0, uintptr(windows.SC_MANAGER_CONNECT))
	if scm == 0 {
		return fmt.Errorf("打开服务控制管理器 (SCM) 失败: %w", err)
	}
	defer procCloseServiceHandle.Call(scm)

	svcNamePtr, _ := windows.UTF16PtrFromString("SharedAccess")
	desiredAccess := uintptr(serviceStop | serviceChangeConfig | serviceQueryStatus)
	svc, _, err := procOpenServiceW.Call(scm, uintptr(unsafe.Pointer(svcNamePtr)), desiredAccess)
	if svc == 0 {
		return fmt.Errorf("打开 SharedAccess 服务句柄失败: %w", err)
	}
	defer procCloseServiceHandle.Call(svc)

	// 1. 将服务启动类型修改为禁用 (Disabled)，防止随系统启动或网络事件自动复活
	retConfig, _, errConfig := procChangeServiceConfigW.Call(
		svc,
		uintptr(serviceNoChange), // dwServiceType (保持不变)
		uintptr(serviceDisabled), // dwStartType (禁用)
		uintptr(serviceNoChange), // dwErrorControl (保持不变)
		0, 0, 0, 0, 0, 0, 0,
	)
	if retConfig == 0 {
		// 记录但继续尝试停止
		_ = errConfig
	}

	// 2. 查询当前运行状态
	var ssp serviceStatusProcess
	var bytesNeeded uint32
	retQuery, _, errQuery := procQueryServiceStatusEx.Call(
		svc,
		uintptr(scStatusProcessInfo),
		uintptr(unsafe.Pointer(&ssp)),
		uintptr(unsafe.Sizeof(ssp)),
		uintptr(unsafe.Pointer(&bytesNeeded)),
	)
	if retQuery == 0 {
		return fmt.Errorf("查询 SharedAccess 服务状态失败: %w", errQuery)
	}

	if ssp.CurrentState == serviceStopped {
		return nil
	}

	// 3. 发送停止控制信号 (SERVICE_CONTROL_STOP)
	var stopStatus serviceStatusProcess
	retStop, _, errStop := procControlService.Call(
		svc,
		uintptr(serviceControlStop),
		uintptr(unsafe.Pointer(&stopStatus)),
	)
	if retStop == 0 {
		return fmt.Errorf("向 SharedAccess 发送停止信号失败: %w", errStop)
	}

	// 4. 等待服务进入 STOPPED 状态（最多等待 5 秒）
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		time.Sleep(200 * time.Millisecond)
		var pollSSP serviceStatusProcess
		r, _, _ := procQueryServiceStatusEx.Call(
			svc,
			uintptr(scStatusProcessInfo),
			uintptr(unsafe.Pointer(&pollSSP)),
			uintptr(unsafe.Sizeof(pollSSP)),
			uintptr(unsafe.Pointer(&bytesNeeded)),
		)
		if r != 0 && pollSSP.CurrentState == serviceStopped {
			return nil
		}
	}

	return fmt.Errorf("停止 SharedAccess 服务超时 (当前状态码: %d)", stopStatus.CurrentState)
}

// AutofixPort53ForAddresses 执行 53 端口冲突自动修复并重新探测指定目标地址的可用性
func (c *WindowsPortChecker) AutofixPort53ForAddresses(ctx context.Context, udpAddrs, tcpAddrs []string) (*PortCheckResult, error) {
	if err := StopAndDisableSharedAccessNative(); err != nil {
		return nil, err
	}

	// 等待操作系统 Winsock 释放端口占用
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(300 * time.Millisecond):
	}

	return c.CheckPort53ForAddresses(ctx, udpAddrs, tcpAddrs)
}
