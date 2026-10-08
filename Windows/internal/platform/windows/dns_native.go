package windows

import (
	"context"
	"fmt"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	procSetInterfaceDnsSettings = modIphlpapi.NewProc("SetInterfaceDnsSettings")
)

const (
	dnsSettingNameServer         uint64 = 0x0002
	dnsInterfaceSettingsVersion1 uint32 = 1
)

type dnsInterfaceSettings struct {
	Version             uint32
	Flags               uint64
	Domain              *uint16
	NameServer          *uint16
	SearchList          *uint16
	RegistrationEnabled uint32
	RegisterAdapterName uint32
	EnableLLMNR         uint32
	QueryAdapterName    uint32
	ProfileNameServer   *uint16
}

// isSetInterfaceDnsSettingsSupported 检查当前系统是否支持 SetInterfaceDnsSettings 原生 API
func isSetInterfaceDnsSettingsSupported() bool {
	return procSetInterfaceDnsSettings.Find() == nil
}

// setAdapterDNSNative 使用 Windows 原生 API (SetInterfaceDnsSettings) 配置网卡 DNS
func setAdapterDNSNative(guidStr string, servers []string) error {
	if !isSetInterfaceDnsSettingsSupported() {
		return fmt.Errorf("SetInterfaceDnsSettings 不受支持")
	}

	cleanGUID := strings.Trim(strings.TrimSpace(guidStr), "{}")
	guid, err := windows.GUIDFromString("{" + cleanGUID + "}")
	if err != nil {
		return fmt.Errorf("无效的网卡 GUID: %w", err)
	}

	var settings dnsInterfaceSettings
	settings.Version = dnsInterfaceSettingsVersion1
	settings.Flags = dnsSettingNameServer

	nsJoined := strings.Join(servers, ",")
	if nsJoined != "" {
		nsPtr, err := windows.UTF16PtrFromString(nsJoined)
		if err != nil {
			return err
		}
		settings.NameServer = nsPtr
	}

	ret, _, _ := procSetInterfaceDnsSettings.Call(
		uintptr(unsafe.Pointer(&guid)),
		uintptr(unsafe.Pointer(&settings)),
	)
	if ret != 0 {
		return fmt.Errorf("SetInterfaceDnsSettings 失败，错误码: %d (%w)", ret, syscall.Errno(ret))
	}
	return nil
}

// resetAdapterDNSNative 使用 Windows 原生 API 将网卡 DNS 恢复为 DHCP
func resetAdapterDNSNative(guidStr string) error {
	return setAdapterDNSNative(guidStr, nil)
}

// resetResidualLoopbackDNSNative 枚举所有网卡并针对配置了回环地址 (127.*, ::1 等) 的网卡执行原生 DNS 重置
func resetResidualLoopbackDNSNative(ctx context.Context, executor CommandExecutor) error {
	adapters, err := scanAdaptersNative(ctx)
	if err != nil {
		return err
	}

	for _, a := range adapters {
		if !a.HasResidualLoopback {
			continue
		}
		// 优先尝试原生 API 重置
		if err := resetAdapterDNSNative(a.ID); err != nil && executor != nil {
			// 原生重置异常时，使用 netsh 容灾重置
			_, _ = executor.RunCommand(ctx, "netsh", "interface", "ipv4", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "source=dhcp")
			_, _ = executor.RunCommand(ctx, "netsh", "interface", "ipv6", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "source=dhcp")
		}
	}
	return nil
}

