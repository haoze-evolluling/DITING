package ipc

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

// handlePortCheck 诊断 53 端口冲突
func (s *Server) handlePortCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	result, err := s.controller.CheckPortConflicts(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*windows.PortCheckResult]{Success: true, Data: result})
}

// handlePortAutofix 自动修复 53 端口冲突（如停止/禁用 ICS 服务）并可选拉起 DNS
func (s *Server) handlePortAutofix(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req AutofixPortRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}
	result, err := s.controller.AutofixPortConflicts(r.Context(), req.StartDNS)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[*windows.PortCheckResult]{
			Success:  false,
			Error:    err.Error(),
			Conflict: result,
		})
		return
	}
	if req.StartDNS && result != nil && result.Available {
		s.Broadcast(Event{Type: "dns", Timestamp: time.Now().UnixMilli(), Data: "started"})
	}
	writeJSON(w, http.StatusOK, Response[*windows.PortCheckResult]{
		Success: true,
		Message: "端口冲突已成功自动修复",
		Data:    result,
	})
}
