//go:build linux

// Package linux 提供 Linux 平台的平台能力实现。
//
// 本包仅依赖 internal/platform（中性抽象层）与标准库 / golang.org/x/sys/unix，
// 不反向依赖任何上层业务包，从而在组合根（cmd/service）处按构建标签选择。
//
// 各能力对应独立的源文件：
//
//	adapter.go          网卡枚举与扫描（net.Interfaces + /proc + /sys）
//	resolvconf.go       /etc/resolv.conf 解析与写入
//	takeover_backend.go DNS 接管后端（systemd-resolved / NetworkManager / resolv.conf）
//	takeover.go         LinuxDNSManager（DNSManager 接口实现）
//	portcheck.go        53 端口占用探测（/proc/net 解析）
//	portcheck_autofix.go DNSStubListener 自动修复
//	firewall.go         防火墙放行（nftables / iptables 探测）
//	service_mgr.go      systemd 服务状态管理（systemctl show 解析）
//	privilege.go        特权执行（root 身份直执行）
//	restore_script.go   离线恢复脚本 restore-dns.sh 生成
package linux
