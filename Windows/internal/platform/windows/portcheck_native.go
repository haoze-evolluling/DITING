package windows

import (
	"encoding/binary"
	"fmt"
	"net"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	modIphlpapi             = windows.NewLazySystemDLL("iphlpapi.dll")
	procGetExtendedTcpTable = modIphlpapi.NewProc("GetExtendedTcpTable")
	procGetExtendedUdpTable = modIphlpapi.NewProc("GetExtendedUdpTable")

	modAdvapi32              = windows.NewLazySystemDLL("advapi32.dll")
	procOpenSCManagerW       = modAdvapi32.NewProc("OpenSCManagerW")
	procOpenServiceW         = modAdvapi32.NewProc("OpenServiceW")
	procQueryServiceStatusEx = modAdvapi32.NewProc("QueryServiceStatusEx")
	procCloseServiceHandle   = modAdvapi32.NewProc("CloseServiceHandle")
)

const (
	afInet  = 2
	afInet6 = 23

	tcpTableOwnerPidAll = 5
	udpTableOwnerPid    = 1

	mibTcpStateListen = 2

	scManagerConnect    = 0x0001
	serviceQueryStatus  = 0x0004
	scStatusProcessInfo = 0
	serviceRunning      = 0x00000004
)

type serviceStatusProcess struct {
	ServiceType             uint32
	CurrentState            uint32
	ControlsAccepted        uint32
	Win32ExitCode           uint32
	ServiceSpecificExitCode uint32
	CheckPoint              uint32
	WaitHint                uint32
	ProcessId               uint32
	ServiceFlags            uint32
}

type nativePortListener struct {
	Protocol     string
	LocalAddress string
	PID          int
	ProcessName  string
}

// checkPort53Native 纯原生探测 53 端口冲突并识别 SharedAccess (ICS) 等服务
func checkPort53Native(available bool, selfPID int) ([]PortConflict, bool, string, error) {
	listeners, err := getPort53ListenersNative()
	if err != nil {
		return nil, false, "", err
	}
	hasICS, icsPID, errICS := checkICSStatusNative()
	if errICS != nil {
		hasICS = false
	}
	confs, ics, diag := formatPortConflicts(listeners, hasICS, icsPID, available, selfPID)
	return confs, ics, diag, nil
}

// formatPortConflicts 根据端点与 ICS 状态汇总格式化诊断报告
func formatPortConflicts(rawList []nativePortListener, hasICS bool, icsPID int, available bool, selfPID int) ([]PortConflict, bool, string) {
	conflicts := make([]PortConflict, 0, len(rawList))
	var diagLines []string
	hasSelfListener := false

	for _, item := range rawList {
		isSelf := (selfPID > 0 && item.PID == selfPID)
		if isSelf {
			hasSelfListener = true
		}
		isICS := false
		if !isSelf && hasICS {
			if icsPID > 0 {
				isICS = (item.PID == icsPID)
			} else {
				isICS = strings.Contains(strings.ToLower(item.ProcessName), "svchost")
			}
		}
		diagnosis := ""
		if isSelf {
			diagnosis = fmt.Sprintf("进程 PID %d (%s) 为谛听 (DITING) 服务自身正在监听 %s (%s)。", item.PID, item.ProcessName, item.LocalAddress, item.Protocol)
		} else if isICS {
			diagnosis = fmt.Sprintf("检测到 Windows 网络连接共享服务 (SharedAccess / ICS) 正在运行 (PID: %d)。ICS 会在 0.0.0.0:53 上占用 UDP，阻止本地 DNS 代理绑定。排查建议：按 Win+R 打开 services.msc 停止并禁用 'Internet Connection Sharing (ICS)' 服务，或以管理员身份运行 'sc stop SharedAccess'。", item.PID)
			diagLines = append(diagLines, diagnosis)
		} else {
			diagnosis = fmt.Sprintf("检测到外部进程 '%s' (PID: %d) 正在监听 %s (%s)。排查建议：请在任务管理器中结束该进程，或修改该软件的监听端口后重试。", item.ProcessName, item.PID, item.LocalAddress, item.Protocol)
			diagLines = append(diagLines, diagnosis)
		}

		conflicts = append(conflicts, PortConflict{
			Port:         53,
			Protocol:     item.Protocol,
			LocalAddress: item.LocalAddress,
			PID:          item.PID,
			ProcessName:  item.ProcessName,
			ServiceName:  ternary(isICS, "SharedAccess", ""),
			IsICS:        isICS,
			IsSelf:       isSelf,
			Diagnosis:    diagnosis,
		})
	}

	if len(diagLines) == 0 {
		if hasSelfListener {
			return conflicts, hasICS, "127.0.0.1:53 当前由谛听 (DITING) 核心服务监听中，无外部端口冲突。"
		}
		if available {
			return conflicts, hasICS, "53 端口空闲且可用，无端口冲突。"
		}
		return conflicts, hasICS, "未能直接绑定 127.0.0.1:53，但未探测到明确的系统监听进程（可能需要管理员权限）。排查建议：请检查是否有其他 DNS 或代理软件占用，或尝试以管理员身份运行本服务。"
	}

	return conflicts, hasICS, strings.Join(diagLines, "\n")
}

