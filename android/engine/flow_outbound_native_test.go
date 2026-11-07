//go:build cgo

// flow_outbound_native_test.go drives the real outbound-proxy path against scripted SOCKS5 and
// HTTP proxies: the config fixture replay proves the normalization matches the old Go code, and the
// end-to-end cases prove the kernel's bytes are what a proxy expects and what the relay side of the
// engine reads back.

package tunnel

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

const proxyFixtureDir = "../../rust/diting-proxy-core/tests/fixtures"

func fixtureRows(t *testing.T, name string) [][]string {
	t.Helper()
	path := proxyFixtureDir + "/" + name
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	rows := make([][]string, 0, 64)
	for _, line := range strings.Split(string(body), "\n") {
		if line == "" {
			continue
		}
		rows = append(rows, strings.Split(line, "\t"))
	}
	return rows
}

func fixtureHex(t *testing.T, value string) []byte {
	t.Helper()
	decoded, err := hex.DecodeString(value)
	if err != nil {
		t.Fatalf("fixture hex %q: %v", value, err)
	}
	return decoded
}

// TestProxyConfigFixtureMatchesNormalization replays config.tsv through the Go JSON decode plus
// the kernel: the old `parseOutboundProxyConfig` produced those columns, so a mismatch is a
// behaviour change.
func TestProxyConfigFixtureMatchesNormalization(t *testing.T) {
	for _, row := range fixtureRows(t, "config.tsv") {
		raw := string(fixtureHex(t, row[0]))
		cfg, err := parseOutboundProxyConfig(raw)
		actual := ""
		if err != nil {
			actual = "err:" + err.Error()
		} else {
			uids := make([]int, 0, len(cfg.uidSet))
			for uid := range cfg.uidSet {
				uids = append(uids, uid)
			}
			sort.Ints(uids)
			joined := "-"
			if len(uids) > 0 {
				parts := make([]string, len(uids))
				for i, uid := range uids {
					parts[i] = strconv.Itoa(uid)
				}
				joined = strings.Join(parts, ",")
			}
			actual = strings.Join([]string{
				"ok",
				hex.EncodeToString([]byte(cfg.Protocol)),
				hex.EncodeToString([]byte(cfg.Host)),
				strconv.Itoa(cfg.Port),
				hex.EncodeToString([]byte(cfg.Scope)),
				joined,
			}, "	")
		}
		if expected := strings.Join(row[9:], "\t"); actual != expected {
			t.Errorf("config %s:\n got %q\nwant %q", raw, actual, expected)
		}
	}
}

// scriptedProxy is a SOCKS5 or HTTP CONNECT proxy on a real listener, recording what the client
// wrote and the command it asked for.
type scriptedProxy struct {
	listener net.Listener
	protocol string // "socks5" or "http"
	username string
	password string
	method   byte // SOCKS5 method the proxy selects

	mu            sync.Mutex
	received      bytes.Buffer
	command       byte
	target        string
	authorization string
}

func newScriptedProxy(t *testing.T, protocol, username, password string, method byte) *scriptedProxy {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	proxy := &scriptedProxy{
		listener: listener,
		protocol: protocol,
		username: username,
		password: password,
		method:   method,
	}
	go proxy.serve()
	t.Cleanup(func() { listener.Close() })
	return proxy
}

func (p *scriptedProxy) port() int {
	return p.listener.Addr().(*net.TCPAddr).Port
}

func (p *scriptedProxy) configJSON(t *testing.T) string {
	t.Helper()
	return fmt.Sprintf(`{"enabled":true,"protocol":%q,"host":"127.0.0.1","port":%d,"username":%q,"password":%q}`,
		p.protocol, p.port(), p.username, p.password)
}

func (p *scriptedProxy) record(data []byte) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.received.Write(data)
}

func (p *scriptedProxy) serve() {
	for {
		conn, err := p.listener.Accept()
		if err != nil {
			return
		}
		go p.handle(conn)
	}
}

