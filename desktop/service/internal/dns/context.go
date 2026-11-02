package dns

import (
	"context"
	"net"
	"strconv"
	"time"

	"github.com/miekg/dns"
)

// attrClientGroup 为上下文中的客户端分组属性键。
//
// 由 client 中间件在流水线早期写入，被规则过滤与缓存键共同消费。
// 集中定义可避免读写两侧的字符串字面量漂移。
const attrClientGroup = "client_group"

// attrClientID 为加密入口识别出的 ClientID 属性键。
//
// ClientID 来自 DoT 的 SNI（`<ClientID>.<服务器名>`）或 DoH 的路径段，是
// 同一台设备换个 IP 之后仍能认出来的稳定身份，因此比 client_group
// （按 IP 网段划分）更适合做身份归属。
const attrClientID = "client_id"

// applyEncryptedClientID 解析本次查询的 ClientID 并写入上下文。
//
// DoH 的路径段优先于 DoT 的 SNI：路径是用户在客户端里逐字填进去的，
// 而 SNI 往往是客户端自己挑的默认值，两者都以路径为准更贴近用户意图。
//
// 服务器名未配置时只能靠路径，因为此时无从判断 SNI 是否多写了一级标签，
// 凭空取一层会把正常访问归类成某个并不存在的客户端。
func applyEncryptedClientID(ctx *DNSContext, origin queryOrigin, hostSNI string) {
	if ctx == nil {
		return
	}

	id := origin.PathClientID
	if id == "" {
		id = ClientIDFromServerName(hostSNI, origin.ServerName)
	}
	if id == "" {
		return
	}
	ctx.ClientID = id
	ctx.Set(attrClientID, id)
}

// DNSContext 封装单个 DNS 查询的执行上下文与状态信息
type DNSContext struct {
	Context    context.Context
	Req        *dns.Msg
	Resp       *dns.Msg
	ClientIP   net.IP
	ClientPort int
	ClientName string // 客户端主机名或友好别名（如 localhost、MacBook-Pro）
	// ClientID 加密入口识别出的客户端标识（DoT 的 SNI / DoH 的路径段）；
	// 明文入口为空串。同一设备换 IP 后仍可辨认，故优先于 IP 归属。
	ClientID   string
	Protocol   string // "udp" / "tcp" / "tcp-tls"
	StartTime  time.Time
	Attributes map[string]any
	Err        error
}

// NewDNSContext 创建 DNS 查询上下文
func NewDNSContext(ctx context.Context, req *dns.Msg, clientAddr net.Addr, protocol string) *DNSContext {
	if ctx == nil {
		ctx = context.Background()
	}

	var clientIP net.IP
	var clientPort int

	if clientAddr != nil {
		switch addr := clientAddr.(type) {
		case *net.UDPAddr:
			clientIP = addr.IP
			clientPort = addr.Port
		case *net.TCPAddr:
			clientIP = addr.IP
			clientPort = addr.Port
		default:
			if host, portStr, err := net.SplitHostPort(clientAddr.String()); err == nil {
				clientIP = net.ParseIP(host)
				if p, pErr := strconv.Atoi(portStr); pErr == nil {
					clientPort = p
				}
			}
		}
	}

	return &DNSContext{
		Context:    ctx,
		Req:        req,
		ClientIP:   clientIP,
		ClientPort: clientPort,
		Protocol:   protocol,
		StartTime:  time.Now(),
		Attributes: make(map[string]any),
	}
}

// Duration 计算自请求接收起的耗时
func (c *DNSContext) Duration() time.Duration {
	return time.Since(c.StartTime)
}

// Set 设置上下文扩展属性
func (c *DNSContext) Set(key string, val any) {
	if c.Attributes == nil {
		c.Attributes = make(map[string]any)
	}
	c.Attributes[key] = val
}

// Get 读取上下文扩展属性
func (c *DNSContext) Get(key string) (any, bool) {
	if c.Attributes == nil {
		return nil, false
	}
	val, ok := c.Attributes[key]
	return val, ok
}
