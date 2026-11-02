//go:build linux

package linux

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// readDefaultGateway 从 /proc/net/route 解析指定接口的 IPv4 默认网关。
//
// /proc/net/route 每行格式为：
//
//	Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT
//
// 其中 Destination 为 "00000000" 表示默认路由，Gateway 为小端序十六进制。
func readDefaultGateway(ifaceName string) string {
	f, err := os.Open("/proc/net/route")
	if err != nil {
		return ""
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Scan() // 跳过表头
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 3 {
			continue
		}
		if fields[0] != ifaceName || fields[1] != "00000000" {
			continue
		}
		if gw := parseHexIPv4(fields[2]); gw != "" && gw != "0.0.0.0" {
			return gw
		}
	}
	return ""
}

// parseHexIPv4 将 /proc 中的小端十六进制 IPv4 转为点分十进制字符串。
func parseHexIPv4(hexStr string) string {
	v, err := strconv.ParseUint(hexStr, 16, 32)
	if err != nil {
		return ""
	}
	// 小端序：低字节为第一段
	return fmt.Sprintf("%d.%d.%d.%d", v&0xff, (v>>8)&0xff, (v>>16)&0xff, (v>>24)&0xff)
}

// ifaceDescription 尝试从 sysfs/udev 读取接口的友好描述，失败时回退为接口名。
func ifaceDescription(name string) string {
	// 1. 通过 /sys/class/net/<name>/device/uevent 的 DRIVER 字段获取驱动名
	uevent := filepath.Join("/sys/class/net", name, "device/uevent")
	if data, err := os.ReadFile(uevent); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			if strings.HasPrefix(line, "DRIVER=") {
				drv := strings.TrimPrefix(strings.TrimSpace(line), "DRIVER=")
				if drv != "" {
					return drv
				}
			}
		}
	}
	// 2. 回退：读取 /sys/class/net/<name>/type 分辨常见类型
	return name
}

// ifaceIsUp 判断接口是否处于 UP 运行状态。
func ifaceIsUp(iface net.Interface) bool {
	return iface.Flags&net.FlagUp != 0
}

// ifaceHasPointToPoint 判断接口是否为点对点（隧道）类型。
func ifaceHasPointToPoint(iface net.Interface) bool {
	return iface.Flags&net.FlagPointToPoint != 0
}

// listManagedInterfaces 返回排序后的所有网络接口。
func listManagedInterfaces() ([]net.Interface, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	sort.Slice(ifaces, func(i, j int) bool { return ifaces[i].Index < ifaces[j].Index })
	return ifaces, nil
}
