package ipc

import (
	"net/http"
	"time"
)

// handleCachePersist 处理 GET /api/v1/cache/persist（状态查询）
func (s *Server) handleCachePersist(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	res, err := s.controller.CachePersistStatus(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*CachePersistResponse]{Success: true, Data: res})
}

// handleCacheDump 处理 POST /api/v1/cache/dump（立即落盘）
func (s *Server) handleCacheDump(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	res, err := s.controller.DumpCache(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.Broadcast(Event{Type: "filter", Timestamp: time.Now().UnixMilli(), Data: "cache_dumped"})
	writeJSON(w, http.StatusOK, Response[*CachePersistResponse]{
		Success: true,
		Message: "缓存已落盘",
		Data:    res,
	})
}

// handleCacheLoad 处理 POST /api/v1/cache/load（从落盘文件恢复）
func (s *Server) handleCacheLoad(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	res, err := s.controller.LoadCache(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*CachePersistResponse]{
		Success: true,
		Message: "缓存已从落盘文件恢复",
		Data:    res,
	})
}