// getProcessNameMapNative 返回当前系统 PID -> 进程名称的映射表
func getProcessNameMapNative() map[int]string {
	res := make(map[int]string)
	snapshot, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return res
	}
	defer windows.CloseHandle(snapshot)

	var entry windows.ProcessEntry32
	entry.Size = uint32(unsafe.Sizeof(entry))
	if err := windows.Process32First(snapshot, &entry); err != nil {
		return res
	}

	for {
		name := windows.UTF16ToString(entry.ExeFile[:])
		res[int(entry.ProcessID)] = name
		if err := windows.Process32Next(snapshot, &entry); err != nil {
			break
		}
	}
	return res
}

// checkICSStatusNative 检查 Windows ICS (SharedAccess) 服务的运行状态与 PID
func checkICSStatusNative() (bool, int, error) {
	scm, _, err := procOpenSCManagerW.Call(0, 0, uintptr(scManagerConnect))
	if scm == 0 {
		return false, 0, err
	}
	defer procCloseServiceHandle.Call(scm)

	svcNamePtr, _ := windows.UTF16PtrFromString("SharedAccess")
	svc, _, err := procOpenServiceW.Call(scm, uintptr(unsafe.Pointer(svcNamePtr)), uintptr(serviceQueryStatus))
	if svc == 0 {
		// 服务不存在或无法查询状态
		return false, 0, nil
	}
	defer procCloseServiceHandle.Call(svc)

	var ssp serviceStatusProcess
	var bytesNeeded uint32
	ret, _, err := procQueryServiceStatusEx.Call(
		svc,
		uintptr(scStatusProcessInfo),
		uintptr(unsafe.Pointer(&ssp)),
		uintptr(unsafe.Sizeof(ssp)),
		uintptr(unsafe.Pointer(&bytesNeeded)),
	)
	if ret == 0 {
		return false, 0, err
	}

	if ssp.CurrentState == serviceRunning {
		return true, int(ssp.ProcessId), nil
	}
	return false, 0, nil
}

// getPort53ListenersNative 枚举正在监听 53 端口的所有 IPv4/IPv6 TCP 与 UDP 端点
func getPort53ListenersNative() ([]nativePortListener, error) {
	procMap := getProcessNameMapNative()
	var listeners []nativePortListener

	// 1. IPv4 TCP
	tcp4, err := getTCP4Listeners(53)
	if err == nil {
		for _, item := range tcp4 {
			listeners = append(listeners, nativePortListener{
				Protocol:     "TCP",
				LocalAddress: item.addr,
				PID:          item.pid,
				ProcessName:  procMap[item.pid],
			})
		}
	}

	// 2. IPv6 TCP
	tcp6, err := getTCP6Listeners(53)
	if err == nil {
		for _, item := range tcp6 {
			listeners = append(listeners, nativePortListener{
				Protocol:     "TCP",
				LocalAddress: item.addr,
				PID:          item.pid,
				ProcessName:  procMap[item.pid],
			})
		}
	}

	// 3. IPv4 UDP
	udp4, err := getUDP4Listeners(53)
	if err == nil {
		for _, item := range udp4 {
			listeners = append(listeners, nativePortListener{
				Protocol:     "UDP",
				LocalAddress: item.addr,
				PID:          item.pid,
				ProcessName:  procMap[item.pid],
			})
		}
	}

	// 4. IPv6 UDP
	udp6, err := getUDP6Listeners(53)
	if err == nil {
		for _, item := range udp6 {
			listeners = append(listeners, nativePortListener{
				Protocol:     "UDP",
				LocalAddress: item.addr,
				PID:          item.pid,
				ProcessName:  procMap[item.pid],
			})
		}
	}

	return listeners, nil
}

