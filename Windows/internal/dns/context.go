package dns

import (
	"context"
	"net"
	"strconv"
	"time"

	"github.com/miekg/dns"
)

// DNSContext 封装单个 DNS 查询的执行上下文与状态信息
type DNSContext struct {
	Context    context.Context
	Req        *dns.Msg
	Resp       *dns.Msg
	ClientIP   net.IP
	ClientPort int
	Protocol   string // "udp" 或 "tcp"
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
