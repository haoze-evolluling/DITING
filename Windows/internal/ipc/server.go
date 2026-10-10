package ipc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

// Server IPC 本地控制 HTTP API 与 WebSocket 服务
type Server struct {
	mu         sync.RWMutex
	addr       string
	token      string
	controller ServiceController
	httpServer *http.Server
	listener   net.Listener
	assetsFS   fs.FS

	clients    map[*wsClient]bool
	register   chan *wsClient
	unregister chan *wsClient
	broadcast  chan Event

	stopCh chan struct{}
}

// NewServer 创建 IPC 服务实例
func NewServer(addr, token string, controller ServiceController) *Server {
	if addr == "" {
		addr = "127.0.0.1:15353"
	}
	return &Server{
		addr:       addr,
		token:      token,
		controller: controller,
		clients:    make(map[*wsClient]bool),
		register:   make(chan *wsClient),
		unregister: make(chan *wsClient),
		broadcast:  make(chan Event, 256),
		stopCh:     make(chan struct{}),
	}
}

// Addr 返回当前实际监听地址（若使用随机端口可获取真实端口）
func (s *Server) Addr() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.listener != nil {
		return s.listener.Addr().String()
	}
	return s.addr
}

// Start 启动 HTTP 及 WebSocket 服务
func (s *Server) Start() error {
	mux := http.NewServeMux()

	mux.HandleFunc("/api/v1/dns/start", s.withAuth(s.handleDNSStart))
	mux.HandleFunc("/api/v1/dns/stop", s.withAuth(s.handleDNSStop))
	mux.HandleFunc("/api/v1/takeover/enable", s.withAuth(s.handleTakeoverEnable))
	mux.HandleFunc("/api/v1/takeover/disable", s.withAuth(s.handleTakeoverDisable))
	mux.HandleFunc("/api/v1/status", s.withAuth(s.handleStatus))
	mux.HandleFunc("/api/v1/adapters", s.withAuth(s.handleAdapters))
	mux.HandleFunc("/api/v1/takeover/adapter", s.withAuth(s.handleAdapterTakeover))
	mux.HandleFunc("/api/v1/upstream/configure", s.withAuth(s.handleUpstreamConfigure))
	mux.HandleFunc("/api/v1/upstream/test", s.withAuth(s.handleUpstreamTest))
	mux.HandleFunc("/api/v1/bootstrap/configure", s.withAuth(s.handleBootstrapConfigure))
	mux.HandleFunc("/api/v1/cache/stats", s.withAuth(s.handleCacheStats))
	mux.HandleFunc("/api/v1/cache/entries", s.withAuth(s.handleCacheEntries))
	mux.HandleFunc("/api/v1/cache/top", s.withAuth(s.handleCacheTop))
	mux.HandleFunc("/api/v1/cache/clear", s.withAuth(s.handleCacheClear))
	mux.HandleFunc("/api/v1/cache/config", s.withAuth(s.handleCacheConfig))
	mux.HandleFunc("/api/v1/filter/stats", s.withAuth(s.handleFilterStats))
	mux.HandleFunc("/api/v1/filter/config", s.withAuth(s.handleFilterConfig))
	mux.HandleFunc("/api/v1/filter/lists", s.withAuth(s.handleFilterLists))
	mux.HandleFunc("/api/v1/filter/lists/add", s.withAuth(s.handleFilterListAdd))
	mux.HandleFunc("/api/v1/filter/lists/update", s.withAuth(s.handleFilterListUpdate))
	mux.HandleFunc("/api/v1/filter/lists/delete", s.withAuth(s.handleFilterListDelete))
	mux.HandleFunc("/api/v1/filter/lists/refresh", s.withAuth(s.handleFilterListRefresh))
	mux.HandleFunc("/api/v1/filter/rules", s.withAuth(s.handleFilterRules))
	mux.HandleFunc("/api/v1/filter/check", s.withAuth(s.handleFilterCheck))
	mux.HandleFunc("/api/v1/dns/lan", s.withAuth(s.handleLANStatus))
	mux.HandleFunc("/api/v1/dns/lan/configure", s.withAuth(s.handleLANConfigure))
	mux.HandleFunc("/api/v1/dns/lan/firewall", s.withAuth(s.handleFirewallConfigure))
	mux.HandleFunc("/api/v1/events", s.handleEvents)
	mux.HandleFunc("/api/v1/portcheck", s.withAuth(s.handlePortCheck))
	mux.HandleFunc("/api/v1/portcheck/autofix", s.withAuth(s.handlePortAutofix))
	mux.HandleFunc("/api/v1/health", s.handleHealth)

	// Web 远程管理与认证路由
	mux.HandleFunc("/api/v1/auth/status", s.handleAuthStatus)
	mux.HandleFunc("/api/v1/auth/login", s.handleAuthLogin)
	mux.HandleFunc("/api/v1/auth/logout", s.withAuth(s.handleAuthLogout))
	mux.HandleFunc("/api/v1/auth/setup", s.handleAuthSetup)
	mux.HandleFunc("/api/v1/auth/password", s.withAuth(s.handleAuthPassword))
	mux.HandleFunc("/api/v1/web/status", s.withAuth(s.handleWebStatus))
	mux.HandleFunc("/api/v1/web/configure", s.withAuth(s.handleWebConfigure))
	mux.HandleFunc("/api/v1/web/firewall", s.withAuth(s.handleWebFirewall))

	// SPA 静态资源路由回退
	mux.HandleFunc("/", s.handleStaticSPA)

	ln, err := net.Listen("tcp", s.addr)
	if err != nil {
		return fmt.Errorf("绑定 IPC 端口失败 (%s): %w", s.addr, err)
	}

	s.mu.Lock()
	s.listener = ln
	s.httpServer = &http.Server{
		Handler:      corsMiddleware(mux),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}
	s.mu.Unlock()

	go s.runHub()
	go func() {
		_ = s.httpServer.Serve(ln)
	}()

	return nil
}

