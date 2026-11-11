package ipc

import (
	"encoding/json"
	"io"
	"net/http"
)

// handleBlockedServices 处理 /api/v1/filter/services (GET, POST)
//
// GET 返回内置服务目录与当前勾选；POST 更新勾选并热重载规则索引。
func (s *Server) handleBlockedServices(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		res, err := s.controller.GetBlockedServices(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*BlockedServicesResponse]{Success: true, Data: res})

	case http.MethodPost:
		body, err := io.ReadAll(r.Body)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
			return
		}
		var req ConfigureBlockedServicesRequest
		if err := json.Unmarshal(body, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
			return
		}
		if err := s.controller.ConfigureBlockedServices(r.Context(), req); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		// 回传更新后的完整状态，避免前端为刷新计数再发一次 GET
		res, err := s.controller.GetBlockedServices(r.Context())
		if err != nil {
			writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "应用拦截配置已更新"})
			return
		}
		writeJSON(w, http.StatusOK, Response[*BlockedServicesResponse]{Success: true, Data: res})

	default:
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET, POST 请求"})
	}
}
