//go:build windows

package windows

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"os/exec"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/haoze-evolluling/diting/server/internal/platform"
	"golang.org/x/sys/windows"
)

var (
	procSetInterfaceDnsSettings = modIphlpapi.NewProc("SetInterfaceDnsSettings")

	modDnsapi                 = windows.NewLazySystemDLL("dnsapi.dll")
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

// normalizeDNSAddress 把单条 DNS 服务器字符串归一化成指定协议栈的纯 IP 字面量。
//
// SetInterfaceDnsSettings 对参数极其严格：只要栈与地址族不匹配、或地址不是纯 IP 字面量，
// 整次调用就返回 ERROR_INVALID_PARAMETER (87)，列表里其余合法地址一起作废。
// 实测会被拒的真实形态包括 `fe80::1%12`（链路本地带 zone）、`[fe80::1]`（方括号）、
// `8.8.8.8:53`（带端口）、协议 URL，以及 IPv4 栈里混入 IPv6 地址（反之亦然）。
func normalizeDNSAddress(raw string, isIPv6 bool) (string, bool) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return "", false
	}
	// `[fe80::1]:53` / `8.8.8.8:53`：只取主机部分
	if host, _, err := net.SplitHostPort(s); err == nil {
		s = host
	}
	s = strings.Trim(s, "[]")
	// `fe80::1%12`：去掉 zone 后缀
	if i := strings.LastIndex(s, "%"); i > 0 {
		s = s[:i]
	}
	ip := net.ParseIP(strings.TrimSpace(s))
	if ip == nil {
		return "", false
	}
	return normalizeIPForStack(ip, isIPv6)
}

// normalizeIPForStack 校验地址族并把 IP 压成规范字面量
func normalizeIPForStack(ip net.IP, isIPv6 bool) (string, bool) {
	if isIPv6 {
		if ip.To4() != nil {
			return "", false
		}
		return ip.String(), true
	}
	v4 := ip.To4()
	if v4 == nil {
		return "", false
	}
	return v4.String(), true
}

// normalizeServersForStack 归一化整份列表：保留同族合法地址（去重），
// 其余（族不匹配、非 IP 字面量）作为 dropped 返回供调用方记录日志。
func normalizeServersForStack(servers []string, isIPv6 bool) (kept []string, dropped []string) {
	seen := make(map[string]struct{}, len(servers))
	for _, raw := range servers {
		addr, ok := normalizeDNSAddress(raw, isIPv6)
		if !ok {
			dropped = append(dropped, raw)
			continue
		}
		if _, dup := seen[addr]; dup {
			continue
		}
		seen[addr] = struct{}{}
		kept = append(kept, addr)
	}
	return kept, dropped
}

// dnsProtoLabel 返回日志与错误信息里使用的协议栈名称
func dnsProtoLabel(isIPv6 bool) string {
	if isIPv6 {
		return "IPv6"
	}
	return "IPv4"
}

// runNetshDNS 执行 netsh interface <family> 子命令（带超时，避免 netsh 挂住整条恢复链路）
func runNetshDNS(family string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	full := append([]string{"interface", family}, args...)
	cmd := exec.CommandContext(ctx, "netsh", full...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if _, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("netsh %s 失败: %w", strings.Join(full, " "), err)
	}
	return nil
}

// setStackDNSNetsh 用 netsh 配置单栈 DNS（servers 为空表示恢复 DHCP 自动获取）
func setStackDNSNetsh(adapterName string, isIPv6 bool, servers []string) error {
	family := "ipv4"
	if isIPv6 {
		family = "ipv6"
	}
	name := "name=" + adapterName

	if len(servers) == 0 {
		return runNetshDNS(family, "set", "dnsservers", name, "source=dhcp")
	}
	if err := runNetshDNS(family, "set", "dnsservers", name, "static", servers[0], "primary", "validate=no"); err != nil {
		return err
	}
	for i, server := range servers[1:] {
		index := fmt.Sprintf("index=%d", i+2)
		if err := runNetshDNS(family, "add", "dnsservers", name, server, index, "validate=no"); err != nil {
			return err
		}
	}
	return nil
}

// resetAdapterDNSNetsh 用 netsh 把网卡双栈 DNS 直接拉回 DHCP 自动获取
func resetAdapterDNSNetsh(adapterName string) error {
	var errs []error
	for _, isIPv6 := range []bool{false, true} {
		if err := setStackDNSNetsh(adapterName, isIPv6, nil); err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

// setInterfaceDnsSettingsNative 通过 Win32 原生 API 配置单栈 (IPv4 或 IPv6) DNS。
//
// servers 必须已经按协议栈归一化（见 normalizeServersForStack）；传空表示该栈重置为 DHCP。
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
		return fmt.Errorf("SetInterfaceDnsSettings (%s) 失败，错误码: %d (%w)", dnsProtoLabel(isIPv6), ret, syscall.Errno(ret))
	}
	return nil
}

