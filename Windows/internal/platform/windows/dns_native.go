package windows

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	procSetInterfaceDnsSettings = modIphlpapi.NewProc("SetInterfaceDnsSettings")

	modDnsapi                  = windows.NewLazySystemDLL("dnsapi.dll")
	procDnsFlushResolverCache = modDnsapi.NewProc("DnsFlushResolverCache")
)

const (
	dnsSettingIPV6               uint64 = 0x0001
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

// flushDNSCacheNative 原生调用 Win32 dnsapi.dll DnsFlushResolverCache 刷新系统 DNS 缓存
func flushDNSCacheNative() error {
	if procDnsFlushResolverCache.Find() != nil {
		return fmt.Errorf("DnsFlushResolverCache 不受支持")
	}
	ret, _, err := procDnsFlushResolverCache.Call()
	if ret == 0 {
		return fmt.Errorf("DnsFlushResolverCache 失败: %w", err)
	}
	return nil
}

// setInterfaceDnsSettingsNative 通过 Win32 原生 API 配置单栈 (IPv4 或 IPv6) DNS
func setInterfaceDnsSettingsNative(guidStr string, isIPv6 bool, servers []string) error {
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
	if isIPv6 {
		settings.Flags |= dnsSettingIPV6
	}

	if len(servers) > 0 {
		nsJoined := strings.Join(servers, ",")
		nsPtr, err := windows.UTF16PtrFromString(nsJoined)
		if err != nil {
			return err
		}
		settings.NameServer = nsPtr
	} else {
		// NameServer 为 nil 时，Windows 会将该栈 DNS 重置为 DHCP 自动获取
		settings.NameServer = nil
	}

	ret, _, _ := procSetInterfaceDnsSettings.Call(
		uintptr(unsafe.Pointer(&guid)),
		uintptr(unsafe.Pointer(&settings)),
	)
	if ret != 0 {
		proto := "IPv4"
		if isIPv6 {
			proto = "IPv6"
		}
		return fmt.Errorf("SetInterfaceDnsSettings (%s) 失败，错误码: %d (%w)", proto, ret, syscall.Errno(ret))
	}
	return nil
}

// setAdapterDNSDualStackNative 分别配置网卡的 IPv4 与 IPv6 DNS（传 nil 表示该栈使用 DHCP 自动获取）
func setAdapterDNSDualStackNative(guidStr string, v4Servers []string, v6Servers []string) error {
	var errs []error
	if err := setInterfaceDnsSettingsNative(guidStr, false, v4Servers); err != nil {
		errs = append(errs, err)
	}
	if err := setInterfaceDnsSettingsNative(guidStr, true, v6Servers); err != nil {
		errs = append(errs, err)
	}
	return errors.Join(errs...)
}

// resetAdapterDNSNative 使用 Windows 原生 API 将网卡 IPv4 与 IPv6 双栈 DNS 恢复为 DHCP
func resetAdapterDNSNative(guidStr string) error {
	return setAdapterDNSDualStackNative(guidStr, nil, nil)
}

// resetResidualLoopbackDNSNative 枚举所有网卡并针对配置了回环地址 (127.*, ::1 等) 的网卡执行原生 DNS 重置
func resetResidualLoopbackDNSNative(ctx context.Context) error {
	adapters, err := scanAdaptersNative(ctx)
	if err != nil {
		return err
	}

	for _, a := range adapters {
		if !a.HasResidualLoopback {
			continue
		}
		_ = resetAdapterDNSNative(a.ID)
	}
	return nil
}

