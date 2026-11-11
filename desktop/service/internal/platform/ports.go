package platform

import (
	"net"
	"strings"
)

// AreAddressesAvailable 快速测试指定地址列表是否均可成功绑定。
func AreAddressesAvailable(udpAddrs, tcpAddrs []string) bool {
	for _, u := range udpAddrs {
		if !TestUDPBind(u) {
			return false
		}
	}
	for _, t := range tcpAddrs {
		if !TestTCPBind(t) {
			return false
		}
	}
	return true
}

// TestUDPBind 测试指定 UDP 地址是否能够成功绑定。
func TestUDPBind(addr string) bool {
	netType := "udp4"
	if isIPv6Addr(addr) {
		netType = "udp6"
	}
	conn, err := net.ListenPacket(netType, addr)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

// TestTCPBind 测试指定 TCP 地址是否能够成功绑定。
func TestTCPBind(addr string) bool {
	netType := "tcp4"
	if isIPv6Addr(addr) {
		netType = "tcp6"
	}
	l, err := net.Listen(netType, addr)
	if err != nil {
		return false
	}
	_ = l.Close()
	return true
}

// isIPv6Addr 判断监听地址是否属于 IPv6。
func isIPv6Addr(addr string) bool {
	h, _, err := net.SplitHostPort(addr)
	if err != nil {
		h = addr
	}
	return strings.Contains(h, ":") || strings.HasPrefix(addr, "[::]")
}

// IsOnlyLoopback 判断目标监听地址集合是否全部为回环地址（不含局域网监听）。
func IsOnlyLoopback(udpAddrs, tcpAddrs []string) bool {
	for _, a := range append(append([]string{}, udpAddrs...), tcpAddrs...) {
		h, _, err := net.SplitHostPort(a)
		if err != nil {
			h = a
		}
		host := strings.Trim(h, "[]")
		if host != "127.0.0.1" && host != "::1" && host != "localhost" {
			return false
		}
	}
	return true
}
