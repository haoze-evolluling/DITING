package ipc

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/miekg/dns"
)

// handleFilterStats 处理 GET /api/v1/filter/stats
func (s *Server) handleFilterStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	stats, err := s.controller.GetFilterStats(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*core.FilterStats]{
		Success: true,
		Data:    stats,
	})
}

// handleFilterConfig 处理 GET / POST /api/v1/filter/config
func (s *Server) handleFilterConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		cfg, err := s.controller.GetFilterConfig(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*core.FilterConfig]{
			Success: true,
			Data:    cfg,
		})
		return
	}

	if r.Method == http.MethodPost {
		currentCfg, err := s.controller.GetFilterConfig(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		merged := *currentCfg
		body, err := io.ReadAll(io.LimitReader(r.Body, 1024*1024))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
			return
		}
		if err := json.Unmarshal(body, &merged); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析配置失败: " + err.Error()})
			return
		}
		if err := s.controller.UpdateFilterConfig(r.Context(), merged); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[string]{
			Success: true,
			Message: "过滤配置已更新生效",
		})
		return
	}

	writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "不支持的 HTTP 方法"})
}

// handleFilterLists 处理 GET /api/v1/filter/lists
func (s *Server) handleFilterLists(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	lists, err := s.controller.GetFilterLists(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*FilterListsResponse]{
		Success: true,
		Data: &FilterListsResponse{
			Total: len(lists),
			Lists: lists,
		},
	})
}

// handleFilterListAdd 处理 POST /api/v1/filter/lists/add
func (s *Server) handleFilterListAdd(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 1024*1024))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var list core.FilterList
	if err := json.Unmarshal(body, &list); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析订阅源失败: " + err.Error()})
		return
	}
	if strings.TrimSpace(list.URL) == "" {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "订阅源 URL 不能为空"})
		return
	}
	if err := s.controller.AddFilterList(r.Context(), list); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[string]{
		Success: true,
		Message: "订阅源已成功添加",
	})
}

// handleFilterListUpdate 处理 POST /api/v1/filter/lists/update
func (s *Server) handleFilterListUpdate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 1024*1024))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var list core.FilterList
	if err := json.Unmarshal(body, &list); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析订阅源失败: " + err.Error()})
		return
	}
	if err := s.controller.UpdateFilterList(r.Context(), list); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[string]{
		Success: true,
		Message: "订阅源已成功更新",
	})
}

// handleFilterListDelete 处理 POST /api/v1/filter/lists/delete
func (s *Server) handleFilterListDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 1024*1024))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req FilterActionRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求失败: " + err.Error()})
		return
	}
	if err := s.controller.DeleteFilterList(r.Context(), req.ID); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[string]{
		Success: true,
		Message: "订阅源已成功删除",
	})
}

// handleFilterListRefresh 处理 POST /api/v1/filter/lists/refresh
func (s *Server) handleFilterListRefresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, _ := io.ReadAll(io.LimitReader(r.Body, 1024*1024))
	var req FilterActionRequest
	_ = json.Unmarshal(body, &req)

	if err := s.controller.RefreshFilterLists(r.Context(), req.ID); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[string]{
		Success: true,
		Message: "规则源拉取与索引重构已完成",
	})
}

// handleFilterRules 处理 GET / POST /api/v1/filter/rules
func (s *Server) handleFilterRules(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		rules, err := s.controller.GetCustomRules(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*FilterRulesResponse]{
			Success: true,
			Data:    &FilterRulesResponse{Rules: rules},
		})
		return
	}

	if r.Method == http.MethodPost {
		body, err := io.ReadAll(io.LimitReader(r.Body, 10*1024*1024))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
			return
		}
		var req core.UpdateRulesRequest
		if err := json.Unmarshal(body, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析规则列表失败: " + err.Error()})
			return
		}
		if err := s.controller.SetCustomRules(r.Context(), req.Rules); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[string]{
			Success: true,
			Message: "自定义规则已保存生效",
		})
		return
	}

	writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "不支持的 HTTP 方法"})
}

// handleFilterCheck 处理 POST /api/v1/filter/check
func (s *Server) handleFilterCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 1024*1024))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req core.CheckDomainRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求失败: " + err.Error()})
		return
	}

	var qtype uint16 = dns.TypeA
	if req.QType != "" {
		if t, ok := dns.StringToType[strings.ToUpper(req.QType)]; ok {
			qtype = t
		}
	}

	res, err := s.controller.CheckHostRule(r.Context(), req.Domain, qtype)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*core.CheckHostResult]{
		Success: true,
		Data:    res,
	})
}
