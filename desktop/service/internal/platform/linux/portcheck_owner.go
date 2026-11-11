//go:build linux

package linux

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// socketInodeOwners 扫描 /proc/<pid>/fd 建立 套接字 inode → PID 的映射。
//
// Linux 的 /proc/net/* 表只提供 inode，不提供进程信息；
// 通过遍历各进程的文件描述符软链（socket:[inode]）反查归属进程。
// 仅在需要定位冲突进程时调用，避免常态下的全盘扫描开销。
func socketInodeOwners() map[int]int {
	owners := make(map[int]int)

	entries, err := os.ReadDir("/proc")
	if err != nil {
		return owners
	}

	// 本进程也必须登记：下游用 pid == selfPID 判定「自身监听」，
	// 旧实现把自己排除后该判定永远拿不到输入，自身监听会被误报为第三方冲突。
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		collectSocketFds(pid, owners)
	}
	return owners
}

// collectSocketFds 解析单个进程的 fd 目录，登记其持有的套接字 inode。
func collectSocketFds(pid int, owners map[int]int) {
	fdDir := filepath.Join("/proc", strconv.Itoa(pid), "fd")
	fds, err := os.ReadDir(fdDir)
	if err != nil {
		return
	}
	for _, fd := range fds {
		link, err := os.Readlink(filepath.Join(fdDir, fd.Name()))
		if err != nil {
			continue
		}
		inode, ok := parseSocketLink(link)
		if !ok {
			continue
		}
		owners[inode] = pid
	}
}

// parseSocketLink 从 "socket:[12345]" 形式的软链目标中提取 inode。
func parseSocketLink(link string) (int, bool) {
	const prefix = "socket:["
	if !strings.HasPrefix(link, prefix) || !strings.HasSuffix(link, "]") {
		return 0, false
	}
	inner := link[len(prefix) : len(link)-1]
	inode, err := strconv.Atoi(inner)
	if err != nil {
		return 0, false
	}
	return inode, true
}

// processName 读取 /proc/<pid>/comm 获取进程名，失败时返回空串。
func processName(pid int) string {
	data, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "comm"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

// systemdResolvedPID 扫描 /proc 定位 systemd-resolved 的 PID，未运行时返回 0。
//
// systemd-resolved 是 Type=notify 服务，不创建任何 pidfile；
// 旧实现读取 /run/systemd/resolve/resolved.pid（该文件从不产生），恒得 0，
// 使 stub 识别与兜底终止整体失效。这里按进程名扫描，无特权时也能覆盖同名进程。
func systemdResolvedPID() int {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return 0
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		if isSystemdResolvedProcess(pid) {
			return pid
		}
	}
	return 0
}

// isSystemdResolvedProcess 判断进程是否为 systemd-resolved。
func isSystemdResolvedProcess(pid int) bool {
	name := processName(pid)
	return name == "systemd-resolve" || name == "systemd-resolved"
}

// isResolvedStubAddress 判断地址是否为 systemd-resolved 的 stub 监听地址
// (127.0.0.53 与 127.0.0.54，前者供本机解析，后者供容器/WSL 使用)。
func isResolvedStubAddress(addr string) bool {
	host := addr
	if idx := strings.LastIndex(addr, ":"); idx >= 0 {
		host = addr[:idx]
	}
	host = strings.Trim(host, "[]")
	return host == "127.0.0.53" || host == "127.0.0.54"
}
