package dns

import (
	"context"
	"crypto/tls"
	"log"
	"net"
	"net/http"
	"strconv"
	"time"
)

// tlsMinVersionForDoH 为 DoH 的最低 TLS 版本。
//
// 与 DoT 一致取 TLS 1.2：把门槛拔到 1.3 会把一部分仍在使用的终端挡在门外，
// 而 DoH 的收益来自链路加密本身，不差这一档。
const tlsMinVersionForDoH = tls.VersionTLS12

// remoteAddrFromRequest 取 DoH 请求的对端地址。
//
// net/http 不公开底层连接，但 Request.RemoteAddr 是由 http.Server 在受理
// 连接时填入的，取它即可。访问控制与限速都依赖这个地址，取不到就只能
// 按「无来源」处理，因此宁可多解析一层也不要返回 nil。
func remoteAddrFromRequest(r *http.Request) net.Addr {
	if r == nil || r.RemoteAddr == "" {
		return nil
	}
	host, portStr, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return nil
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return nil
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil
	}
	return &net.TCPAddr{IP: ip, Port: port}
}

// logEncryptedError 记录加密监听的运行期错误。
//
// 加密入口是附加能力：它的异常不该影响明文解析，因此统一走日志，
// 不向调用方返回、也不触发任何降级动作。
func logEncryptedError(what string, err error) {
	log.Printf("[加密DNS] %s: %v\n", what, err)
}

// closeHTTP 在超时内优雅关闭 HTTP 服务，超时后强制断开。
func closeHTTP(srv *http.Server, timeout time.Duration) {
	if srv == nil {
		return
	}
	done := make(chan struct{})
	go func() {
		_ = srv.Shutdown(context.Background())
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(timeout):
		// 与明文监听器同样的取舍：超时后强行退出，不阻塞整体关闭
		_ = srv.Close()
	}
}
