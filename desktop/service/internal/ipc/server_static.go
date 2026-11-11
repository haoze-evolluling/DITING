package ipc

import (
	"io"
	"io/fs"
	"mime"
	"net"
	"net/http"
	"path"
	"path/filepath"
	"strings"
)

// SetAssetsFS 设置嵌入的 Web 前端静态文件系统
func (s *Server) SetAssetsFS(assets fs.FS) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.assetsFS = assets
}

// handleStaticSPA 托管前端单页应用 (SPA)，支持静态资源分发与 HTML5 History 路由回退
func (s *Server) handleStaticSPA(w http.ResponseWriter, r *http.Request) {
	// 拦截未匹配的 /api/ 路由，返回标准 JSON 404
	if strings.HasPrefix(r.URL.Path, "/api/") {
		writeJSON(w, http.StatusNotFound, Response[any]{
			Success: false,
			Error:   "api endpoint not found",
		})
		return
	}

	s.mu.RLock()
	assets := s.assetsFS
	s.mu.RUnlock()

	if assets == nil {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>谛听 DNS</title></head><body style="font-family:sans-serif;text-align:center;padding:50px;"><h2>谛听 (DITING) 服务运行中</h2><p>未加载前端静态资源包</p></body></html>`))
		return
	}

	reqPath := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
	if reqPath == "" || reqPath == "." {
		reqPath = "index.html"
	}

	// 尝试在静态资源中查找目标文件
	f, err := assets.Open(reqPath)
	if err != nil {
		// 文件不存在，回退至 index.html 以支撑 SPA 前端路由
		serveIndexHTML(w, assets)
		return
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil || stat.IsDir() {
		serveIndexHTML(w, assets)
		return
	}

	// 针对带哈希指纹的 assets 静态文件开启长期高效缓存
	ext := filepath.Ext(reqPath)
	ctype := mime.TypeByExtension(ext)
	if ctype == "" {
		switch ext {
		case ".svg":
			ctype = "image/svg+xml"
		case ".ico":
			ctype = "image/x-icon"
		case ".png":
			ctype = "image/png"
		case ".woff2":
			ctype = "font/woff2"
		case ".js", ".mjs":
			ctype = "text/javascript; charset=utf-8"
		case ".css":
			ctype = "text/css; charset=utf-8"
		case ".json":
			ctype = "application/json"
		default:
			ctype = "application/octet-stream"
		}
	}
	w.Header().Set("Content-Type", ctype)

	if strings.HasPrefix(reqPath, "assets/") {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	} else if reqPath == "index.html" {
		w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	}

	if rs, ok := f.(io.ReadSeeker); ok {
		http.ServeContent(w, r, reqPath, stat.ModTime(), rs)
	} else {
		_, _ = io.Copy(w, f)
	}
}

func serveIndexHTML(w http.ResponseWriter, assets fs.FS) {
	idxFile, err := assets.Open("index.html")
	if err != nil {
		http.Error(w, "index.html not found", http.StatusNotFound)
		return
	}
	defer idxFile.Close()

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	_, _ = io.Copy(w, idxFile)
}

// extractToken 从 Authorization / X-API-Token 头或查询参数提取访问凭证
func extractToken(r *http.Request) string {
	authHeader := r.Header.Get("Authorization")
	if strings.HasPrefix(authHeader, "Bearer ") {
		return strings.TrimPrefix(authHeader, "Bearer ")
	}
	if t := r.Header.Get("X-API-Token"); t != "" {
		return t
	}
	return r.URL.Query().Get("token")
}

// getClientIP 返回用于防爆破计数的客户端地址。
//
// IPC 服务在桌面/Web 模式下都是直连（无自有反向代理），因此只采信
// TCP 对端地址。X-Forwarded-For / X-Real-IP 完全由客户端控制，若采信
// 则攻击者每次请求换一个伪造值即可无限次尝试口令，也能反向锁死他人。
func getClientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}
