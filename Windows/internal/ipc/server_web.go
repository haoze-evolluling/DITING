package ipc

import (
	"encoding/json"
	"net/http"
)

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
