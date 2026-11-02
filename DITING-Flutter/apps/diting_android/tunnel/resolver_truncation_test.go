// resolver_truncation_test.go verifies the plain-UDP truncation retry (A-019).
//
// RFC 1035 §4.2.1 requires a resolver to retry over TCP when the upstream sets
// TC=1. The plain resolver used to return the truncated datagram as final, which
// then entered the cache and was replayed to every subsequent client: a
// header-only answer with no address records, indistinguishable from an upstream
// that answered NODATA.

package tunnel

import (
	"fmt"
	"net"
	"testing"
	"time"

	"github.com/miekg/dns"
)

// startTruncatingUpstream serves UDP answers with TC=1 and TCP answers with a
// real A record, matching the upstream behaviour that triggered the bug.
func startTruncatingUpstream(t *testing.T) (addr string, cleanup func()) {
	t.Helper()

	answer := func(r *dns.Msg, truncated bool, ip string) []byte {
		m := new(dns.Msg)
		m.SetReply(r)
		m.Truncated = truncated
		if !truncated && ip != "" {
			rr, err := dns.NewRR(fmt.Sprintf("%s 300 IN A %s", r.Question[0].Name, ip))
			if err == nil {
				m.Answer = append(m.Answer, rr)
			}
		}
		raw, _ := m.Pack()
		return raw
	}

	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("udp listen: %v", err)
	}
	port := pc.LocalAddr().(*net.UDPAddr).Port

	udpDone := make(chan struct{})
	go func() {
		defer close(udpDone)
		buf := make([]byte, 4096)
		for {
			n, from, rerr := pc.ReadFrom(buf)
			if rerr != nil {
				return
			}
			req := new(dns.Msg)
			if req.Unpack(buf[:n]) != nil {
				continue
			}
			_, _ = pc.WriteTo(answer(req, true, ""), from)
		}
	}()

	tcpLn, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		_ = pc.Close()
		t.Fatalf("tcp listen on same port: %v", err)
	}
	tcpDone := make(chan struct{})
	go func() {
		defer close(tcpDone)
		for {
			conn, aerr := tcpLn.Accept()
			if aerr != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				lenBuf := make([]byte, 2)
				if _, rerr := readFull(c, lenBuf); rerr != nil {
					return
				}
				msgLen := int(lenBuf[0])<<8 | int(lenBuf[1])
				body := make([]byte, msgLen)
				if _, rerr := readFull(c, body); rerr != nil {
					return
				}
				req := new(dns.Msg)
				if req.Unpack(body) != nil {
					return
				}
				resp := answer(req, false, "192.0.2.55")
				frame := []byte{byte(len(resp) >> 8), byte(len(resp))}
				_, _ = c.Write(append(frame, resp...))
			}(conn)
		}
	}()

	cleanup = func() {
		_ = pc.Close()
		_ = tcpLn.Close()
		<-udpDone
		<-tcpDone
	}
	return fmt.Sprintf("127.0.0.1:%d", port), cleanup
}

func readFull(c net.Conn, buf []byte) (int, error) {
	total := 0
	for total < len(buf) {
		n, err := c.Read(buf[total:])
		total += n
		if err != nil {
			return total, err
		}
	}
	return total, nil
}

func TestQueryPlainRetriesOverTcpWhenTruncated(t *testing.T) {
	addr, cleanup := startTruncatingUpstream(t)
	defer cleanup()

	resolver := NewResolver(nil)
	defer resolver.Shutdown()

	rawQuery := makeQueryMsg("truncated.example.")
	resp, err := resolver.queryPlain(rawQuery, addr)
	if err != nil {
		t.Fatalf("queryPlain failed: %v", err)
	}

	var msg dns.Msg
	if uerr := msg.Unpack(resp); uerr != nil {
		t.Fatalf("unpack response: %v", uerr)
	}
	if msg.Truncated {
		t.Fatalf("truncated UDP answer was returned as final instead of retrying over TCP")
	}
	if len(msg.Answer) != 1 {
		t.Fatalf("expected the TCP answer with one A record, got %d answers", len(msg.Answer))
	}
	a, ok := msg.Answer[0].(*dns.A)
	if !ok || a.A.String() != "192.0.2.55" {
		t.Fatalf("unexpected answer record: %v", msg.Answer[0])
	}
}

// The retry must not fire for a normal (non-truncated) UDP answer, or every
// plain query would open a pointless TCP connection.
func TestQueryPlainDoesNotOpenTcpForCompleteAnswer(t *testing.T) {
	server, addr := startMockDNSServer(t, makeAnswerHandler("192.0.2.7", 0))
	defer func() { _ = server.Shutdown() }()
	// Deliberately no TCP listener on that port: a retry would fail and the
	// truncated fallback would surface as a missing answer.
	resolver := NewResolver(nil)
	defer resolver.Shutdown()

	resp, err := resolver.queryPlain(makeQueryMsg("complete.example."), addr)
	if err != nil {
		t.Fatalf("queryPlain failed: %v", err)
	}
	var msg dns.Msg
	if uerr := msg.Unpack(resp); uerr != nil {
		t.Fatalf("unpack response: %v", uerr)
	}
	if msg.Truncated || len(msg.Answer) != 1 {
		t.Fatalf("complete UDP answer was not returned as-is: truncated=%v answers=%d", msg.Truncated, len(msg.Answer))
	}

	time.Sleep(50 * time.Millisecond) // let any stray dial surface
}
