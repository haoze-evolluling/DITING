package dns

import (
	"fmt"
	"net"
	"strings"
	"sync"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// RebindConfig DNS Rebinding 保护配置类型别名
type RebindConfig = core.RebindConfig

// DefaultRebindConfig 默认 Rebind 防御配置别名
var DefaultRebindConfig = core.DefaultRebindConfig

// RebindProtectionManager DNS Rebinding 防御管理器
type RebindProtectionManager struct {
	mu             sync.RWMutex
	enabled        bool
	allowedDomains []string
}

// NewRebindProtectionManager 创建 DNS 重新绑定防护管理器
func NewRebindProtectionManager(cfg RebindConfig) *RebindProtectionManager {
	m := &RebindProtectionManager{
		enabled: cfg.Enabled,
	}
	m.SetAllowedDomains(cfg.AllowedDomains)
	return m
}

// SetEnabled 设置是否开启 DNS Rebinding 防御
func (m *RebindProtectionManager) SetEnabled(enabled bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.enabled = enabled
}

// IsEnabled 获取当前是否开启 DNS Rebinding 防御
func (m *RebindProtectionManager) IsEnabled() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.enabled
}

// GetConfig 获取当前完整配置快照
func (m *RebindProtectionManager) GetConfig() RebindConfig {
	m.mu.RLock()
	defer m.mu.RUnlock()
	domains := make([]string, len(m.allowedDomains))
	copy(domains, m.allowedDomains)
	return RebindConfig{
		Enabled:        m.enabled,
		AllowedDomains: domains,
	}
}

// UpdateConfig 完整更新 DNS Rebinding 防御配置
func (m *RebindProtectionManager) UpdateConfig(cfg RebindConfig) {
	m.mu.Lock()
	m.enabled = cfg.Enabled
	m.mu.Unlock()
	m.SetAllowedDomains(cfg.AllowedDomains)
}

// SetAllowedDomains 更新白名单域名
func (m *RebindProtectionManager) SetAllowedDomains(domains []string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	cleaned := make([]string, 0, len(domains))
	for _, d := range domains {
		d = strings.ToLower(strings.TrimSpace(d))
		d = strings.TrimPrefix(d, "*")
		d = strings.Trim(d, ".")
		if d != "" {
			cleaned = append(cleaned, d)
		}
	}
	m.allowedDomains = cleaned
}

// IsDomainAllowed 判断域名是否在内网白名单中
func (m *RebindProtectionManager) IsDomainAllowed(domain string) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	domain = strings.ToLower(strings.Trim(domain, "."))
	for _, allowed := range m.allowedDomains {
		if domain == allowed || strings.HasSuffix(domain, "."+allowed) {
			return true
		}
	}
	return false
}

// IsBlockedIP 判定 IP 是否为私有/回环/链路本地/未指定地址（RFC 1918、RFC 4193、RFC 3927 等）
func IsBlockedIP(ip net.IP) bool {
	if ip == nil {
		return false
	}
	if ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
		return true
	}
	// 针对 DNS64 / NAT64 (RFC 6052 64:ff9b::/96) 合成地址，提取内嵌 IPv4 检查是否为内网私有地址
	if len(ip) == 16 && ip[0] == 0x00 && ip[1] == 0x64 && ip[2] == 0xff && ip[3] == 0x9b &&
		ip[4] == 0 && ip[5] == 0 && ip[6] == 0 && ip[7] == 0 &&
		ip[8] == 0 && ip[9] == 0 && ip[10] == 0 && ip[11] == 0 {
		embeddedV4 := net.IPv4(ip[12], ip[13], ip[14], ip[15])
		if embeddedV4.IsPrivate() || embeddedV4.IsLoopback() || embeddedV4.IsLinkLocalUnicast() || embeddedV4.IsUnspecified() {
			return true
		}
	}
	return false
}

// FindBlockedIPInMsg 遍历报文各 Section 提取首个非公网内网 IP（防御 DNS 重新绑定攻击）
func FindBlockedIPInMsg(msg *dns.Msg) net.IP {
	if msg == nil {
		return nil
	}
	for _, section := range [][]dns.RR{msg.Answer, msg.Extra, msg.Ns} {
		for _, rr := range section {
			switch v := rr.(type) {
			case *dns.A:
				if IsBlockedIP(v.A) {
					return v.A
				}
			case *dns.AAAA:
				if IsBlockedIP(v.AAAA) {
					return v.AAAA
				}
			case *dns.HTTPS:
				if ip := findBlockedHintIP(v.Value); ip != nil {
					return ip
				}
			case *dns.SVCB:
				if ip := findBlockedHintIP(v.Value); ip != nil {
					return ip
				}
			}
		}
	}
	return nil
}

func findBlockedHintIP(values []dns.SVCBKeyValue) net.IP {
	for _, kv := range values {
		switch hint := kv.(type) {
		case *dns.SVCBIPv4Hint:
			for _, ip := range hint.Hint {
				if IsBlockedIP(ip) {
					return ip
				}
			}
		case *dns.SVCBIPv6Hint:
			for _, ip := range hint.Hint {
				if IsBlockedIP(ip) {
					return ip
				}
			}
		}
	}
	return nil
}

// NewRebindMiddleware 创建防 DNS 重新绑定攻击流水线中间件
// 借鉴自 blocky (rebinding_resolver.go) 与 AdGuard Home (dnsforward/access.go)
func NewRebindMiddleware(mgr *RebindProtectionManager, cache ...*core.DNSCache) Middleware {
	var c *core.DNSCache
	if len(cache) > 0 {
		c = cache[0]
	}
	// 分组由前置 client 中间件写入上下文；这里只读，不改变中间件签名

	return func(ctx *DNSContext, next func() error) error {
		err := next()
		if mgr == nil || !mgr.IsEnabled() || ctx.Resp == nil || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return err
		}

		// 若前置中间件已经阻断或本身就是错误报文，不需重复处理
		if val, ok := ctx.Get("filter_blocked"); ok && val == true {
			return err
		}

		blockedIP := FindBlockedIPInMsg(ctx.Resp)
		if blockedIP == nil {
			return err
		}

		q := ctx.Req.Question[0]
		domain := strings.Trim(q.Name, ".")
		if mgr.IsDomainAllowed(domain) {
			return err
		}

		// 检测到外部域名解析为内网保留地址，判定为 Rebinding 攻击并执行阻断
		reason := fmt.Sprintf("DNS Rebinding 攻击防护: 外部域名解析为非受信内网 IP (%s)", blockedIP.String())
		ctx.Set("rebinding_blocked", true)
		ctx.Set("filter_action", "block")
		ctx.Set("filter_blocked", true)
		ctx.Set("filter_reason", reason)

		// 同步从缓存中剔除被投毒的记录（按查询所属分组，避免删错键）。
		// 分组来自前置 client 中间件写入的上下文属性，无需解析器参与。
		if c != nil {
			c.RemoveForGroup(ctx.Req, cachedGroup(ctx))
		}

		// 替换为安全的空应答或指定拒绝
		cleanResp := new(dns.Msg)
		cleanResp.SetRcode(ctx.Req, dns.RcodeSuccess)
		cleanResp.Authoritative = true
		cleanResp.RecursionAvailable = true
		ctx.Resp = cleanResp

		return err
	}
}