type rawListener struct {
	addr string
	pid  int
}

func parsePort(dwPort uint32) uint16 {
	return binary.BigEndian.Uint16([]byte{byte(dwPort), byte(dwPort >> 8)})
}

func getTCP4Listeners(targetPort uint16) ([]rawListener, error) {
	var size uint32
	var buf []byte
	var ret uintptr
	for i := 0; i < 5; i++ {
		var p unsafe.Pointer
		if len(buf) > 0 {
			p = unsafe.Pointer(&buf[0])
		}
		r, _, _ := procGetExtendedTcpTable.Call(uintptr(p), uintptr(unsafe.Pointer(&size)), 0, uintptr(afInet), uintptr(tcpTableOwnerPidAll), 0)
		ret = r
		if ret == 0 {
			break
		}
		if ret != uintptr(windows.ERROR_INSUFFICIENT_BUFFER) {
			return nil, syscall.Errno(ret)
		}
		buf = make([]byte, size)
	}
	if ret != 0 || len(buf) < 4 {
		return nil, nil
	}

	numEntries := binary.LittleEndian.Uint32(buf[0:4])
	offset := 4
	rowSize := 24
	var res []rawListener

	for i := uint32(0); i < numEntries; i++ {
		if offset+rowSize > len(buf) {
			break
		}
		row := buf[offset : offset+rowSize]
		state := binary.LittleEndian.Uint32(row[0:4])
		localAddrRaw := binary.LittleEndian.Uint32(row[4:8])
		localPortRaw := binary.LittleEndian.Uint32(row[8:12])
		owningPid := binary.LittleEndian.Uint32(row[20:24])
		offset += rowSize

		port := parsePort(localPortRaw)
		if port == targetPort && state == mibTcpStateListen {
			ip := net.IPv4(byte(localAddrRaw), byte(localAddrRaw>>8), byte(localAddrRaw>>16), byte(localAddrRaw>>24))
			res = append(res, rawListener{
				addr: fmt.Sprintf("%s:%d", ip.String(), port),
				pid:  int(owningPid),
			})
		}
	}
	return res, nil
}

func getTCP6Listeners(targetPort uint16) ([]rawListener, error) {
	var size uint32
	var buf []byte
	var ret uintptr
	for i := 0; i < 5; i++ {
		var p unsafe.Pointer
		if len(buf) > 0 {
			p = unsafe.Pointer(&buf[0])
		}
		r, _, _ := procGetExtendedTcpTable.Call(uintptr(p), uintptr(unsafe.Pointer(&size)), 0, uintptr(afInet6), uintptr(tcpTableOwnerPidAll), 0)
		ret = r
		if ret == 0 {
			break
		}
		if ret != uintptr(windows.ERROR_INSUFFICIENT_BUFFER) {
			return nil, syscall.Errno(ret)
		}
		buf = make([]byte, size)
	}
	if ret != 0 || len(buf) < 4 {
		return nil, nil
	}

	numEntries := binary.LittleEndian.Uint32(buf[0:4])
	offset := 4
	rowSize := 56
	var res []rawListener

	for i := uint32(0); i < numEntries; i++ {
		if offset+rowSize > len(buf) {
			break
		}
		row := buf[offset : offset+rowSize]
		var ipBytes [16]byte
		copy(ipBytes[:], row[0:16])
		localPortRaw := binary.LittleEndian.Uint32(row[20:24])
		state := binary.LittleEndian.Uint32(row[48:52])
		owningPid := binary.LittleEndian.Uint32(row[52:56])
		offset += rowSize

		port := parsePort(localPortRaw)
		if port == targetPort && state == mibTcpStateListen {
			ip := net.IP(ipBytes[:])
			res = append(res, rawListener{
				addr: fmt.Sprintf("%s:%d", ip.String(), port),
				pid:  int(owningPid),
			})
		}
	}
	return res, nil
}

