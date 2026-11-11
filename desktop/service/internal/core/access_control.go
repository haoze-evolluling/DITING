package core

import (
	"fmt"
	"net"
	"strings"
	"sync"
)

// AccessControlConfig 客户端访问控制配置
// 借鉴自 AdGuard Home (access.go) 与 dnscrypt-proxy (plugin_allow_ip / plugin_block_ip)
type AccessControlConfig struct {
	AllowedClients []string `json:"allowedClients"` // 允许访问的客户端 IP 或 CIDR 网段（若非空，仅名单内客户端可解析）
	BlockedClients []string `json:"blockedClients"` // 显式阻断的客户端 IP 或 CIDR 网段
}

// DefaultAccessControlConfig 返回默认访问控制配置（默认不限制客户端）
func DefaultAccessControlConfig() AccessControlConfig {
	return AccessControlConfig{
		AllowedClients: []string{},
		BlockedClients: []string{},
	}
}

// AccessControl 客户端访问控制管理器，线程安全
type AccessControl struct {
	mu          sync.RWMutex
	allowedIPs  map[string]struct{}
	allowedNets []*net.IPNet
	blockedIPs  map[string]struct{}
	blockedNets []*net.IPNet
	hasAllowed  bool
}

// NewAccessControl 创建客户端访问控制引擎
func NewAccessControl(cfg AccessControlConfig) (*AccessControl, error) {
	ac := &AccessControl{}
	if err := ac.Update(cfg); err != nil {
		return nil, err
	}
	return ac, nil
}

// Update 更新访问控制规则
func (ac *AccessControl) Update(cfg AccessControlConfig) error {
	ac.mu.Lock()
	defer ac.mu.Unlock()

	allowedIPs := make(map[string]struct{})
	var allowedNets []*net.IPNet
	for _, entry := range cfg.AllowedClients {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		ip, ipNet, err := parseIPOrCIDR(entry)
		if err != nil {
			return fmt.Errorf("解析 allowedClients 条目 %q 失败: %w", entry, err)
		}
		if ipNet != nil {
			allowedNets = append(allowedNets, ipNet)
		} else if ip != nil {
			allowedIPs[ip.String()] = struct{}{}
		}
	}

	blockedIPs := make(map[string]struct{})
	var blockedNets []*net.IPNet
	for _, entry := range cfg.BlockedClients {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		ip, ipNet, err := parseIPOrCIDR(entry)
		if err != nil {
			return fmt.Errorf("解析 blockedClients 条目 %q 失败: %w", entry, err)
		}
		if ipNet != nil {
			blockedNets = append(blockedNets, ipNet)
		} else if ip != nil {
			blockedIPs[ip.String()] = struct{}{}
		}
	}

	ac.allowedIPs = allowedIPs
	ac.allowedNets = allowedNets
	ac.blockedIPs = blockedIPs
	ac.blockedNets = blockedNets
	ac.hasAllowed = (len(allowedIPs) > 0 || len(allowedNets) > 0)
	return nil
}

// CheckAccess 校验指定客户端 IP 是否被允许访问
func (ac *AccessControl) CheckAccess(ip net.IP) (bool, string) {
	if ac == nil {
		return true, ""
	}
	if ip == nil {
		return true, ""
	}

	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}

	ac.mu.RLock()
	defer ac.mu.RUnlock()

	ipStr := ip.String()

	// 1. 显式黑名单检查 (Blocked List 优先)
	if _, found := ac.blockedIPs[ipStr]; found {
		return false, fmt.Sprintf("客户端 IP %s 处于黑名单阻断列表中", ipStr)
	}
	for _, subnet := range ac.blockedNets {
		if subnet.Contains(ip) {
			return false, fmt.Sprintf("客户端 IP %s 处于黑名单网段 %s 中", ipStr, subnet.String())
		}
	}

	// 2. 白名单检查 (若配置了 AllowedClients，则必须在允许名单内)
	if ac.hasAllowed {
		if _, found := ac.allowedIPs[ipStr]; found {
			return true, ""
		}
		for _, subnet := range ac.allowedNets {
			if subnet.Contains(ip) {
				return true, ""
			}
		}
		return false, fmt.Sprintf("客户端 IP %s 不在允许访问的白名单列表中", ipStr)
	}

	return true, ""
}

func parseIPOrCIDR(s string) (net.IP, *net.IPNet, error) {
	if strings.Contains(s, "/") {
		_, ipNet, err := net.ParseCIDR(s)
		if err != nil {
			return nil, nil, err
		}
		return nil, ipNet, nil
	}
	ip := net.ParseIP(s)
	if ip == nil {
		return nil, nil, fmt.Errorf("无效的 IP 地址: %s", s)
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	return ip, nil, nil
}
