// engine_dns_transport.go hosts the DNS-over-UDP and DNS-over-TCP stream
// handlers used by the full-tunnel data plane, plus the dns.ResponseWriter
// adapters that forward answers back into the gVisor flow.
//
// These used to live at the bottom of engine_full_tunnel.go; they are split out
// so that file stays inside the project's 550-line ceiling while the buffered
// TUN writer and the flow handlers keep their own file.

package tunnel

import (
	"encoding/binary"
	"io"
	"net"
	"time"

	"github.com/miekg/dns"
	"github.com/xjasonlyu/tun2socks/v2/core/adapter"
)

const dnsUDPIdleTimeout = 15 * time.Second

func handleDNSOverUDP(conn adapter.UDPConn, engine *Engine, uid int) {
	defer conn.Close()

	appName := engine.appNameForFlow(udpFlowID(conn), ProtocolUDP)
	buf := make([]byte, 4096)
	for {
		_ = conn.SetReadDeadline(time.Now().Add(dnsUDPIdleTimeout))
		n, err := conn.Read(buf)
		if err != nil {
			return
		}
		if engine.trafficTracker != nil && n > 0 {
			engine.trafficTracker.RecordTx(uid, int64(n))
		}
		req := new(dns.Msg)
		if err := req.Unpack(buf[:n]); err != nil {
			continue
		}
		engine.serveDNS(&udpDNSResponseWriter{conn: conn, engine: engine, uid: uid}, req, appName, uid)
	}
}

type udpDNSResponseWriter struct {
	conn   adapter.UDPConn
	engine *Engine
	uid    int
}

func (w *udpDNSResponseWriter) LocalAddr() net.Addr  { return w.conn.LocalAddr() }
func (w *udpDNSResponseWriter) RemoteAddr() net.Addr { return w.conn.RemoteAddr() }

func (w *udpDNSResponseWriter) WriteMsg(m *dns.Msg) error {
	packed, err := m.Pack()
	if err != nil {
		return err
	}
	if w.engine != nil && w.engine.trafficTracker != nil && len(packed) > 0 {
		w.engine.trafficTracker.RecordRx(w.uid, int64(len(packed)))
	}
	_, err = w.conn.Write(packed)
	return err
}

func (w *udpDNSResponseWriter) Write(b []byte) (int, error) {
	if w.engine != nil && w.engine.trafficTracker != nil && len(b) > 0 {
		w.engine.trafficTracker.RecordRx(w.uid, int64(len(b)))
	}
	return w.conn.Write(b)
}

func (w *udpDNSResponseWriter) Close() error        { return nil }
func (w *udpDNSResponseWriter) TsigStatus() error   { return nil }
func (w *udpDNSResponseWriter) TsigTimersOnly(bool) {}
func (w *udpDNSResponseWriter) Hijack()             {}

const dnsTCPIdleTimeout = 15 * time.Second

func handleDNSOverTCP(conn adapter.TCPConn, engine *Engine, uid int) {
	defer conn.Close()
	appName := engine.appNameForFlow(tcpFlowID(conn), ProtocolTCP)
	lenBuf := make([]byte, 2)
	for {
		_ = conn.SetReadDeadline(time.Now().Add(dnsTCPIdleTimeout))
		if _, err := io.ReadFull(conn, lenBuf); err != nil {
			return
		}
		msgLen := binary.BigEndian.Uint16(lenBuf)
		if msgLen == 0 {
			continue
		}
		buf := make([]byte, msgLen)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return
		}
		if engine.trafficTracker != nil {
			engine.trafficTracker.RecordTx(uid, int64(2+int(msgLen)))
		}
		req := new(dns.Msg)
		if err := req.Unpack(buf); err != nil {
			continue
		}
		engine.serveDNS(&tcpDNSResponseWriter{conn: conn, engine: engine, uid: uid}, req, appName, uid)
	}
}

type tcpDNSResponseWriter struct {
	conn   adapter.TCPConn
	engine *Engine
	uid    int
}

func (w *tcpDNSResponseWriter) LocalAddr() net.Addr  { return w.conn.LocalAddr() }
func (w *tcpDNSResponseWriter) RemoteAddr() net.Addr { return w.conn.RemoteAddr() }

func (w *tcpDNSResponseWriter) WriteMsg(m *dns.Msg) error {
	packed, err := m.Pack()
	if err != nil {
		return err
	}
	return w.writeBytes(packed)
}

func (w *tcpDNSResponseWriter) Write(b []byte) (int, error) {
	err := w.writeBytes(b)
	if err != nil {
		return 0, err
	}
	return len(b), nil
}

func (w *tcpDNSResponseWriter) writeBytes(b []byte) error {
	total := make([]byte, 2+len(b))
	binary.BigEndian.PutUint16(total, uint16(len(b)))
	copy(total[2:], b)
	if w.engine != nil && w.engine.trafficTracker != nil && len(total) > 0 {
		w.engine.trafficTracker.RecordRx(w.uid, int64(len(total)))
	}
	_ = w.conn.SetWriteDeadline(time.Now().Add(dnsTCPIdleTimeout))
	_, err := w.conn.Write(total)
	return err
}

func (w *tcpDNSResponseWriter) Close() error        { return nil }
func (w *tcpDNSResponseWriter) TsigStatus() error   { return nil }
func (w *tcpDNSResponseWriter) TsigTimersOnly(bool) {}
func (w *tcpDNSResponseWriter) Hijack()             {}
