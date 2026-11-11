package ipc

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// maxFilterPauseSeconds 定时暂停的时长上限（约 10 年）。
//
// 上限的作用是让「秒数溢出」在入口处变成 400，而不是在 time.Duration
// 乘算后变成负数、被解释成「暂停至手动恢复」。
const maxFilterPauseSeconds int64 = 10 * 365 * 24 * 3600

// handleFilterPause 处理 GET / POST /api/v1/filter/pause
//
// 借鉴 Technitium TemporaryDisableBlocking / pi-hole piholeEnable 的定时暂停语义：
// 暂停为运行时状态，重启服务即恢复拦截。
func (s *Server) handleFilterPause(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		res, err := s.controller.GetFilterPause(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*FilterPauseResponse]{Success: true, Data: res})
		return
	}

	if r.Method == http.MethodPost {
		body, err := io.ReadAll(io.LimitReader(r.Body, 64*1024))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败: " + err.Error()})
			return
		}
		var req FilterPauseRequest
		if err := json.Unmarshal(body, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析暂停请求失败: " + err.Error()})
			return
		}
		// 只有 0 表示「暂停至手动恢复」。负值会被 Duration 乘算/比较吞成同一个
		// 永久暂停分支，秒数大到 int64 溢出（≥ 约 9.22e9）同样如此——合法调用方的
		// 笔误因此静默退化成「永久关过滤」（fail-open），必须显式拒绝。
		if req.Paused && req.DurationSec < 0 {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "durationSec 不能为负数"})
			return
		}
		if req.Paused && req.DurationSec > maxFilterPauseSeconds {
			writeJSON(w, http.StatusBadRequest, Response[any]{
				Success: false,
				Error:   fmt.Sprintf("durationSec 超出上限（最大 %d 秒，约 10 年）", maxFilterPauseSeconds),
			})
			return
		}
		if err := s.controller.SetFilterPause(r.Context(), req); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		msg := "拦截已恢复"
		if req.Paused {
			msg = "拦截已暂停"
		}
		writeJSON(w, http.StatusOK, Response[string]{Success: true, Message: msg})
		return
	}

	writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET / POST 请求"})
}
