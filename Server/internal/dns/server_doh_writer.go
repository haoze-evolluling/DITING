package dns

import (
	"net"
	"net/http"

	"github.com/miekg/dns"
)

// dohResponseWriter 把一次 HTTP 请求伪装成 dns.ResponseWriter。
//
// 流水线只认这个接口，而 DoH 的应答要经 HTTP 写出，因此这里把待发消息留在
// 内存里，由调用方在 HTTP 层落笔——而不是直接写 socket。
//
// remote 由调用方传入：net/http 不公开底层连接，从 ResponseWriter 取不到
// 对端地址，但访问控制与限速都依赖它，不能省。
type dohResponseWriter struct {
	w      http.ResponseWriter
	remote net.Addr
	resp   *dns.Msg
}

// newDoHResponseWriter 包装一次 DoH 请求的写出目标。
//
// remote 为 nil 时流水线会当作无来源处理（不做按 IP 的判定），
// 因此调用方应尽量给出真实对端地址。
func newDoHResponseWriter(w http.ResponseWriter, remote net.Addr) *dohResponseWriter {
	return &dohResponseWriter{w: w, remote: remote}
}

// LocalAddr 返回服务端地址；HTTP 层不提供该信息，返回 nil。
func (d *dohResponseWriter) LocalAddr() net.Addr { return nil }

// RemoteAddr 返回调用方地址，供访问控制与限速使用。
func (d *dohResponseWriter) RemoteAddr() net.Addr { return d.remote }

// WriteMsg 记录应答，实际写出由 HTTP 层完成
func (d *dohResponseWriter) WriteMsg(m *dns.Msg) error {
	if m == nil {
		return nil
	}
	// 拷一份：流水线在写出之后仍可能改动这个消息，而 HTTP 层是稍后才读它
	d.resp = m.Copy()
	return nil
}

// Write 记录已封装的应答
func (d *dohResponseWriter) Write(b []byte) (int, error) {
	m := new(dns.Msg)
	if err := m.Unpack(b); err != nil {
		return 0, err
	}
	d.resp = m
	return len(b), nil
}

// Close 在 DoH 中无对应动作：连接由 HTTP 层管理
func (d *dohResponseWriter) Close() error { return nil }

// TsigStatus 返回 TSIG 校验状态；DoH 入口不做 TSIG 校验
func (d *dohResponseWriter) TsigStatus() error { return nil }

// TsigTimersOnly 设置 TSIG 计时器模式；DoH 入口不做 TSIG 校验
func (d *dohResponseWriter) TsigTimersOnly(bool) {}

// Hijack 交还连接控制权；DoH 不对外暴露底层连接，故为空操作
func (d *dohResponseWriter) Hijack() {}
