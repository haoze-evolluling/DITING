package dns

import (
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	pathpkg "path"
	"strings"
	"time"

	"github.com/miekg/dns"
)

// DoH 的请求参数与限制（RFC 8484）
const (
	// dohContentType 是 DoH 报文的媒体类型
	dohContentType = "application/dns-message"
	// dohGetParam 是 GET 请求里承载报文的查询参数
	dohGetParam = "dns"
	// dohMaxBody 限制 POST 正文大小。
	//
	// DNS 报文本身封顶 64 KiB，留一点余量给不该出现的多余字节；
	// 不设上限的话，一个匿名客户端就能用超大正文把内存吃光。
	dohMaxBody = 65536 + 512
	// dohReadTimeout / dohWriteTimeout 针对单次请求
	dohReadTimeout  = 10 * time.Second
	dohWriteTimeout = 10 * time.Second
	// dohIdleTimeout 是 HTTP 连接的保活时长
	dohIdleTimeout = 60 * time.Second
)

// dohListener 承载 DoH 的 HTTPS 监听器。
type dohListener struct {
	srv  *http.Server
	ln   net.Listener
	path string
	// pprof 之类不该出现在面向终端的解析入口上，这里只跑一个极小的路由
}

// DoHListenAddress 返回 DoH 实际生效的监听地址；未在监听时返回空串。
func (s *Server) DoHListenAddress() string {
	s.mu.Lock()
	dl := s.doh
	s.mu.Unlock()
	if dl == nil || dl.ln == nil {
		return ""
	}
	return dl.ln.Addr().String()
}

// DoHPath 返回当前生效的 DoH 路径。
//
// 优先报监听器上真正注册的那条：它是既成事实，而配置可能在重建
// 监听器失败后与运行状态不一致。
func (s *Server) DoHPath() string {
	s.mu.Lock()
	dl := s.doh
	cfg := s.encrypted
	s.mu.Unlock()
	if dl != nil && dl.path != "" {
		return dl.path
	}
	if cfg == nil {
		return ""
	}
	return normalizeDoHPath(cfg.DoHPath)
}

// normalizeDoHPath 保证路径以 "/" 开头且没有末尾斜杠。
//
// 客户端会把配置里写的东西逐字拼进 URL，缺前导斜杠会得到
// https://hostdns-query 这种解析不了的地址；末尾斜杠则会让
// "/dns-query" 与 "/dns-query/" 变成两个不同的路由。
//
// 单独的 "/" 也回落到默认路径：它会让 ServeMux 注册出一条通配路由，
// 于是任意路径都被当成 DoH 入口，远不是填写者想要的效果。
func normalizeDoHPath(path string) string {
	p := strings.TrimSpace(path)
	if p == "" || p == "/" {
		return "/dns-query"
	}
	if !strings.HasPrefix(p, "/") {
		p = "/" + p
	}
	p = strings.TrimRight(p, "/")
	if p == "" {
		return "/dns-query"
	}
	// ServeMux 的模式语法对非法 pattern 直接 panic：内部 "//" 会报
	// "unclean path"，花括号会被当成通配段。用户输入必须在这里收敛成
	// 一个绝不会 panic 的普通字面路径。
	//
	// DDR 模板里的 "{?dns}" 占位符不是路径的一部分，先剥掉再统一拼回，
	// 避免同一份配置在「注册路由」与「广播 DDR」两处得到不同结果。
	p = stripDoHTemplate(p)
	p = pathpkg.Clean(p)
	if p == "/" || p == "." {
		return "/dns-query"
	}
	p = sanitizeDoHPathSegment(p)
	if p == "" || p == "/" {
		return "/dns-query"
	}
	return p
}

// stripDoHTemplate 去掉路径里的 "{...}" 占位段（如 DDR 的 "{?dns}"）。
func stripDoHTemplate(p string) string {
	for {
		start := strings.IndexByte(p, '{')
		if start < 0 {
			return p
		}
		end := strings.IndexByte(p[start:], '}')
		if end < 0 {
			return p[:start]
		}
		p = p[:start] + p[start+end+1:]
	}
}

