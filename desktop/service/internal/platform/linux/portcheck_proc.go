//go:build linux

package linux

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
)

// procNetFile 描述一个待解析的 /proc/net 套接字表文件。
type procNetFile struct {
	path     string
	protocol string
}

// procNetFiles 按协议列出需要解析的内核套接字表。
var procNetFiles = []procNetFile{
	{"/proc/net/udp", "UDP"},
	{"/proc/net/tcp", "TCP"},
	{"/proc/net/udp6", "UDP"},
	{"/proc/net/tcp6", "TCP"},
}

// procSocket 描述从 /proc/net/* 解析出的单个套接字条目。
type procSocket struct {
	Protocol     string
	LocalAddress string
	LocalPort    int
	Inode        int
	State        int
}

// tcpListenState 为 TCP_LISTEN 状态码（UDP 无连接状态，恒为 07）。
const tcpListenState = 0x0A

// parseProcNet 解析 /proc/net 下的套接字表。
//
// 文件格式（每行）：
//
//	sl local_address rem_address st tx_queue:rx_queue tr:tm->when retrnsmt uid timeout inode
//	0: 0100007F:0035 00000000:0000 07 ... 12345
//
// local_address 为"小端十六进制 IP:十六进制端口"。
func parseProcNet(path, protocol string) ([]procSocket, error) {
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	defer f.Close()

	var sockets []procSocket
	sc := bufio.NewScanner(f)
	sc.Scan() // 跳过表头
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		// 至少需要 local_address、st、以及 inode 字段
		if len(fields) < 10 {
			continue
		}

		addr, port, err := parseHexEndpoint(fields[1])
		if err != nil {
			continue
		}
		state, err := strconv.ParseInt(fields[3], 16, 32)
		if err != nil {
			continue
		}
		// inode 位于第 10 列（索引 9），部分内核版本列数略有差异
		inode := 0
		if v, err := strconv.Atoi(fields[9]); err == nil {
			inode = v
		}

		sockets = append(sockets, procSocket{
			Protocol:     protocol,
			LocalAddress: net.JoinHostPort(addr, strconv.Itoa(port)),
			LocalPort:    port,
			Inode:        inode,
			State:        int(state),
		})
	}
	return sockets, sc.Err()
}

// parseHexEndpoint 解析 "0100007F:0035" 形式的端点。
func parseHexEndpoint(s string) (addr string, port int, err error) {
	parts := strings.Split(s, ":")
	if len(parts) != 2 {
		return "", 0, fmt.Errorf("非法端点: %s", s)
	}

	portVal, err := strconv.ParseUint(parts[1], 16, 32)
	if err != nil {
		return "", 0, err
	}

	ip, err := parseProcHexIP(parts[0])
	if err != nil {
		return "", 0, err
	}
	return ip, int(portVal), nil
}

// parseProcHexIP 将 /proc 中的小端十六进制地址转为点分十进制或 IPv6 字符串。
func parseProcHexIP(hexStr string) (string, error) {
	switch len(hexStr) {
	case 8:
		v, err := strconv.ParseUint(hexStr, 16, 32)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("%d.%d.%d.%d", v&0xff, (v>>8)&0xff, (v>>16)&0xff, (v>>24)&0xff), nil
	case 32:
		return parseProcHexIPv6(hexStr)
	default:
		return "", fmt.Errorf("非法地址长度: %s", hexStr)
	}
}

// parseProcHexIPv6 解析 32 位十六进制 IPv6 地址（按 4 字节小端分组）。
func parseProcHexIPv6(hexStr string) (string, error) {
	var groups []string
	for i := 0; i < 32; i += 8 {
		v, err := strconv.ParseUint(hexStr[i:i+8], 16, 32)
		if err != nil {
			return "", err
		}
		groups = append(groups,
			fmt.Sprintf("%02x%02x", v&0xff, (v>>8)&0xff),
			fmt.Sprintf("%02x%02x", (v>>16)&0xff, (v>>24)&0xff),
		)
	}
	// 归并为零压缩 IPv6 文本
	full := ""
	for i, g := range groups {
		if i > 0 {
			full += ":"
		}
		full += g
	}
	return full, nil
}

// collectPort53Sockets 收集所有监听 53 端口的套接字条目。
func collectPort53Sockets() ([]procSocket, error) {
	var out []procSocket
	for _, pf := range procNetFiles {
		sockets, err := parseProcNet(pf.path, pf.protocol)
		if err != nil {
			return nil, err
		}
		for _, s := range sockets {
			if s.LocalPort != 53 {
				continue
			}
			// TCP 仅保留 LISTEN 状态；UDP 无连接状态需保留
			if s.Protocol == "TCP" && s.State != tcpListenState {
				continue
			}
			out = append(out, s)
		}
	}
	return out, nil
}
