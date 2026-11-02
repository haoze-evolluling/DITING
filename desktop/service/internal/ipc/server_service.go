package ipc

import (
	"net/http"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// handleServiceStatus 返回宿主机后台核心服务的真实状态。
//
// Web 控制台运行在浏览器中，无法直接访问桌面端进程，历史上只能退回
// 一份"未安装/未检测到"的占位状态，导致界面与宿主机实际情况相悖。
// 本端点由宿主机服务进程直接查询 SCM / systemd，是 Web 端的权威数据源。
func (s *Server) handleServiceStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}
	status, err := s.controller.GetCoreServiceStatus(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*platform.CoreServiceStatus]{Success: true, Data: status})
}