func (p *scriptedProxy) handle(conn net.Conn) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
	reader := bufio.NewReader(conn)
	read := func(n int) ([]byte, bool) {
		buf := make([]byte, n)
		got, err := io.ReadFull(reader, buf)
		p.record(buf[:got])
		return buf, err == nil
	}
	if p.protocol == "socks5" {
		if !p.handleSocks(conn, read) {
			return
		}
	} else {
		if !p.handleHTTP(conn, reader) {
			return
		}
	}
	_ = conn.SetDeadline(time.Time{})
	// Echo everything that follows the handshake.
	_, _ = io.Copy(conn, reader)
}

func (p *scriptedProxy) handleSocks(conn net.Conn, read func(int) ([]byte, bool)) bool {
	header, ok := read(2)
	if !ok || header[0] != 0x05 {
		return false
	}
	if _, ok := read(int(header[1])); !ok {
		return false
	}
	if _, err := conn.Write([]byte{0x05, p.method}); err != nil {
		return false
	}
	if p.method == 0x02 {
		verLen, ok := read(2)
		if !ok || verLen[0] != 0x01 {
			return false
		}
		user, ok := read(int(verLen[1]))
		if !ok {
			return false
		}
		passLen, ok := read(1)
		if !ok {
			return false
		}
		pass, ok := read(int(passLen[0]))
		if !ok {
			return false
		}
		if string(user) != p.username || string(pass) != p.password {
			_, _ = conn.Write([]byte{0x01, 0x01})
			return false
		}
		if _, err := conn.Write([]byte{0x01, 0x00}); err != nil {
			return false
		}
	}
	head, ok := read(4)
	if !ok || head[0] != 0x05 {
		return false
	}
	p.mu.Lock()
	p.command = head[1]
	p.mu.Unlock()
	var host string
	var port int
	switch head[3] {
	case 0x01:
		addr, ok := read(4)
		if !ok {
			return false
		}
		host = net.IP(addr).String()
	case 0x04:
		addr, ok := read(16)
		if !ok {
			return false
		}
		host = net.IP(addr).String()
	case 0x03:
		length, ok := read(1)
		if !ok {
			return false
		}
		name, ok := read(int(length[0]))
		if !ok {
			return false
		}
		host = string(name)
	default:
		return false
	}
	portBytes, ok := read(2)
	if !ok {
		return false
	}
	port = int(portBytes[0])<<8 | int(portBytes[1])
	p.mu.Lock()
	p.target = net.JoinHostPort(host, strconv.Itoa(port))
	p.mu.Unlock()
	// Reply with an IPv4 relay endpoint.
	_, err := conn.Write([]byte{0x05, 0x00, 0x00, 0x01, 1, 2, 3, 4, 0x04, 0x38})
	return err == nil
}

func (p *scriptedProxy) handleHTTP(conn net.Conn, reader *bufio.Reader) bool {
	request, err := readHTTPHeader(reader)
	if err != nil {
		return false
	}
	p.record(request)
	lines := strings.Split(string(request), "\r\n")
	if len(lines) == 0 {
		return false
	}
	fields := strings.Fields(lines[0])
	if len(fields) != 3 || fields[0] != "CONNECT" {
		return false
	}
	p.mu.Lock()
	p.target = fields[1]
	p.authorization = ""
	for _, line := range lines[1:] {
		if strings.HasPrefix(line, "Proxy-Authorization: ") {
			p.authorization = strings.TrimPrefix(line, "Proxy-Authorization: ")
		}
	}
	p.mu.Unlock()
	_, err = conn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))
	return err == nil
}

func readHTTPHeader(reader *bufio.Reader) ([]byte, error) {
	var header bytes.Buffer
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			return header.Bytes(), err
		}
		header.WriteString(line)
		if line == "\r\n" {
			return header.Bytes(), nil
		}
	}
}

func (p *scriptedProxy) snapshot() (received string, command byte, target string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.received.String(), p.command, p.target
}

