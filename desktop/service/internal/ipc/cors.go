package ipc

import (
	"net"
	"net/http"
	"net/url"
	"strings"
)

// corsMiddleware 为本地 HTTP/WS IPC 服务注入标准跨域响应头及预检支持。
// 解决浏览器页面与 127.0.0.1 本地特权服务通信时的跨域限制，
// 并兼容 Chromium 私有网络访问 (Private Network Access) 规范。
//
// 安全约束：只对受信来源反射 Origin。任意互联网页面同样可以访问 127.0.0.1，
// 若无条件反射 Origin 并允许凭据，恶意网页即可跨域读写本机管理 API。
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		trusted := isTrustedOrigin(r)
		if origin == "" {
			// 非浏览器请求（本机进程 / curl）：无需 CORS 头，保持与旧行为一致
			w.Header().Set("Access-Control-Allow-Origin", "*")
		} else if trusted {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, HEAD")
		if reqHeaders := r.Header.Get("Access-Control-Request-Headers"); reqHeaders != "" && trusted {
			w.Header().Set("Access-Control-Allow-Headers", reqHeaders)
		} else {
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-API-Token, Accept, Origin, Cache-Control, X-Requested-With, Access-Control-Request-Private-Network")
		}
		w.Header().Set("Access-Control-Max-Age", "86400")
		// 支持 Chromium 私有网络访问 (Private Network Access) 规范
		w.Header().Set("Access-Control-Allow-Private-Network", "true")

		if r.Method == http.MethodOptions {
			if !trusted {
				w.WriteHeader(http.StatusForbidden)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// isTrustedOrigin 判断请求来源是否为受信页面。
//
// 非浏览器请求（无 Origin 头，如本机进程 / curl）视为受信——它们本就不受
// 同源策略约束，且无法通过 Origin 区分身份；浏览器请求则只接受本机回环
// 页面与同源页面。任意互联网页面必然携带远端 Origin，会被拒绝。
func isTrustedOrigin(r *http.Request) bool {
	origin := strings.TrimSpace(r.Header.Get("Origin"))
	if origin == "" {
		return true
	}
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	host := strings.ToLower(u.Hostname())
	if host == "localhost" {
		return true
	}
	if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
		return true
	}
	// 同源页面（Web 控制台自身）
	return strings.EqualFold(u.Host, r.Host)
}