func getUDP4Listeners(targetPort uint16) ([]rawListener, error) {
	var size uint32
	var buf []byte
	var ret uintptr
	for i := 0; i < 5; i++ {
		var p unsafe.Pointer
		if len(buf) > 0 {
			p = unsafe.Pointer(&buf[0])
		}
		r, _, _ := procGetExtendedUdpTable.Call(uintptr(p), uintptr(unsafe.Pointer(&size)), 0, uintptr(afInet), uintptr(udpTableOwnerPid), 0)
		ret = r
		if ret == 0 {
			break
		}
		if ret != uintptr(windows.ERROR_INSUFFICIENT_BUFFER) {
			return nil, syscall.Errno(ret)
		}
		buf = make([]byte, size)
	}
	if ret != 0 || len(buf) < 4 {
		return nil, nil
	}

	numEntries := binary.LittleEndian.Uint32(buf[0:4])
	offset := 4
	rowSize := 12
	var res []rawListener

	for i := uint32(0); i < numEntries; i++ {
		if offset+rowSize > len(buf) {
			break
		}
		row := buf[offset : offset+rowSize]
		localAddrRaw := binary.LittleEndian.Uint32(row[0:4])
		localPortRaw := binary.LittleEndian.Uint32(row[4:8])
		owningPid := binary.LittleEndian.Uint32(row[8:12])
		offset += rowSize

		port := parsePort(localPortRaw)
		if port == targetPort {
			ip := net.IPv4(byte(localAddrRaw), byte(localAddrRaw>>8), byte(localAddrRaw>>16), byte(localAddrRaw>>24))
			res = append(res, rawListener{
				addr: fmt.Sprintf("%s:%d", ip.String(), port),
				pid:  int(owningPid),
			})
		}
	}
	return res, nil
}

func getUDP6Listeners(targetPort uint16) ([]rawListener, error) {
	var size uint32
	var buf []byte
	var ret uintptr
	for i := 0; i < 5; i++ {
		var p unsafe.Pointer
		if len(buf) > 0 {
			p = unsafe.Pointer(&buf[0])
		}
		r, _, _ := procGetExtendedUdpTable.Call(uintptr(p), uintptr(unsafe.Pointer(&size)), 0, uintptr(afInet6), uintptr(udpTableOwnerPid), 0)
		ret = r
		if ret == 0 {
			break
		}
		if ret != uintptr(windows.ERROR_INSUFFICIENT_BUFFER) {
			return nil, syscall.Errno(ret)
		}
		buf = make([]byte, size)
	}
	if ret != 0 || len(buf) < 4 {
		return nil, nil
	}

	numEntries := binary.LittleEndian.Uint32(buf[0:4])
	offset := 4
	rowSize := 28
	var res []rawListener

	for i := uint32(0); i < numEntries; i++ {
		if offset+rowSize > len(buf) {
			break
		}
		row := buf[offset : offset+rowSize]
		var ipBytes [16]byte
		copy(ipBytes[:], row[0:16])
		localPortRaw := binary.LittleEndian.Uint32(row[20:24])
		owningPid := binary.LittleEndian.Uint32(row[24:28])
		offset += rowSize

		port := parsePort(localPortRaw)
		if port == targetPort {
			ip := net.IP(ipBytes[:])
			res = append(res, rawListener{
				addr: fmt.Sprintf("%s:%d", ip.String(), port),
				pid:  int(owningPid),
			})
		}
	}
	return res, nil
}