// applyStackDNS 下发单栈 DNS：先归一化，再走原生 API；原生失败时退回 netsh（与 restore-dns.bat 同一路径）。
//
// 只报错不兜底的后果是实打实的「永久断网」：还原失败时网卡就停在 127.0.0.1/::1 上，
// 而快照按设计保留，于是每次点「一键恢复」都重复撞同一个错误。
func applyStackDNS(guidStr, adapterName string, isIPv6 bool, servers []string) error {
	proto := dnsProtoLabel(isIPv6)
	kept, dropped := normalizeServersForStack(servers, isIPv6)
	if len(dropped) > 0 {
		log.Printf("[DNS] 网卡 [%s] 的 %s 快照含 %d 条非法地址，已丢弃（否则整次设置会被 Windows 拒绝）: %v\n",
			adapterName, proto, len(dropped), dropped)
	}

	nativeErr := setInterfaceDnsSettingsNative(guidStr, isIPv6, kept)
	if nativeErr == nil {
		return nil
	}
	if adapterName == "" {
		return fmt.Errorf("设置网卡 [%s] 的 %s DNS 失败（下发地址: %v）: %w", adapterName, proto, kept, nativeErr)
	}
	if netshErr := setStackDNSNetsh(adapterName, isIPv6, kept); netshErr != nil {
		return fmt.Errorf("设置网卡 [%s] 的 %s DNS 失败（下发地址: %v）: %w（netsh 兜底亦失败: %v）",
			adapterName, proto, kept, nativeErr, netshErr)
	}
	log.Printf("[DNS] 网卡 [%s] 的 %s DNS 原生 API 失败，已通过 netsh 兜底完成: %v\n", adapterName, proto, nativeErr)
	return nil
}

// setAdapterDNSDualStackNative 分别配置网卡的 IPv4 与 IPv6 DNS（传 nil 表示该栈使用 DHCP 自动获取）
func setAdapterDNSDualStackNative(guidStr, adapterName string, v4Servers []string, v6Servers []string) error {
	var errs []error
	if err := applyStackDNS(guidStr, adapterName, false, v4Servers); err != nil {
		errs = append(errs, err)
	}
	if err := applyStackDNS(guidStr, adapterName, true, v6Servers); err != nil {
		errs = append(errs, err)
	}
	return errors.Join(errs...)
}

// resetAdapterDNSNative 使用 Windows 原生 API 将网卡 IPv4 与 IPv6 双栈 DNS 恢复为 DHCP
func resetAdapterDNSNative(guidStr, adapterName string) error {
	return setAdapterDNSDualStackNative(guidStr, adapterName, nil, nil)
}

// resetResidualLoopbackDNSNative 枚举所有网卡并针对配置了回环地址 (127.*, ::1 等) 的网卡执行原生 DNS 重置。
//
// 每张网卡的重置结果都会聚合返回：旧实现逐个 `_ =` 吞错并恒返 nil，
// 调用方据此报告「兜底自愈成功」，而网卡实际仍指向 127.0.0.1。
func resetResidualLoopbackDNSNative(ctx context.Context) error {
	adapters, err := scanAdaptersNative(ctx)
	if err != nil {
		return err
	}

	var errs []error
	for _, a := range adapters {
		if !a.HasResidualLoopback {
			continue
		}
		if err := resetAdapterDNSNative(a.ID, a.Name); err != nil {
			errs = append(errs, fmt.Errorf("重置网卡 [%s] 残留 DNS 失败: %w", a.Name, err))
		}
	}
	return errors.Join(errs...)
}

// forceResetLoopbackAdaptersToDHCP 对还原失败后仍指向本机回环的网卡直接走 netsh 拉回 DHCP。
//
// 这是「先保证有网」的最后一道闸：快照仍保留在 dns_state.json 里，退回 DHCP 不会丢失
// 原始静态 DNS 的依据，下一次还原/自愈成功后仍会按快照写回。
func forceResetLoopbackAdaptersToDHCP(ctx context.Context, adapters []platform.AdapterState) error {
	if len(adapters) == 0 {
		return nil
	}
	scanned, err := scanAdaptersNative(ctx)
	if err != nil {
		return err
	}

	nameByID := make(map[string]string, len(adapters))
	for _, a := range adapters {
		nameByID[a.ID] = a.Name
	}

	var errs []error
	for _, a := range scanned {
		restoreName, rejected := nameByID[a.ID]
		if !rejected || !a.HasResidualLoopback {
			continue
		}
		name := restoreName
		if name == "" {
			name = a.Name
		}
		if name == "" {
			errs = append(errs, fmt.Errorf("网卡 [%s] 仍残留回环 DNS，但缺少网卡名无法兜底重置", a.ID))
			continue
		}
		if err := resetAdapterDNSNetsh(name); err != nil {
			errs = append(errs, fmt.Errorf("网卡 [%s] 兜底拉回 DHCP 失败: %w", name, err))
			continue
		}
		log.Printf("[DNS] 网卡 [%s] 还原失败后仍指向本机回环，已通过 netsh 兜底重置为 DHCP（原始快照保留，可再次恢复）\n", name)
	}
	return errors.Join(errs...)
}
