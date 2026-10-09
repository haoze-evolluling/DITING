package ipc

import (
	"encoding/json"
	"io"
	"io/fs"
	"mime"
	"net"
	"net/http"
	"path"
	"path/filepath"
	"strings"
)

// SetAssetsFS 设置嵌入的 Web 前端静态文件系统
func (s *Server) SetAssetsFS(assets fs.FS) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.assetsFS = assets
}

// handleStaticSPA 托管前端单页应用 (SPA)，支持静态资源分发与 HTML5 History 路由回退
func (s *Server) handleStaticSPA(w http.ResponseWriter, r *http.Request) {
	// 拦截未匹配的 /api/ 路由，返回标准 JSON 404
	if strings.HasPrefix(r.URL.Path, "/api/") {
		writeJSON(w, http.StatusNotFound, Response[any]{
			Success: false,
			Error:   "api endpoint not found",
		})
		return
	}

	s.mu.RLock()
	assets := s.assetsFS
	s.mu.RUnlock()

	if assets == nil {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>谛听 DNS</title></head><body style="font-family:sans-serif;text-align:center;padding:50px;"><h2>谛听 (DITING) 服务运行中</h2><p>未加载前端静态资源包</p></body></html>`))
		return
	}

	reqPath := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
	if reqPath == "" || reqPath == "." {
		reqPath = "index.html"
	}

	// 尝试在静态资源中查找目标文件
	f, err := assets.Open(reqPath)
	if err != nil {
		// 文件不存在，回退至 index.html 以支撑 SPA 前端路由
		serveIndexHTML(w, assets)
		return
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil || stat.IsDir() {
		serveIndexHTML(w, assets)
		return
	}

	// 针对带哈希指纹的 assets 静态文件开启长期高效缓存
	ext := filepath.Ext(reqPath)
	ctype := mime.TypeByExtension(ext)
	if ctype == "" {
		if ext == ".woff2" {
			ctype = "font/woff2"
		} else {
			ctype = "application/octet-stream"
		}
	}
	w.Header().Set("Content-Type", ctype)

	if strings.HasPrefix(reqPath, "assets/") {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	} else if reqPath == "index.html" {
		w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	}

	if rs, ok := f.(io.ReadSeeker); ok {
		http.ServeContent(w, r, reqPath, stat.ModTime(), rs)
	} else {
		_, _ = io.Copy(w, f)
	}
}

func serveIndexHTML(w http.ResponseWriter, assets fs.FS) {
	idxFile, err := assets.Open("index.html")
	if err != nil {
		http.Error(w, "index.html not found", http.StatusNotFound)
		return
	}
	defer idxFile.Close()

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	_, _ = io.Copy(w, idxFile)
}

func getClientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		if len(parts) > 0 {
			return strings.TrimSpace(parts[0])
		}
	}
	if xrip := r.Header.Get("X-Real-IP"); xrip != "" {
		return strings.TrimSpace(xrip)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

// handleAuthStatus 获取当前认证与 Web 服务概览
func (s *Server) handleAuthStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	status, err := s.controller.GetAuthStatus(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*AuthStatusResponse]{Success: true, Data: status})
}

// handleAuthLogin 处理管理员账号登录
func (s *Server) handleAuthLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "无效的请求格式: " + err.Error()})
		return
	}

	clientIP := getClientIP(r)
	resp, err := s.controller.Login(r.Context(), req, clientIP)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*LoginResponse]{Success: true, Data: resp})
}

// handleAuthLogout 处理管理员退出登录
func (s *Server) handleAuthLogout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	token := extractToken(r)
	_ = s.controller.Logout(r.Context(), token)
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "已成功注销登录会话"})
}

// handleAuthSetup 首次初始化管理员账号密码
func (s *Server) handleAuthSetup(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req SetupAuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "无效的请求格式: " + err.Error()})
		return
	}
	if err := s.controller.SetupAuth(r.Context(), req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "管理员账号初始化成功！"})
}

// handleAuthPassword 修改管理员密码
func (s *Server) handleAuthPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req ChangePasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "无效的请求格式: " + err.Error()})
		return
	}

	// 检查是否为受信任本地 IPC 免验原密调用
	token := extractToken(r)
	bypassOldAuth := (s.token != "" && token == s.token) || (s.token == "" && isLoopbackRequest(r))

	if err := s.controller.ChangePassword(r.Context(), req, bypassOldAuth); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "管理员密码修改成功！已有外部会话已失效。"})
}

// handleWebStatus 获取局域网 Web 远程管理状态及访问地址列表
func (s *Server) handleWebStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	status, err := s.controller.GetWebStatus(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*WebStatusResponse]{Success: true, Data: status})
}

// handleWebConfigure 启用或配置局域网 Web 远程管理
func (s *Server) handleWebConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req ConfigureWebRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "无效的请求格式: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureWeb(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "局域网 Web 远程管理配置已保存并生效"})
}

// handleWebFirewall 配置 Web 端口 Windows 防火墙规则
func (s *Server) handleWebFirewall(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req ConfigureFirewallRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "无效的请求格式: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureWebFirewall(r.Context(), req.Enable); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	msg := "已清除 Web 端口防火墙规则"
	if req.Enable {
		msg = "已成功放行 Web 端口防火墙入站规则"
	}
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: msg})
}

func extractToken(r *http.Request) string {
	authHeader := r.Header.Get("Authorization")
	if strings.HasPrefix(authHeader, "Bearer ") {
		return strings.TrimPrefix(authHeader, "Bearer ")
	}
	if t := r.Header.Get("X-API-Token"); t != "" {
		return t
	}
	return r.URL.Query().Get("token")
}
