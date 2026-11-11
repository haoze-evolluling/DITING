package ipc

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// handleSafeSearch 处理 /api/v1/safesearch/config
//
// GET  读取当前强制安全搜索配置
// POST 更新配置（总开关 / 服务商黑名单 / TTL）
//
// 借鉴 AdGuard Home internal/filtering/safesearch 的服务商分类与强制重写语义。
func (s *Server) handleSafeSearch(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		res, err := s.controller.GetSafeSearch(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*SafeSearchConfigResponse]{Success: true, Data: res})
	case http.MethodPost:
		body, err := io.ReadAll(io.LimitReader(r.Body, 64*1024))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败: " + err.Error()})
			return
		}
		var req ConfigureSafeSearchRequest
		if err := json.Unmarshal(body, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析安全搜索配置失败: " + err.Error()})
			return
		}
		if err := s.controller.ConfigureSafeSearch(r.Context(), req); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		s.Broadcast(Event{Type: "safesearch", Data: "configured"})
		writeJSON(w, http.StatusOK, Response[string]{Success: true, Message: "强制安全搜索配置已更新"})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET / POST 请求"})
	}
}

// normalizeSafeSearchDisabled 过滤非法服务商标识并去重，保持稳定顺序。
func normalizeSafeSearchDisabled(list []string) []string {
	valid := make(map[string]bool)
	for _, s := range core.SafeSearchServices() {
		valid[s] = true
	}
	seen := make(map[string]bool)
	out := make([]string, 0, len(list))
	for _, s := range list {
		if !valid[s] || seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
	}
	return out
}
