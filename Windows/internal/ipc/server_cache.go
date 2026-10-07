package ipc

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"

	"github.com/haoze-evolluling/diting/windows/internal/core"
)

// handleCacheStats 处理 GET /api/v1/cache/stats
func (s *Server) handleCacheStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	stats, err := s.controller.GetCacheStats(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*core.CacheStats]{
		Success: true,
		Data:    stats,
	})
}

// handleCacheEntries 处理 GET /api/v1/cache/entries?query=...&limit=...
func (s *Server) handleCacheEntries(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	query := r.URL.Query().Get("query")
	limitStr := r.URL.Query().Get("limit")
	limit := 100
	if limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 {
			limit = l
		}
	}

	res, err := s.controller.GetCacheEntries(r.Context(), query, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*CacheEntriesResponse]{
		Success: true,
		Data:    res,
	})
}

// handleCacheTop 处理 GET /api/v1/cache/top?limit=...
func (s *Server) handleCacheTop(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	limitStr := r.URL.Query().Get("limit")
	limit := 10
	if limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 {
			limit = l
		}
	}

	top, err := s.controller.GetCacheTopDomains(r.Context(), limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[[]core.CacheDomainStat]{
		Success: true,
		Data:    top,
	})
}

// handleCacheClear 处理 POST /api/v1/cache/clear
func (s *Server) handleCacheClear(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	if err := s.controller.ClearCache(r.Context()); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[string]{
		Success: true,
		Message: "智能缓存已成功清空",
	})
}

// handleCacheConfig 处理 GET / POST /api/v1/cache/config
func (s *Server) handleCacheConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		cfg, err := s.controller.GetCacheConfig(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*core.CacheConfig]{
			Success: true,
			Data:    cfg,
		})
		return
	}

	if r.Method == http.MethodPost {
		currentCfg, err := s.controller.GetCacheConfig(r.Context())
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
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析缓存配置请求体失败: " + err.Error()})
			return
		}
		if err := s.controller.UpdateCacheConfig(r.Context(), merged); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[string]{
			Success: true,
			Message: "智能缓存配置已更新并生效",
		})
		return
	}

	writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET / POST 请求"})
}