// sanitizeDoHPathSegment 把路径中会破坏 ServeMux 模式的字符替换掉。
//
// 花括号是 Go 1.22 模式语法里的通配段标记，空格/控制字符也不该出现在
// 一个会被逐字拼进 URL 的路径里。替换而非拒绝：保存路径的调用方已经
// 落盘，返回一个可用的路径比让服务反复起不来更安全。
func sanitizeDoHPathSegment(p string) string {
	var b strings.Builder
	for _, r := range p {
		switch {
		case r == '{' || r == '}' || r < 0x20 || r == 0x7f:
			b.WriteRune('-')
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

// startDoH 绑定并激活 DoH 监听器（RFC 8484）。
// startDoHLocked 绑定并激活 DoH 监听器。调用方须持有 s.mu。
func (s *Server) startDoHLocked() error {
	cfg := s.encrypted
	if cfg == nil {
		return fmt.Errorf("未启用加密 DNS 监听")
	}
	if cfg.TLSConfig == nil {
		return fmt.Errorf("未载入服务端证书")
	}
	if err := cfg.Validate(); err != nil {
		return err
	}

	addr := cfg.DoHListenAddress()
	network := "tcp"
	if isIPv6(addr) {
		network = "tcp6"
	} else {
		network = "tcp4"
	}

	ln, err := net.Listen(network, addr)
	if err != nil {
		return fmt.Errorf("绑定 %s 失败: %w", addr, err)
	}

	path := normalizeDoHPath(cfg.DoHPath)
	mux := http.NewServeMux()
	registerDoHRoutes(mux, path, s)

	tlsCfg := cfg.TLSConfig.Clone()
	// DoH 走 HTTP/2；不宣告 h2 会让客户端回落 HTTP/1.1，多花往返
	tlsCfg.NextProtos = []string{"h2", "http/1.1"}
	tlsCfg.MinVersion = tlsMinVersionForDoH

	httpSrv := &http.Server{
		Handler:      mux,
		TLSConfig:    tlsCfg,
		ReadTimeout:  dohReadTimeout,
		WriteTimeout: dohWriteTimeout,
		IdleTimeout:  dohIdleTimeout,
	}

	dl := &dohListener{srv: httpSrv, ln: ln, path: path}
	s.doh = dl

	go func() {
		if err := httpSrv.ServeTLS(ln, "", ""); err != nil &&
			!errors.Is(err, http.ErrServerClosed) && s.serving() {
			// 监听器已绑定成功，这里出错多半是证书在服务过程中被换掉或
			// 文件被删；如实记录，明文解析不受影响
			logEncryptedError("DoH 服务异常退出", err)
		}
	}()
	return nil
}

// registerDoHRoutes 注册 DoH 的两条路由：无 ClientID 与带 ClientID。
//
// 用 Go 1.22 的方法+通配模式，{ClientID} 由 r.PathValue 取出；
// 若手工切路径，"/dns-query" 与 "/dns-query/x" 的前缀关系很容易写错。
func registerDoHRoutes(mux *http.ServeMux, path string, s *Server) {
	mux.HandleFunc("GET "+path, s.serveDoH(""))
	mux.HandleFunc("POST "+path, s.serveDoH(""))
	mux.HandleFunc("GET "+path+"/{ClientID}", s.serveDoHPathValue)
	mux.HandleFunc("POST "+path+"/{ClientID}", s.serveDoHPathValue)
}

// serveDoHPathValue 从路径段取出 ClientID 后继续处理。
func (s *Server) serveDoHPathValue(w http.ResponseWriter, r *http.Request) {
	s.serveDoH(r.PathValue("ClientID"))(w, r)
}

// serveDoH 处理一次 DoH 查询。
//
// clientIDFromPath 为路由里带出的 ClientID，未带时为空串。
func (s *Server) serveDoH(clientIDFromPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.closed.Load() {
			http.Error(w, "服务已停止", http.StatusServiceUnavailable)
			return
		}

		query, err := readDoHQuery(r)
		if err != nil {
			// 400 而非 500：报文不合规是调用方的问题，不该让客户端重试
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		req := new(dns.Msg)
		if err := req.Unpack(query); err != nil {
			http.Error(w, "DNS 报文无法解析", http.StatusBadRequest)
			return
		}
		// RFC 8484 §4.1：不合语法的报文（非单题查询 / QR=1）应返回 400
		if !isStandardQuery(req) {
			http.Error(w, "只接受单题标准查询报文", http.StatusBadRequest)
			return
		}

		// 路径里的 ClientID 先做一次校验：非法就让调用方知道，
		// 否则它会以为自己带着一个生效的身份在查询
		clientID := strings.TrimSpace(clientIDFromPath)
		if clientID != "" {
			if err := ValidateClientID(clientID); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			clientID = strings.ToLower(clientID)
		}

		rw := newDoHResponseWriter(w, s.doHClientAddr(r))
		s.handleEncryptedQuery(rw, req, queryOrigin{
			Protocol:     "doh",
			ServerName:   clientServerName(r),
			PathClientID: clientID,
		})

		if rw.resp == nil {
			http.Error(w, "解析失败", http.StatusInternalServerError)
			return
		}
		packed, err := rw.resp.Pack()
		if err != nil {
			http.Error(w, "应答无法封装", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", dohContentType)
		// DNS 应答里已有自己的 TTL，不该再被 HTTP 缓存重复计入
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(packed)
	}
}

// clientServerName 取 DoH 请求里可用于识别 ClientID 的服务器名。
//
// 优先用 Host 头：它才是客户端以为自己连的那个名字。TLS 的 SNI 在
// HTTP/2 下由客户端复用连接时可能只发一次，而 Host 每个请求都带。
func clientServerName(r *http.Request) string {
	host := strings.TrimSpace(r.Host)
	if host == "" {
		return ""
	}
	// 去掉端口：SNI 与 Host 的比对基准都是纯主机名
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	return strings.TrimSuffix(host, ".")
}

// readDoHQuery 按 RFC 8484 取出请求里的 DNS 报文。
//
// GET 用 base64url 编码的 ?dns= 参数，POST 用 application/dns-message 正文；
// 两种都只认这一种媒体类型，宽泛接受反而会让配置错误无从暴露。
func readDoHQuery(r *http.Request) ([]byte, error) {
	switch r.Method {
	case http.MethodGet:
		raw := r.URL.Query().Get(dohGetParam)
		if raw == "" {
			return nil, fmt.Errorf("缺少 %s 参数", dohGetParam)
		}
		// RFC 8484 允许省略填充，base64.RawURLEncoding 正好对应
		// 与 POST 分支同一道尺寸闸门：GET 报文经 base64 膨胀后可达数倍，
		// 不设上限时单个匿名请求即可放大 Unpack 的内存开销
		if len(raw) > base64.RawURLEncoding.EncodedLen(dohMaxBody) {
			return nil, fmt.Errorf("%s 参数超过 %d 字节上限", dohGetParam, dohMaxBody)
		}
		decoded, err := base64.RawURLEncoding.DecodeString(raw)
		if err != nil {
			return nil, fmt.Errorf("%s 参数不是合法的 base64url", dohGetParam)
		}
		if len(decoded) > dohMaxBody {
			return nil, fmt.Errorf("%s 参数超过 %d 字节", dohGetParam, dohMaxBody)
		}
		return decoded, nil

	case http.MethodPost:
		if ct := r.Header.Get("Content-Type"); !isDoHContentType(ct) {
			return nil, fmt.Errorf("Content-Type 必须是 %s", dohContentType)
		}
		body, err := io.ReadAll(io.LimitReader(r.Body, dohMaxBody+1))
		if err != nil {
			return nil, fmt.Errorf("读取请求正文失败")
		}
		if len(body) > dohMaxBody {
			return nil, fmt.Errorf("请求正文超过 %d 字节", dohMaxBody)
		}
		if len(body) == 0 {
			return nil, fmt.Errorf("请求正文为空")
		}
		return body, nil

	default:
		return nil, fmt.Errorf("不支持的请求方法 %s", r.Method)
	}
}

// isDoHContentType 判断媒体类型，忽略 charset 之类的参数。
func isDoHContentType(ct string) bool {
	if ct == "" {
		return false
	}
	base, _, _ := strings.Cut(ct, ";")
	return strings.EqualFold(strings.TrimSpace(base), dohContentType)
}
