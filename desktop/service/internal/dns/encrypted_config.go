package dns

import (
	"crypto/tls"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// DoT 的默认参数。读超时沿用明文 TCP 的量级，空闲超时放宽到 30 秒：
// 加密客户端普遍维持长连接，用明文那样的短空闲窗口会让它们反复重握手。
const (
	DefaultDoTReadTimeout = 5 * time.Second
	DefaultDoTIdleTimeout = 30 * time.Second
)

// queryOrigin 描述一次查询从哪个入口进来，以及入口能提供的身份线索。
//
// 集中成一个结构体而不是继续加参数：每接一种加密协议都要多带一两个
// 只有它自己用得上的字段（SNI、DoH 路径段），散在参数列表里会让每个
// 调用点都得知道别的协议长什么样。
type queryOrigin struct {
	// Protocol 写入 DNSContext：udp / tcp / tcp-tls / doh / doq
	Protocol string
	// ServerName 为 DoT 握手给出的 SNI
	ServerName string
	// PathClientID 为 DoH 路径段里带的 ClientID
	PathClientID string
}

// EncryptedServerConfig 加密 DNS 监听配置。
//
// 与 core.EncryptedDNSConfig 分开：那是「用户配置了什么」的持久化形态，
// 这里是「本次要监听什么」的运行形态。证书已经由 CertManager 载入成
// *tls.Config，配置里不再出现任何文件路径。
type EncryptedServerConfig struct {
	DoTEnabled bool
	DoHEnabled bool
	DoQEnabled bool
	// ListenAddress 为空表示所有网卡；端口取自 core.EncryptedDNSConfig
	ListenAddress string
	DoTPort       int
	DoHPort       int
	DoQPort       int
	// DoHPath 为 DoH 的请求路径，缺省 /dns-query
	DoHPath string
	// ServerName 用于从 SNI 中剥离 ClientID
	ServerName string
	// TLSConfig 已载入服务端证书；为 nil 时不监听任何加密端口
	TLSConfig *tls.Config
	// TrustedProxy 在 DoH 位于反向代理之后时还原真实客户端 IP；
	// nil 表示不信任任何转发头（默认）
	TrustedProxy *TrustedProxy
	// ReadTimeout / IdleTimeout 见上方默认值
	ReadTimeout time.Duration
	IdleTimeout time.Duration
}

// DoTListenAddress 返回 DoT 的监听地址，形如 0.0.0.0:853。
//
// 空监听地址必须展开成 0.0.0.0 而不是交给 net.Listen 当 "": 后者在部分
// 平台上会同时抢 v4/v6 通配地址，与明文 DNS 已有的 [::] 监听撞车。
func (c EncryptedServerConfig) DoTListenAddress() string {
	host := strings.TrimSpace(c.ListenAddress)
	if host == "" {
		host = "0.0.0.0"
	}
	port := c.DoTPort
	if port <= 0 || port > 65535 {
		port = core.DefaultDoTPort
	}
	return net.JoinHostPort(host, strconv.Itoa(port))
}

// DoHListenAddress 返回 DoH 的监听地址，形如 0.0.0.0:443。
func (c EncryptedServerConfig) DoHListenAddress() string {
	host := strings.TrimSpace(c.ListenAddress)
	if host == "" {
		host = "0.0.0.0"
	}
	port := c.DoHPort
	if port <= 0 || port > 65535 {
		port = core.DefaultDoHPort
	}
	return net.JoinHostPort(host, strconv.Itoa(port))
}

// DoQListenAddress 返回 DoQ 的监听地址，形如 0.0.0.0:853。
//
// DoQ 跑在 UDP 上，与 DoT 默认同为 853 并不冲突：两者分属不同传输层，
// 端口空间本来就是分开的。
func (c EncryptedServerConfig) DoQListenAddress() string {
	host := strings.TrimSpace(c.ListenAddress)
	if host == "" {
		host = "0.0.0.0"
	}
	port := c.DoQPort
	if port <= 0 || port > 65535 {
		port = core.DefaultDoQPort
	}
	return net.JoinHostPort(host, strconv.Itoa(port))
}

// Validate 校验监听配置是否足以开工。
//
// 只校验「已启用」协议自己的端口：换证书重载时可能只开 DoT，
// 此时 DoHPort 还是零值，一并校验会让合法的单项配置起不来。
func (c EncryptedServerConfig) Validate() error {
	if c.DoTEnabled && (c.DoTPort <= 0 || c.DoTPort > 65535) {
		return fmt.Errorf("DoT 端口 %d 非法", c.DoTPort)
	}
	if c.DoHEnabled && (c.DoHPort <= 0 || c.DoHPort > 65535) {
		return fmt.Errorf("DoH 端口 %d 非法", c.DoHPort)
	}
	if c.DoQEnabled && (c.DoQPort <= 0 || c.DoQPort > 65535) {
		return fmt.Errorf("DoQ 端口 %d 非法", c.DoQPort)
	}
	if c.ListenAddress != "" {
		if ip := net.ParseIP(strings.TrimSpace(c.ListenAddress)); ip == nil {
			return fmt.Errorf("监听地址 %q 不是合法 IP", c.ListenAddress)
		}
	}
	return nil
}
