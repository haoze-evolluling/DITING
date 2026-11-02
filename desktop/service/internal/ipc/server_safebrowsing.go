package ipc

import (
	"encoding/json"
	"io"
	"net/http"
)

// handleSafeBrowsing 处理 /api/v1/filter/safebrowsing (GET, POST)
//
// GET 返回配置与累计统计；POST 更新配置并回传更新后的完整状态。
func (s *Server) handleSafeBrowsing(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		res, err := s.controller.GetSafeBrowsing(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*SafeBrowsingResponse]{Success: true, Data: res})

	case http.MethodPost:
		body, err := io.ReadAll(r.Body)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
			return
		}
		var req ConfigureSafeBrowsingRequest
		if err := json.Unmarshal(body, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
			return
		}
		if err := s.controller.ConfigureSafeBrowsing(r.Context(), req); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		// 回传更新后的状态：归一化可能改写超范围的参数，
		// 让界面立刻看到真正生效的值而不是它填进去的那个
		res, err := s.controller.GetSafeBrowsing(r.Context())
		if err != nil {
			writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "声誉查询配置已更新"})
			return
		}
		writeJSON(w, http.StatusOK, Response[*SafeBrowsingResponse]{Success: true, Data: res})

	default:
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET, POST 请求"})
	}
}