func dialThroughProxy(t *testing.T, proxy *scriptedProxy, target string) (net.Conn, error) {
	t.Helper()
	cfg, err := parseOutboundProxyConfig(proxy.configJSON(t))
	if err != nil {
		t.Fatalf("config rejected: %v", err)
	}
	outbound := newFlowOutbound(cfg, nil, nil)
	t.Cleanup(func() { outbound.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return outbound.DialTCP(ctx, target)
}

func TestSocks5DialThroughProxyWithCredentials(t *testing.T) {
	proxy := newScriptedProxy(t, "socks5", "alice", "s3cret", 0x02)
	conn, err := dialThroughProxy(t, proxy, "example.com:80")
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	if _, err := conn.Write([]byte("ping")); err != nil {
		t.Fatalf("write: %v", err)
	}
	echo := make([]byte, 4)
	if _, err := io.ReadFull(conn, echo); err != nil {
		t.Fatalf("read echo: %v", err)
	}
	if string(echo) != "ping" {
		t.Fatalf("echo = %q", echo)
	}

	received, command, target := proxy.snapshot()
	want := []byte{0x05, 0x02, 0x00, 0x02} // greeting: no-auth + user/pass
	want = append(want, 0x01, 0x05)
	want = append(want, "alice"...)
	want = append(want, 0x06)
	want = append(want, "s3cret"...)
	want = append(want, 0x05, 0x01, 0x00, 0x03, 0x0b)
	want = append(want, "example.com"...)
	want = append(want, 0x00, 0x50)
	if received != string(want) {
		t.Fatalf("proxy received %x, want %x", received, want)
	}
	if command != socksCommandConnect {
		t.Fatalf("command = %d", command)
	}
	if target != "example.com:80" {
		t.Fatalf("target = %q", target)
	}
}

func TestSocks5NoAuthDialUsesIPAddressForm(t *testing.T) {
	proxy := newScriptedProxy(t, "socks5", "", "", 0x00)
	conn, err := dialThroughProxy(t, proxy, "1.2.3.4:443")
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	conn.Close()
	received, _, target := proxy.snapshot()
	want := []byte{0x05, 0x01, 0x00, 0x05, 0x01, 0x00, 0x01, 1, 2, 3, 4, 0x01, 0xbb}
	if received != string(want) {
		t.Fatalf("proxy received %x, want %x", received, want)
	}
	if target != "1.2.3.4:443" {
		t.Fatalf("target = %q", target)
	}
}

func TestHTTPConnectDialThroughProxy(t *testing.T) {
	proxy := newScriptedProxy(t, "http", "alice", "s3cret", 0)
	conn, err := dialThroughProxy(t, proxy, "example.com:443")
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()
	if _, err := conn.Write([]byte("hi")); err != nil {
		t.Fatalf("write: %v", err)
	}
	if _, err := io.ReadFull(conn, make([]byte, 2)); err != nil {
		t.Fatalf("read echo: %v", err)
	}
	received, _, target := proxy.snapshot()
	if target != "example.com:443" {
		t.Fatalf("target = %q", target)
	}
	if !strings.HasPrefix(received, "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n") {
		t.Fatalf("request = %q", received)
	}
	token, ok := strings.CutPrefix(proxy.authorization, "Basic ")
	if !ok {
		t.Fatalf("request has no basic authorization: %q", received)
	}
	credentials, err := base64.StdEncoding.DecodeString(token)
	if err != nil || string(credentials) != "alice:s3cret" {
		t.Fatalf("authorization token %q decodes to %q (%v)", token, credentials, err)
	}
	if !strings.HasSuffix(received, "\r\n\r\n") {
		t.Fatalf("request is not terminated: %q", received)
	}
}

func TestSocks5HandshakeErrorIsReported(t *testing.T) {
	proxy := newScriptedProxy(t, "socks5", "", "", 0xff)
	_, err := dialThroughProxy(t, proxy, "example.com:80")
	if err == nil {
		t.Fatal("expected the rejected handshake to fail")
	}
	if !strings.Contains(err.Error(), "SOCKS5 proxy rejected authentication methods") {
		t.Fatalf("error = %v", err)
	}
}

func TestProxyRejectsUnsupportedUDP(t *testing.T) {
	proxy := newScriptedProxy(t, "http", "", "", 0)
	cfg, err := parseOutboundProxyConfig(proxy.configJSON(t))
	if err != nil {
		t.Fatalf("config rejected: %v", err)
	}
	outbound := newFlowOutbound(cfg, nil, nil)
	defer outbound.Close()
	if _, err := outbound.DialUDP(context.Background(), "8.8.8.8:53"); !errors.Is(err, errOutboundUDPUnsupported) {
		t.Fatalf("DialUDP error = %v", err)
	}
	if _, err := outbound.OpenPacket(context.Background()); !errors.Is(err, errOutboundUDPUnsupported) {
		t.Fatalf("OpenPacket error = %v", err)
	}
}

// TestSocks5UDPAssociateFraming drives OpenPacket: the associate handshake, the datagram wrapper
// the relay receives and the decoder used on the reply.
func TestSocks5UDPAssociateFraming(t *testing.T) {
	relay, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("relay listen: %v", err)
	}
	defer relay.Close()

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("proxy listen: %v", err)
	}
	defer listener.Close()

	control := make(chan struct{})
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		reader := bufio.NewReader(conn)
		_, _ = reader.Discard(3) // greeting
		_, _ = conn.Write([]byte{0x05, 0x00})
		header := make([]byte, 4)
		if _, err := io.ReadFull(reader, header); err != nil {
			return
		}
		_, _ = io.CopyN(io.Discard, reader, 6) // 1.2.3.4:0
		relayUDP := relay.LocalAddr().(*net.UDPAddr)
		reply := []byte{0x05, 0x00, 0x00, 0x01}
		reply = append(reply, relayUDP.IP.To4()...)
		reply = append(reply, byte(relayUDP.Port>>8), byte(relayUDP.Port))
		_, _ = conn.Write(reply)
		<-control
	}()

	cfg, err := parseOutboundProxyConfig(fmt.Sprintf(
		`{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":%d}`,
		listener.Addr().(*net.TCPAddr).Port))
	if err != nil {
		t.Fatalf("config rejected: %v", err)
	}
	outbound := newFlowOutbound(cfg, nil, nil)
	defer outbound.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	packet, err := outbound.OpenPacket(ctx)
	if err != nil {
		t.Fatalf("OpenPacket: %v", err)
	}
	defer packet.Close()

	target, err := net.ResolveUDPAddr("udp", "1.2.3.4:53")
	if err != nil {
		t.Fatalf("resolve target: %v", err)
	}
	if _, err := packet.WriteTo([]byte("dns-query"), target); err != nil {
		t.Fatalf("WriteTo: %v", err)
	}

	buf := make([]byte, 512)
	_ = relay.SetReadDeadline(time.Now().Add(5 * time.Second))
	n, from, err := relay.ReadFrom(buf)
	if err != nil {
		t.Fatalf("relay read: %v", err)
	}
	want := []byte{0, 0, 0, 0x01, 1, 2, 3, 4, 0x00, 0x35}
	want = append(want, "dns-query"...)
	if !bytes.Equal(buf[:n], want) {
		t.Fatalf("relay received %x, want %x", buf[:n], want)
	}

	reply := []byte{0, 0, 0, 0x01, 9, 8, 7, 6, 0x1f, 0x90}
	reply = append(reply, "answer"...)
	if _, err := relay.WriteTo(reply, from); err != nil {
		t.Fatalf("relay write: %v", err)
	}

	_ = packet.SetReadDeadline(time.Now().Add(5 * time.Second))
	count, address, err := packet.ReadFrom(buf)
	if err != nil {
		t.Fatalf("ReadFrom: %v", err)
	}
	if string(buf[:count]) != "answer" {
		t.Fatalf("payload = %q", buf[:count])
	}
	if address.String() != "9.8.7.6:8080" {
		t.Fatalf("address = %q", address.String())
	}
	close(control)
}
