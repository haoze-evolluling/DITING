package ipc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

// ServiceController 抽象服务核心控制操作接口
type ServiceController interface {
	StartDNS(ctx context.Context) error
	StopDNS(ctx context.Context) error
	EnableTakeover(ctx context.Context) error
	DisableTakeover(ctx context.Context) error
	GetStatus(ctx context.Context) (*StatusResponse, error)
	CheckPortConflicts(ctx context.Context) (*windows.PortCheckResult, error)
	GetAdapters(ctx context.Context) ([]windows.AdapterInfo, error)
	ConfigureUpstream(ctx context.Context, req ConfigureUpstreamRequest) error
	TestUpstream(ctx context.Context, req TestUpstreamRequest) (*TestUpstreamResponse, error)
	SetAdapterTakeover(ctx context.Context, req AdapterTakeoverRequest) error
	GetCacheStats(ctx context.Context) (*core.CacheStats, error)
	GetCacheEntries(ctx context.Context, query string, limit int) (*CacheEntriesResponse, error)
	GetCacheTopDomains(ctx context.Context, limit int) ([]core.CacheDomainStat, error)
	ClearCache(ctx context.Context) error
	GetCacheConfig(ctx context.Context) (*core.CacheConfig, error)
	UpdateCacheConfig(ctx context.Context, cfg core.CacheConfig) error
	GetFilterStats(ctx context.Context) (*core.FilterStats, error)
	GetFilterConfig(ctx context.Context) (*core.FilterConfig, error)
	UpdateFilterConfig(ctx context.Context, cfg core.FilterConfig) error
	GetFilterLists(ctx context.Context) ([]core.FilterList, error)
	AddFilterList(ctx context.Context, list core.FilterList) error
	UpdateFilterList(ctx context.Context, list core.FilterList) error
	DeleteFilterList(ctx context.Context, id string) error
	RefreshFilterLists(ctx context.Context, id string) error
	GetCustomRules(ctx context.Context) ([]string, error)
	SetCustomRules(ctx context.Context, rules []string) error
	CheckHostRule(ctx context.Context, domain string, qtype uint16) (*core.CheckHostResult, error)
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		// 允许本地进程、GUI 客户端及常规来源连接
		return true
	},
}

// wsClient 表示一个活跃的 WebSocket 订阅客户端
type wsClient struct {
	conn *websocket.Conn
	send chan Event
}

// Server IPC 本地控制 HTTP API 与 WebSocket 服务
type Server struct {
	mu         sync.RWMutex
	addr       string
	token      string
	controller ServiceController
	httpServer *http.Server
	listener   net.Listener

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
	mux.HandleFunc("/api/v1/events", s.handleEvents)
	mux.HandleFunc("/api/v1/portcheck", s.withAuth(s.handlePortCheck))
	mux.HandleFunc("/api/v1/health", s.handleHealth)

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

// Broadcast 推送事件到所有已连接的 WebSocket 订阅端
func (s *Server) Broadcast(evt Event) {
	if evt.Timestamp == 0 {
		evt.Timestamp = time.Now().UnixMilli()
	}
	select {
	case s.broadcast <- evt:
	default:
		// 缓冲区满时丢弃，防止反压阻塞核心 DNS 链路
	}
}

// runHub 集中调度 WebSocket 连接注册、解绑与事件广播
func (s *Server) runHub() {
	for {
		select {
		case <-s.stopCh:
			s.mu.Lock()
			for client := range s.clients {
				close(client.send)
				_ = client.conn.Close()
				delete(s.clients, client)
			}
			s.mu.Unlock()
			return
		case client := <-s.register:
			s.mu.Lock()
			s.clients[client] = true
			s.mu.Unlock()
		case client := <-s.unregister:
			s.mu.Lock()
			if _, ok := s.clients[client]; ok {
				delete(s.clients, client)
				close(client.send)
				_ = client.conn.Close()
			}
			s.mu.Unlock()
		case evt := <-s.broadcast:
			s.mu.RLock()
			for client := range s.clients {
				select {
				case client.send <- evt:
				default:
					// 客户端发送过慢，关闭并注销
					go func(c *wsClient) {
						select {
						case s.unregister <- c:
						case <-s.stopCh:
						}
					}(client)
				}
			}
			s.mu.RUnlock()
		}
	}
}

// withAuth 校验 Bearer Token 或 X-API-Token 请求头
func (s *Server) withAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.token != "" && !s.verifyToken(r) {
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
	if s.token == "" {
		return true
	}
	authHeader := r.Header.Get("Authorization")
	if strings.HasPrefix(authHeader, "Bearer ") {
		token := strings.TrimPrefix(authHeader, "Bearer ")
		if token == s.token {
			return true
		}
	}
	if r.Header.Get("X-API-Token") == s.token {
		return true
	}
	if r.URL.Query().Get("token") == s.token {
		return true
	}
	return false
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

func (s *Server) handlePortCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	result, err := s.controller.CheckPortConflicts(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*windows.PortCheckResult]{Success: true, Data: result})
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

func (s *Server) handleEvents(w http.ResponseWriter, r *http.Request) {
	if s.token != "" && !s.verifyToken(r) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}

	client := &wsClient{
		conn: conn,
		send: make(chan Event, 64),
	}

	select {
	case s.register <- client:
	case <-s.stopCh:
		_ = conn.Close()
		return
	}

	go s.writePump(client)
	go s.readPump(client)
}

func (s *Server) readPump(c *wsClient) {
	defer func() {
		select {
		case s.unregister <- c:
		case <-s.stopCh:
		}
	}()
	c.conn.SetReadLimit(512)
	_ = c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		_ = c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})
	for {
		if _, _, err := c.conn.ReadMessage(); err != nil {
			break
		}
	}
}

func (s *Server) writePump(c *wsClient) {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		_ = c.conn.Close()
	}()

	for {
		select {
		case evt, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if !ok {
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			data, err := json.Marshal(evt)
			if err != nil {
				continue
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, data); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func writeJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(payload)
}
