package ipc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/platform"
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
	s.registerRoutes(mux)

	network := "tcp"
	if strings.HasPrefix(s.addr, "0.0.0.0:") || strings.HasPrefix(s.addr, "127.0.0.1:") {
		network = "tcp4"
	}
	ln, err := net.Listen(network, s.addr)
	if err != nil {
		return fmt.Errorf("绑定 IPC 端口失败 (%s): %w", s.addr, err)
	}

	s.mu.Lock()
	s.listener = ln
	s.httpServer = &http.Server{
		Handler:      corsMiddleware(bodyLimitMiddleware(mux)),
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

// maxRequestBodyBytes 单个管理 API 请求体的硬上限。
//
// 最大的合法请求体是 DNS 区文本（业务上限 1 MiB），留出余量取 4 MiB。
// 统一在此处截断，避免各 handler 自行 io.ReadAll / json.NewDecoder 时
// 把任意大小的请求体整块读入内存（服务与 DNS 核心同进程）。
const maxRequestBodyBytes = 4 << 20

// bodyLimitMiddleware 为所有请求套上统一尺寸闸门。
func bodyLimitMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, maxRequestBodyBytes)
		}
		next.ServeHTTP(w, r)
	})
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
	//
	// 回环地址本身不足以证明来源可信：浏览器中的任意网页访问 127.0.0.1 时
	// RemoteAddr 同样是回环。因此还要求请求不带跨站 Origin（受信来源见
	// isTrustedOrigin），杜绝恶意网页借助本机回环绕过鉴权。
	if s.token == "" && isLoopbackRequest(r) && isTrustedOrigin(r) {
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
		var pErr *platform.PortConflictError
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
		var pErr *platform.PortConflictError
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
	writeJSON(w, http.StatusOK, Response[[]platform.AdapterInfo]{Success: true, Data: adapters})
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
	if r.Method == http.MethodGet {
		cfg, err := s.controller.GetUpstreamConfig(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*core.ResolverConfig]{Success: true, Data: cfg})
		return
	}

	if r.Method == http.MethodPost {
		var req ConfigureUpstreamRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
			return
		}
		if err := s.controller.ConfigureUpstream(r.Context(), req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
			return
		}
		s.Broadcast(Event{Type: "upstream", Timestamp: time.Now().UnixMilli(), Data: "configured"})
		writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "上游配置已成功更新"})
		return
	}

	writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET / POST 请求"})
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

// handleMeta 返回宿主机运行平台信息（免鉴权，供 Web 控制台在登录前判定 OS）。
func (s *Server) handleMeta(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	writeJSON(w, http.StatusOK, Response[MetaResponse]{Success: true, Data: MetaResponse{OS: runtime.GOOS}})
}

func writeJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(payload)
}
