package ipc

import (
	"encoding/json"
	"io"
	"net/http"
)

// handleClientGroups 处理 GET / POST /api/v1/clients/groups
func (s *Server) handleClientGroups(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		res, err := s.controller.GetClientGroups(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*ClientGroupConfigResponse]{Success: true, Data: res})
		return
	}

	if r.Method == http.MethodPost {
		body, err := io.ReadAll(io.LimitReader(r.Body, 256*1024))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败: " + err.Error()})
			return
		}
		var req ConfigureClientGroupsRequest
		if err := json.Unmarshal(body, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析客户端分组配置失败: " + err.Error()})
			return
		}
		if err := s.controller.ConfigureClientGroups(r.Context(), req); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[string]{
			Success: true,
			Message: "客户端分组已更新并生效",
		})
		return
	}

	writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET / POST 请求"})
}
