package dns

import (
	"context"
	"fmt"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
)

// ServerConfig 定义 DNS 本地服务监听配置
type ServerConfig struct {
	UDPAddresses []string      `json:"udpAddresses"`
	TCPAddresses []string      `json:"tcpAddresses"`
	ReadTimeout  time.Duration `json:"readTimeout"`
	WriteTimeout time.Duration `json:"writeTimeout"`
}

// DefaultServerConfig 返回标准默认双栈配置 (127.0.0.1:53 与 [::1]:53)
func DefaultServerConfig() ServerConfig {
	return ServerConfig{
		UDPAddresses: []string{"127.0.0.1:53", "[::1]:53"},
		TCPAddresses: []string{"127.0.0.1:53", "[::1]:53"},
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
	}
}

// Server 基于 miekg/dns 的双栈 UDP/TCP DNS 监听服务
type Server struct {
	mu            sync.Mutex
	config        ServerConfig
	pipeline      *Pipeline
	servers       []*dns.Server
	activeQueries sync.WaitGroup
	started       atomic.Bool
	closed        atomic.Bool
}

// NewServer 创建 DNS 监听服务
func NewServer(config ServerConfig, pipeline *Pipeline) *Server {
	if len(config.UDPAddresses) == 0 && len(config.TCPAddresses) == 0 {
		config = DefaultServerConfig()
	}
	if config.ReadTimeout <= 0 {
		config.ReadTimeout = 5 * time.Second
	}
	if config.WriteTimeout <= 0 {
		config.WriteTimeout = 5 * time.Second
	}

	return &Server{
		config:   config,
		pipeline: pipeline,
	}
}

// Start 启动双栈 UDP/TCP 监听器
func (s *Server) Start() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.started.Load() {
		return fmt.Errorf("server already started")
	}

	servers := make([]*dns.Server, 0)
	boundCount := 0

	// 启动 UDP 监听器
	for _, addr := range s.config.UDPAddresses {
		network := "udp"
		if isIPv6(addr) {
			network = "udp6"
		} else {
			network = "udp4"
		}

		conn, err := net.ListenPacket(network, addr)
		if err != nil {
			// 若 IPv6 地址绑定失败（部分系统禁用 IPv6），容错降级
			if isIPv6(addr) {
				continue
			}
			s.cleanupServers(servers)
			return fmt.Errorf("bind udp %s failed: %w", addr, err)
		}

		udpServer := &dns.Server{
			PacketConn:   conn,
			Handler:      dns.HandlerFunc(s.ServeDNS),
			ReadTimeout:  s.config.ReadTimeout,
			WriteTimeout: s.config.WriteTimeout,
			UDPSize:      dns.MaxMsgSize,
		}
		servers = append(servers, udpServer)
		boundCount++
	}

	// 启动 TCP 监听器
	for _, addr := range s.config.TCPAddresses {
		network := "tcp"
		if isIPv6(addr) {
			network = "tcp6"
		} else {
			network = "tcp4"
		}

		listener, err := net.Listen(network, addr)
		if err != nil {
			if isIPv6(addr) {
				continue
			}
			s.cleanupServers(servers)
			return fmt.Errorf("bind tcp %s failed: %w", addr, err)
		}

		tcpServer := &dns.Server{
			Listener:     listener,
			Handler:      dns.HandlerFunc(s.ServeDNS),
			ReadTimeout:  s.config.ReadTimeout,
			WriteTimeout: s.config.WriteTimeout,
		}
		servers = append(servers, tcpServer)
		boundCount++
	}

	if boundCount == 0 {
		s.cleanupServers(servers)
		return fmt.Errorf("failed to bind any DNS listener (all UDP/TCP listeners failed)")
	}

	s.servers = servers
	s.started.Store(true)
	s.closed.Store(false)

	// 异步激活每个 listener
	for _, srv := range servers {
		go func(server *dns.Server) {
			_ = server.ActivateAndServe()
		}(srv)
	}

	return nil
}

// ServeDNS 处理单次 DNS 协议请求
func (s *Server) ServeDNS(w dns.ResponseWriter, r *dns.Msg) {
	if s.closed.Load() {
		dns.HandleFailed(w, r)
		return
	}

	s.activeQueries.Add(1)
	defer s.activeQueries.Done()

	protocol := "udp"
	if _, ok := w.RemoteAddr().(*net.TCPAddr); ok {
		protocol = "tcp"
	}

	dnsCtx := NewDNSContext(context.Background(), r, w.RemoteAddr(), protocol)

	if s.pipeline != nil {
		_ = s.pipeline.Execute(dnsCtx)
	}

	if dnsCtx.Resp != nil {
		dnsCtx.Resp.Id = r.Id
		_ = w.WriteMsg(dnsCtx.Resp)
	} else {
		dns.HandleFailed(w, r)
	}
}

// Shutdown 优雅关闭监听器并等待进行中请求结束
func (s *Server) Shutdown() error {
	s.mu.Lock()
	if !s.started.Load() || s.closed.Load() {
		s.mu.Unlock()
		return nil
	}
	s.closed.Store(true)
	servers := s.servers
	s.servers = nil
	s.mu.Unlock()

	// 先关闭所有网络监听，拒绝新连接
	s.cleanupServers(servers)

	// 等待活跃请求在超时内完成
	waitCh := make(chan struct{})
	go func() {
		s.activeQueries.Wait()
		close(waitCh)
	}()

	select {
	case <-waitCh:
	case <-time.After(3 * time.Second):
		// 优雅超时强行退出
	}

	return nil
}

func (s *Server) cleanupServers(servers []*dns.Server) {
	for _, srv := range servers {
		if srv != nil {
			_ = srv.Shutdown()
		}
	}
}

func isIPv6(addr string) bool {
	host, _, err := net.SplitHostPort(addr)
	if err == nil {
		ip := net.ParseIP(host)
		return ip != nil && ip.To4() == nil
	}
	ip := net.ParseIP(addr)
	return ip != nil && ip.To4() == nil
}
