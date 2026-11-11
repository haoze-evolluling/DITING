package ipc

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// handleRewriteRules 处理 /api/v1/dns/rewrite/rules (GET, POST, DELETE)
func (s *Server) handleRewriteRules(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		rules, err := s.controller.GetRewriteRules(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[[]core.RewriteRule]{
			Success: true,
			Data:    rules,
		})
	case http.MethodPost:
		body, err := io.ReadAll(r.Body)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
			return
		}
		var rule core.RewriteRule
		if err := json.Unmarshal(body, &rule); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
			return
		}
		if err := s.controller.AddRewriteRule(r.Context(), rule); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[any]{
			Success: true,
			Message: "DNS 重写规则已成功添加或更新",
		})
	case http.MethodDelete:
		domain := r.URL.Query().Get("domain")
		if domain == "" {
			body, _ := io.ReadAll(r.Body)
			var payload struct {
				Domain string `json:"domain"`
			}
			if err := json.Unmarshal(body, &payload); err == nil {
				domain = payload.Domain
			}
		}
		if domain == "" {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "缺少 domain 参数"})
			return
		}
		if err := s.controller.DeleteRewriteRule(r.Context(), domain); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[any]{
			Success: true,
			Message: "DNS 重写规则已成功删除",
		})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET, POST, DELETE 请求"})
	}
}

// handleRewriteConfigure 处理 POST /api/v1/dns/rewrite/configure
func (s *Server) handleRewriteConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigureRewriteRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureRewrite(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "DNS 重写全局配置已成功更新",
	})
}

// handleClients 处理 GET /api/v1/clients 获取已识别的活跃客户端列表
func (s *Server) handleClients(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	clients, err := s.controller.GetClients(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[[]core.ClientInfo]{
		Success: true,
		Data:    clients,
	})
}

// handleClientAlias 处理 POST /api/v1/clients/alias 设置客户端静态友好名称
func (s *Server) handleClientAlias(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigureClientAliasRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureClientAlias(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "客户端别名已成功更新",
	})
}

// handleECSConfigure 处理 POST /api/v1/dns/ecs/configure
func (s *Server) handleECSConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ConfigureECSRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}
	if err := s.controller.ConfigureECS(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[any]{
		Success: true,
		Message: "EDNS Client Subnet 配置已成功更新",
	})
}
