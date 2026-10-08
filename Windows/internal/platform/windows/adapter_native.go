package windows

import (
	"context"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

func scanAdaptersNative(ctx context.Context) ([]AdapterInfo, error) {
	flags := uint32(windows.GAA_FLAG_INCLUDE_GATEWAYS |
		windows.GAA_FLAG_SKIP_MULTICAST | windows.GAA_FLAG_SKIP_ANYCAST)

	var size uint32 = 16384
	var buf []byte

	for i := 0; i < 3; i++ {
		buf = make([]byte, size)
		aa := (*windows.IpAdapterAddresses)(unsafe.Pointer(&buf[0]))
		err := windows.GetAdaptersAddresses(windows.AF_UNSPEC, flags, 0, aa, &size)
		if err == nil {
			break
		}
		if err == windows.ERROR_BUFFER_OVERFLOW {
			continue
		}
		return nil, err
	}

	var results []AdapterInfo
	cur := (*windows.IpAdapterAddresses)(unsafe.Pointer(&buf[0]))

	for cur != nil {
		id := windows.BytePtrToString(cur.AdapterName)
		name := windows.UTF16PtrToString(cur.FriendlyName)
		description := windows.UTF16PtrToString(cur.Description)
		index := int(cur.IfIndex)

		status := "Disconnected"
		if cur.OperStatus == windows.IfOperStatusUp {
			status = "Up"
		}

		// 解析 IPv4 网关
		gateway := ""
		for gw := cur.FirstGatewayAddress; gw != nil; gw = gw.Next {
			ip := gw.Address.IP()
			if ip != nil && ip.To4() != nil && HasValidIPv4Gateway(ip.String()) {
				gateway = ip.String()
				break
			}
		}

		// 解析 DNS 服务器
		var v4DNS []string
		var v6DNS []string
		for dns := cur.FirstDnsServerAddress; dns != nil; dns = dns.Next {
			ip := dns.Address.IP()
			if ip != nil {
				if ip4 := ip.To4(); ip4 != nil {
					if !IsLoopbackOrLocalIP(ip4.String()) {
						v4DNS = append(v4DNS, ip4.String())
					}
				} else {
					ipStr := ip.String()
					lower := strings.ToLower(ipStr)
					if !IsLoopbackOrLocalIP(ipStr) && !strings.HasPrefix(lower, "fec0:") {
						v6DNS = append(v6DNS, ipStr)
					}
				}
			}
		}

		// 检测该网卡是否存在残留的回环 DNS 配置 (127.*, ::1 等)
		hasResidualLoopback := false
		for dns := cur.FirstDnsServerAddress; dns != nil; dns = dns.Next {
			ip := dns.Address.IP()
			if ip != nil && IsLoopbackOrLocalIP(ip.String()) {
				hasResidualLoopback = true
				break
			}
		}
		if !hasResidualLoopback && checkRegistryContainsLoopback(id) {
			hasResidualLoopback = true
		}

		v4DNS = FilterLoopbackIPs(v4DNS)
		v6DNS = FilterLoopbackIPs(v6DNS)

		// 检查 DHCP 与静态 DNS 配置（从注册表读取真实配置以防被虚拟层覆盖）
		v4DHCP, v6DHCP := getDHCPConfigFromRegistry(id)
		if len(v4DNS) == 0 {
			v4DHCP = true
		}
		if len(v6DNS) == 0 {
			v6DHCP = true
		}

		// 判断是否为虚拟网卡
		isVirt := (cur.IfType == 24 || cur.IfType == 131) // Loopback / Tunnel
		isPhysical := !IsVirtualAdapter(name, description, isVirt)

		results = append(results, AdapterInfo{
			ID:                  id,
			Name:                name,
			Description:         description,
			Index:               index,
			Status:              status,
			Gateway:             gateway,
			IPv4DHCP:            v4DHCP,
			IPv6DHCP:            v6DHCP,
			IPv4DNS:             v4DNS,
			IPv6DNS:             v6DNS,
			IsPhysical:          isPhysical,
			HasResidualLoopback: hasResidualLoopback,
		})

		cur = cur.Next
	}

	return results, nil
}

// getDHCPConfigFromRegistry 从注册表读取网卡的 DHCP 配置状态
func getDHCPConfigFromRegistry(guid string) (v4DHCP bool, v6DHCP bool) {
	v4DHCP = true
	v6DHCP = true

	if guid == "" {
		return
	}

	// 1. IPv4 注册表项
	tcpipPath := `SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\` + guid
	k, err := registry.OpenKey(registry.LOCAL_MACHINE, tcpipPath, registry.QUERY_VALUE)
	if err == nil {
		enableDHCP, _, errVal := k.GetIntegerValue("EnableDHCP")
		nameServer, _, _ := k.GetStringValue("NameServer")
		k.Close()

		v4StaticDNS := parseRegistryNameServer(nameServer)
		if errVal == nil {
			v4DHCP = (enableDHCP == 1) && len(v4StaticDNS) == 0
		} else if len(v4StaticDNS) > 0 {
			v4DHCP = false
		}
	}

	// 2. IPv6 注册表项
	tcpip6Path := `SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\` + guid
	k6, err6 := registry.OpenKey(registry.LOCAL_MACHINE, tcpip6Path, registry.QUERY_VALUE)
	if err6 == nil {
		nameServer6, _, _ := k6.GetStringValue("NameServer")
		k6.Close()

		v6StaticDNS := parseRegistryNameServer(nameServer6)
		if len(v6StaticDNS) > 0 {
			v6DHCP = false
		}
	}

	return
}

func parseRegistryNameServer(ns string) []string {
	if ns == "" {
		return nil
	}
	fields := strings.FieldsFunc(ns, func(r rune) bool {
		return r == ',' || r == ' ' || r == ';'
	})
	var clean []string
	for _, f := range fields {
		f = strings.TrimSpace(f)
		if f != "" && !IsLoopbackOrLocalIP(f) {
			clean = append(clean, f)
		}
	}
	return clean
}

// checkRegistryContainsLoopback 检查注册表中是否直接配置了 127.* 或 ::1 等回环 DNS
func checkRegistryContainsLoopback(guid string) bool {
	if guid == "" {
		return false
	}
	tcpipPath := `SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\` + guid
	if k, err := registry.OpenKey(registry.LOCAL_MACHINE, tcpipPath, registry.QUERY_VALUE); err == nil {
		ns, _, _ := k.GetStringValue("NameServer")
		k.Close()
		for _, f := range strings.FieldsFunc(ns, func(r rune) bool { return r == ',' || r == ' ' || r == ';' }) {
			if IsLoopbackOrLocalIP(f) {
				return true
			}
		}
	}
	tcpip6Path := `SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\` + guid
	if k6, err := registry.OpenKey(registry.LOCAL_MACHINE, tcpip6Path, registry.QUERY_VALUE); err == nil {
		ns6, _, _ := k6.GetStringValue("NameServer")
		k6.Close()
		for _, f := range strings.FieldsFunc(ns6, func(r rune) bool { return r == ',' || r == ' ' || r == ';' }) {
			if IsLoopbackOrLocalIP(f) {
				return true
			}
		}
	}
	return false
}