// Shutdown 优雅关闭 IPC 服务
func (s *Server) Shutdown(ctx context.Context) error {
	s.mu.Lock()
	select {
	case <-s.stopCh:
	default:
		close(s.stopCh)
	}
	httpSrv := s.httpServer
	s.mu.Unlock()

	if httpSrv != nil {
		return httpSrv.Shutdown(ctx)
	}
	return nil
}

// withAuth 校验 Bearer Token、X-API-Token 或 Web 会话凭证
func (s *Server) withAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.verifyToken(r) {
			writeJSON(w, http.StatusUnauthorized, Response[any]{
				Success: false,
				Error:   "unauthorized: missing or invalid authentication token",
			})
			return
		}
		next(w, r)
	}
}

func (s *Server) verifyToken(r *http.Request) bool {
	token := extractToken(r)

	// 1. 若匹配本地 IPC 专用凭据，直接放行
	if s.token != "" && token == s.token {
		return true
	}

	// 2. 若匹配有效的 Web 登录会话 Token，放行
	if token != "" && s.controller != nil && s.controller.ValidateSession(token) {
		return true
	}

	// 3. 本地回环免密直连 (来自本机 127.0.0.1 或 [::1] 且未强制配置专用 IPC 密钥)
	if s.token == "" && isLoopbackRequest(r) {
		return true
	}

	return false
}

func isLoopbackRequest(r *http.Request) bool {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func (s *Server) handleDNSStart(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	if err := s.controller.StartDNS(r.Context()); err != nil {
		var pErr *windows.PortConflictError
		if errors.As(err, &pErr) {
			writeJSON(w, http.StatusConflict, Response[any]{
				Success:  false,
				Error:    pErr.Error(),
				Conflict: pErr.Result,
			})
			return
		}
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.Broadcast(Event{Type: "dns", Timestamp: time.Now().UnixMilli(), Data: "started"})
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "DNS 服务已成功启动"})
}

func (s *Server) handleDNSStop(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	if err := s.controller.StopDNS(r.Context()); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.Broadcast(Event{Type: "dns", Timestamp: time.Now().UnixMilli(), Data: "stopped"})
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "DNS 服务已停止"})
}

func (s *Server) handleTakeoverEnable(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	if err := s.controller.EnableTakeover(r.Context()); err != nil {
		var pErr *windows.PortConflictError
		if errors.As(err, &pErr) {
			writeJSON(w, http.StatusConflict, Response[any]{
				Success:  false,
				Error:    pErr.Error(),
				Conflict: pErr.Result,
			})
			return
		}
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.Broadcast(Event{Type: "takeover", Timestamp: time.Now().UnixMilli(), Data: "enabled"})
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "物理网卡 DNS 已成功接管"})
}

func (s *Server) handleTakeoverDisable(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	if err := s.controller.DisableTakeover(r.Context()); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.Broadcast(Event{Type: "takeover", Timestamp: time.Now().UnixMilli(), Data: "disabled"})
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "系统 DNS 接管已还原"})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	status, err := s.controller.GetStatus(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*StatusResponse]{Success: true, Data: status})
}

func (s *Server) handleAdapters(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	adapters, err := s.controller.GetAdapters(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[[]windows.AdapterInfo]{Success: true, Data: adapters})
}

func (s *Server) handleAdapterTakeover(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req AdapterTakeoverRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	if err := s.controller.SetAdapterTakeover(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.Broadcast(Event{Type: "takeover", Timestamp: time.Now().UnixMilli(), Data: req})
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "网卡接管状态已更新"})
}

func (s *Server) handleUpstreamConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req ConfigureUpstreamRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	if err := s.controller.ConfigureUpstream(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.Broadcast(Event{Type: "upstream", Timestamp: time.Now().UnixMilli(), Data: "configured"})
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "上游配置已成功更新"})
}

func (s *Server) handleUpstreamTest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req TestUpstreamRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	res, err := s.controller.TestUpstream(r.Context(), req)
	if err != nil {
		writeJSON(w, http.StatusOK, Response[*TestUpstreamResponse]{Success: false, Error: err.Error(), Data: res})
		return
	}
	writeJSON(w, http.StatusOK, Response[*TestUpstreamResponse]{Success: true, Data: res})
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, Response[string]{Success: true, Data: "ok"})
}

func writeJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(payload)
}
