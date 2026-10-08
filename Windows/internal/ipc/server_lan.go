package ipc

import (
	"encoding/json"
	"net/http"
	"time"
)

func (s *Server) handleLANStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	res, err := s.controller.GetLANStatus(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*LANStatusResponse]{Success: true, Data: res})
}

func (s *Server) handleLANConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req ConfigureLANRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	if err := s.controller.ConfigureLAN(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.Broadcast(Event{Type: "dns", Timestamp: time.Now().UnixMilli(), Data: "lan_updated"})
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: "局域网 DNS 服务配置已更新"})
}

func (s *Server) handleFirewallConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	var req ConfigureFirewallRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	if err := s.controller.ConfigureFirewall(r.Context(), req.Enable); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	msg := "已成功放行 53 端口防火墙规则"
	if !req.Enable {
		msg = "已成功移除 53 端口防火墙规则"
	}
	writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: msg})
}
