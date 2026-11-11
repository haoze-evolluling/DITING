package ipc

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"time"
)

// handleAuthBackground 处理获取、更新或删除全局自定义登录背景
func (s *Server) handleAuthBackground(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleGetBackground(w, r)
	case http.MethodPost, http.MethodPut:
		s.handleSetBackground(w, r)
	case http.MethodDelete:
		s.handleResetBackground(w, r)
	default:
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
	}
}

// verifyBackgroundPermission 检查修改或删除背景的接口权限
func (s *Server) verifyBackgroundPermission(r *http.Request, passwordInBody string) (bool, error) {
	// 1. 本地回环免密直连或有效 session / IPC token 放行
	if isLoopbackRequest(r) || s.verifyToken(r) {
		return true, nil
	}

	// 2. 若系统尚未初始化管理员账号密码，放行配置
	if s.controller != nil && !s.controller.IsAuthInitialized() {
		return true, nil
	}

	// 3. 远程未登录请求：检查 X-Admin-Password 请求头或请求参数携带的密码
	adminPass := r.Header.Get("X-Admin-Password")
	if adminPass == "" {
		adminPass = passwordInBody
	}
	if adminPass == "" {
		return false, fmt.Errorf("未授权：局域网远程修改全局背景需要验证管理员密码")
	}

	clientIP, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		clientIP = r.RemoteAddr
	}

	if s.controller != nil {
		ok, verifyErr := s.controller.VerifyAdminPasswordWithIP(r.Context(), clientIP, adminPass)
		if verifyErr != nil {
			return false, verifyErr
		}
		if ok {
			return true, nil
		}
	}

	return false, fmt.Errorf("未授权：管理员密码验证失败")
}

// handleGetBackground 获取当前全局登录背景
func (s *Server) handleGetBackground(w http.ResponseWriter, r *http.Request) {
	resp, err := s.controller.GetLoginBackground(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*LoginBackgroundResponse]{Success: true, Data: resp})
}

// handleSetBackground 保存全局登录背景配置（含上传图片）
func (s *Server) handleSetBackground(w http.ResponseWriter, r *http.Request) {
	// 限制请求体最大 15MB，防止超大异常负载
	r.Body = http.MaxBytesReader(w, r.Body, 15*1024*1024)
	var req SetLoginBackgroundRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "无效的请求格式: " + err.Error()})
		return
	}

	if ok, authErr := s.verifyBackgroundPermission(r, req.AdminPassword); !ok {
		writeJSON(w, http.StatusUnauthorized, Response[any]{Success: false, Error: authErr.Error()})
		return
	}

	if err := s.controller.SetLoginBackground(r.Context(), req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}

	// 广播背景更新事件通知所有已连接客户端
	s.Broadcast(Event{
		Type:      "background",
		Timestamp: time.Now().UnixMilli(),
		Data:      "updated",
	})

	resp, _ := s.controller.GetLoginBackground(r.Context())
	writeJSON(w, http.StatusOK, Response[*LoginBackgroundResponse]{
		Success: true,
		Data:    resp,
		Message: "全局登录背景已保存并应用",
	})
}

// handleResetBackground 恢复默认系统背景
func (s *Server) handleResetBackground(w http.ResponseWriter, r *http.Request) {
	adminPass := r.URL.Query().Get("adminPassword")
	if adminPass == "" {
		adminPass = r.Header.Get("X-Admin-Password")
	}
	if ok, authErr := s.verifyBackgroundPermission(r, adminPass); !ok {
		writeJSON(w, http.StatusUnauthorized, Response[any]{Success: false, Error: authErr.Error()})
		return
	}

	if err := s.controller.ResetLoginBackground(r.Context()); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}

	s.Broadcast(Event{
		Type:      "background",
		Timestamp: time.Now().UnixMilli(),
		Data:      "reset",
	})

	resp, _ := s.controller.GetLoginBackground(r.Context())
	writeJSON(w, http.StatusOK, Response[*LoginBackgroundResponse]{
		Success: true,
		Data:    resp,
		Message: "已恢复系统默认背景",
	})
}

// handleAuthBackgroundImage 提供服务端存储的背景图片二进制流
func (s *Server) handleAuthBackgroundImage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}

	data, contentType, modTime, err := s.controller.GetLoginBackgroundImage(r.Context())
	if err != nil {
		http.NotFound(w, r)
		return
	}

	etag := fmt.Sprintf(`"bg-%d-%d"`, len(data), modTime.UnixNano())
	if match := r.Header.Get("If-None-Match"); match == etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("ETag", etag)
	w.Header().Set("Cache-Control", "public, max-age=86400")
	w.Header().Set("Content-Length", fmt.Sprintf("%d", len(data)))

	if r.Method == http.MethodHead {
		w.WriteHeader(http.StatusOK)
		return
	}

	_, _ = w.Write(data)
}
