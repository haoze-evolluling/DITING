package ipc

import (
	"net/http"
)

// corsMiddleware 为本地 HTTP/WS IPC 服务注入标准跨域响应头及预检支持。
// 解决 WebView2 (Wails) 前端与 127.0.0.1 本地特权服务通信时的跨域限制，
// 并兼容 Chromium 私有网络访问 (Private Network Access) 规范。
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
		} else {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, HEAD")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-API-Token, Accept, Origin, Cache-Control, X-Requested-With")
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Access-Control-Max-Age", "86400")
		// 支持 Chromium / WebView2 私有网络访问 (Private Network Access) 规范
		w.Header().Set("Access-Control-Allow-Private-Network", "true")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
