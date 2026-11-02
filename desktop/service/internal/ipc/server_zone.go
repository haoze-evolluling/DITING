package ipc

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// handleZoneConfig 处理 /api/v1/dns/zone/config (GET, POST)
//
// GET 返回区配置与各区构建结果；POST 整体更新并重建索引。
func (s *Server) handleZoneConfig(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		res, err := s.controller.GetZoneConfig(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, Response[*ZoneConfigResponse]{Success: true, Data: res})

	case http.MethodPost:
		body, err := io.ReadAll(r.Body)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
			return
		}
		var req ConfigureZoneRequest
		if err := json.Unmarshal(body, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
			return
		}
		if err := s.controller.ConfigureZone(r.Context(), req); err != nil {
			writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
			return
		}
		// 回传重建后的完整状态：解析失败是逐区发生的，
		// 只回一句「已保存」会让用户以为写错的区也生效了
		res, err := s.controller.GetZoneConfig(r.Context())
		if err != nil {
			writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "本地权威区配置已更新"})
			return
		}
		writeJSON(w, http.StatusOK, Response[*ZoneConfigResponse]{Success: true, Data: res})

	default:
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET, POST 请求"})
	}
}

// handleZoneTest 处理 POST /api/v1/dns/zone/test
//
// 用与引擎完全相同的解析路径预演一次，让用户在保存前就看到结果。
// 解析失败属于预期输入而非服务异常，因此返回 200 + Success=false。
func (s *Server) handleZoneTest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return
	}
	var req ZoneTestRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return
	}

	records, err := core.ParseZonePreview(req.Origin, req.Content, req.TTL)
	if err != nil {
		writeJSON(w, http.StatusOK, Response[ZoneTestResponse]{
			Success: true,
			Data:    ZoneTestResponse{Success: false, Records: []string{}, Error: err.Error()},
		})
		return
	}
	writeJSON(w, http.StatusOK, Response[ZoneTestResponse]{
		Success: true,
		Data:    ZoneTestResponse{Success: true, Records: records},
	})
}
