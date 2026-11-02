package ipc

import (
	"net/http"
)

// handleEmergencyRestore 应急恢复系统 DNS。
//
// 旧版桌面端把这件事放在原生绑定（`App.RunEmergencyRestore`）里，只有桌面窗口能用；
// Flutter 前端只走 HTTP，所以这里补一个受鉴权保护的同义接口，桌面窗口与局域网控制台共用。
// 恢复依据是服务落盘的接管快照，与启动时的自愈逻辑同源，不会凭当前状态猜测。
func (s *Server) handleEmergencyRestore(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	result, err := s.controller.EmergencyRestore(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	if result == nil {
		result = &EmergencyRestoreResponse{Message: "网络 DNS 状态正常，无需修复。"}
	}
	writeJSON(w, http.StatusOK, Response[*EmergencyRestoreResponse]{Success: true, Data: result})
}
