package ipc

import (
	"encoding/json"
	"io"
	"net/http"
)

// handleFilterSchedule 处理 GET / POST /api/v1/filter/schedule
func (s *Server) handleFilterSchedule(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		res, err := s.controller.GetBlockingSchedule(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*ScheduleConfigResponse]{Success: true, Data: res})
		return
	}

	if r.Method == http.MethodPost {
		body, err := io.ReadAll(io.LimitReader(r.Body, 256*1024))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败: " + err.Error()})
			return
		}
		var req ConfigureScheduleRequest
		if err := json.Unmarshal(body, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析时间计划配置失败: " + err.Error()})
			return
		}
		if err := s.controller.ConfigureBlockingSchedule(r.Context(), req); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[string]{
			Success: true,
			Message: "时间计划已更新并生效",
		})
		return
	}

	writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET / POST 请求"})
}
