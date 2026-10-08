package ipc

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
)

func (s *Server) handleBootstrapConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req ConfigureBootstrapRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}

	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	cfg := core.BootstrapConfig{
		Enabled: enabled,
		Servers: req.Servers,
	}

	if err := s.controller.ConfigureUpstream(r.Context(), ConfigureUpstreamRequest{
		Bootstrap: &cfg,
	}); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.Broadcast(Event{Type: "upstream", Timestamp: time.Now().UnixMilli(), Data: "bootstrap_configured"})
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "Bootstrap DNS 配置已成功更新"})
}
