package ipc

import (
	"encoding/json"
	"io"
	"net/http"
)

// handleAccessConfigure 处理 POST /api/v1/dns/access/configure
func (s *Server) handleAccessConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigureAccessRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureAccess(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "客户端访问控制配置已成功更新",
	})
}

// handleRateLimitConfigure 处理 POST /api/v1/dns/ratelimit/configure
func (s *Server) handleRateLimitConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigureRateLimitRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureRateLimit(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "客户端请求速率限制配置已成功更新",
	})
}

// handleDNS64Configure 处理 POST /api/v1/dns/dns64/configure
func (s *Server) handleDNS64Configure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigureDNS64Request
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureDNS64(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "DNS64 过渡合成配置已成功更新",
	})
}

// handleUnqualifiedConfigure 处理 POST /api/v1/dns/unqualified/configure
func (s *Server) handleUnqualifiedConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigureBlockUnqualifiedRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureBlockUnqualified(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "单标签域名防外泄配置已成功更新",
	})
}

// handlePrivacyConfigure 处理 POST /api/v1/dns/privacy/configure
func (s *Server) handlePrivacyConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigurePrivacyRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigurePrivacy(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "DNS 隐私与协议增强配置已成功更新",
	})
}

// handleRebindConfigure 处理 POST /api/v1/dns/rebind/configure
func (s *Server) handleRebindConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigureRebindRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureRebind(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "DNS Rebinding 防御配置已成功更新",
	})
}

// handleHostsConfigure 处理 POST /api/v1/dns/hosts/configure
func (s *Server) handleHostsConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigureHostsRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureHosts(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "Hosts 解析器配置已成功更新",
	})
}

