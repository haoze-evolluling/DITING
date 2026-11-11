package ipc

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"

	"github.com/haoze-evolluling/diting/server/internal/querylog"
)

// parseSearchQuery 从 URL 查询参数解析查询历史检索条件
func parseSearchQuery(r *http.Request) querylog.SearchQuery {
	q := r.URL.Query()
	sq := querylog.SearchQuery{
		Domain: q.Get("domain"),
		Client: q.Get("client"),
		QType:  q.Get("qtype"),
		RCode:  q.Get("rcode"),
		Status: q.Get("status"),
		// 缺省即回退扫描落盘历史；显式传 0/false 才关闭
		IncludeFile: q.Get("includeFile") != "0" && q.Get("includeFile") != "false",
	}
	if v := q.Get("startMs"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			sq.StartMs = n
		}
	}
	if v := q.Get("endMs"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			sq.EndMs = n
		}
	}
	if v := q.Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			sq.Limit = n
		}
	}
	if v := q.Get("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			sq.Offset = n
		}
	}
	return sq
}

// handleQueryLogSearch 处理 GET /api/v1/querylog/search
func (s *Server) handleQueryLogSearch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	res, err := s.controller.GetQueryLog(r.Context(), parseSearchQuery(r))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*querylog.SearchResult]{Success: true, Data: res})
}

// handleQueryLogStats 处理 GET /api/v1/querylog/stats?top=10
func (s *Server) handleQueryLogStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	top, err := s.controller.GetQueryStats(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*QueryStatsResponse]{Success: true, Data: top})
}

// handleQueryLogClear 处理 POST /api/v1/querylog/clear
func (s *Server) handleQueryLogClear(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	if err := s.controller.ClearQueryLog(r.Context()); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[string]{
		Success: true,
		Message: "查询历史与统计已成功清空",
	})
}

// handleQueryLogConfig 处理 GET / POST /api/v1/querylog/config
func (s *Server) handleQueryLogConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		cfg, err := s.controller.GetQueryLogConfig(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*querylog.QueryLogConfig]{Success: true, Data: cfg})
		return
	}

	if r.Method == http.MethodPost {
		currentCfg, err := s.controller.GetQueryLogConfig(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		merged := *currentCfg
		bodyBytes, err := io.ReadAll(io.LimitReader(r.Body, 65536))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败: " + err.Error()})
			return
		}
		if err := json.Unmarshal(bodyBytes, &merged); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析查询日志配置请求体失败: " + err.Error()})
			return
		}
		if err := s.controller.UpdateQueryLogConfig(r.Context(), merged); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[string]{
			Success: true,
			Message: "查询日志配置已更新并生效",
		})
		return
	}

	writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET / POST 请求"})
}
