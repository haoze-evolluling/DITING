package ipc

import (
	"fmt"
	"net/http"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// handleEncryptedMobileConfig 处理 GET /api/v1/encrypted/mobileconfig
//
// 返回的是二进制文件而不是 JSON，因此不走 withAuth 的 JSON 包装：
// 认证令牌经 extractToken 从查询串里取（与 /auth/background/image 同款），
// 好让用户把链接直接交给 iOS 设备打开——系统下载时不会带自定义请求头。
func (s *Server) handleEncryptedMobileConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "只支持 GET 请求", http.StatusMethodNotAllowed)
		return
	}
	if !s.verifyToken(r) {
		http.Error(w, "unauthorized: missing or invalid authentication token", http.StatusUnauthorized)
		return
	}

	// protocol 为空时由控制器按当前启用的监听器挑选
	protocol := r.URL.Query().Get("protocol")
	data, err := s.controller.BuildEncryptedMobileConfig(r.Context(), protocol)
	if err != nil {
		// 生成失败几乎都是配置不全（没服务器名、没有在跑的加密监听），
		// 属于调用方需要修正的状态，用 400 而非 500
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", core.MobileConfigContentType)
	w.Header().Set("Content-Disposition",
		fmt.Sprintf("attachment; filename=%q", "diting-dns"+core.MobileConfigFileExt))
	w.Header().Set("Content-Length", fmt.Sprintf("%d", len(data)))
	// 描述文件含内网地址，不该被中间代理或浏览器缓存下来
	w.Header().Set("Cache-Control", "no-store")

	if r.Method == http.MethodHead {
		w.WriteHeader(http.StatusOK)
		return
	}
	_, _ = w.Write(data)
}
