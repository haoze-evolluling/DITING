// flow_outbound.go implements flow-level outbound transport adapters including direct socket dialing,
// SOCKS5 proxies (with optional username/password authentication and UDP associate support),
// and HTTP CONNECT tunnels (with basic authentication). All outbound connections utilize
// socket protection functions to bypass the Android VPN routing table.
//
// Responsibility split (Rust kernel rust/diting-proxy-core): the config normalization, the SOCKS5
// greeting / method / auth / request / reply codec, the address and UDP datagram framing and the
// HTTP CONNECT request bytes all live in the kernel. Go keeps every socket, deadline, the status
// channel, the `net.Conn` / `net.PacketConn` types and the proxy-vs-direct decision, and it still
// reads the HTTP CONNECT reply with `http.ReadResponse` (the `bufio` behaviour is part of the
// contract being preserved).
//
// If the kernel is unavailable the proxy feature is unusable: `ConfigureOutboundProxy` reports it
// and every proxied dial fails with that error. Direct traffic keeps working, and so does
// disabling the proxy (a disabled config returns before the kernel is asked).

package tunnel

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

var errOutboundUDPUnsupported = errors.New("outbound proxy does not support UDP")

type outboundProxyConfig struct {
	Enabled  bool   `json:"enabled"`
	Protocol string `json:"protocol"`
	Host     string `json:"host"`
	Port     int    `json:"port"`
	Username string `json:"username"`
	Password string `json:"password"`
	// Scope is "all" (default) or "apps". In "apps" mode only flows owned by UIDs are proxied,
	// and the engine's own DNS upstream dials stay direct.
	Scope string `json:"scope"`
	UIDs  []int  `json:"uids"`

	uidSet map[int]struct{}
}

const outboundScopeApps = "apps"

// socksCommandConnect is the SOCKS5 command every proxied TCP dial issues; UDP ASSOCIATE has its
// own fixed request in the kernel (`socksUDPAssociateNative`).
const socksCommandConnect byte = 0x01

// socksMethodUserPass is the sub-negotiation method the proxy selects for credentials.
const socksMethodUserPass byte = 0x02

// socksReplyBufferSize covers the largest reply frame: header + length byte + 255-byte domain +
// port (`socks5::parse_reply` reports the exact length, this is the ceiling).
const socksReplyBufferSize = 4 + 1 + 255 + 2

// socksDatagramHeaderSize is the ceiling `ReadFrom` adds on top of a payload: three reserved
// bytes, an address type, a length byte, a 255-byte domain and the port.
const socksDatagramHeaderSize = 3 + 1 + 1 + 255 + 2

// perApp reports whether only the selected UIDs are proxied.
func (c outboundProxyConfig) perApp() bool {
	return c.Enabled && c.Scope == outboundScopeApps
}

// proxiesUID reports whether a flow owned by uid goes through the proxy. Unknown owners stay direct
// in per-app mode so an unselected app is never pushed into the proxy by mistake.
func (c outboundProxyConfig) proxiesUID(uid int) bool {
	if !c.perApp() {
		return true
	}
	if uid == UIDUnknown {
		return false
	}
	_, ok := c.uidSet[uid]
	return ok
}

type flowOutbound interface {
	DialTCP(ctx context.Context, target string) (net.Conn, error)
	DialUDP(ctx context.Context, target string) (net.Conn, error)
	OpenPacket(ctx context.Context) (net.PacketConn, error)
	SupportsUDP() bool
	Close() error
}

type directFlowOutbound struct{ protectFn func(fd int) bool }

func (d *directFlowOutbound) dialer() *net.Dialer {
	return &net.Dialer{Timeout: flowDialTimeout, Control: protectedControl(d.protectFn)}
}

func (d *directFlowOutbound) DialTCP(ctx context.Context, target string) (net.Conn, error) {
	return d.dialer().DialContext(ctx, "tcp", target)
}

func (d *directFlowOutbound) DialUDP(ctx context.Context, target string) (net.Conn, error) {
	return d.dialer().DialContext(ctx, "udp", target)
}

func (d *directFlowOutbound) OpenPacket(ctx context.Context) (net.PacketConn, error) {
	lc := net.ListenConfig{Control: protectedControl(d.protectFn)}
	return lc.ListenPacket(ctx, "udp", "0.0.0.0:0")
}

func (d *directFlowOutbound) SupportsUDP() bool { return true }
func (d *directFlowOutbound) Close() error      { return nil }

type proxyStatusEvent struct {
	state   string
	message string
}

type proxyFlowOutbound struct {
	config      outboundProxyConfig
	direct      *directFlowOutbound
	report      func(string, string)
	mu          sync.Mutex
	lastState   string
	lastMessage string
	statusCh    chan proxyStatusEvent
	stopCh      chan struct{}
	closeOnce   sync.Once
}

// parseOutboundProxyConfig decodes the config JSON and hands the fields to the kernel for
// validation and normalization. A disabled config returns before the kernel is consulted, so the
// proxy can always be switched off.
func parseOutboundProxyConfig(raw string) (outboundProxyConfig, error) {
	if strings.TrimSpace(raw) == "" {
		return outboundProxyConfig{}, nil
	}
	var cfg outboundProxyConfig
	if err := json.Unmarshal([]byte(raw), &cfg); err != nil {
		return cfg, fmt.Errorf("invalid outbound proxy config: %w", err)
	}
	if !cfg.Enabled {
		return cfg, nil
	}
	normalized, err := normalizeOutboundProxyNative(cfg)
	if err != nil {
		return cfg, err
	}
	cfg.Enabled = normalized.enabled
	cfg.Protocol = normalized.protocol
	cfg.Host = normalized.host
	cfg.Port = normalized.port
	cfg.Scope = normalized.scope
	cfg.uidSet = make(map[int]struct{}, len(normalized.uids))
	for _, uid := range normalized.uids {
		cfg.uidSet[uid] = struct{}{}
	}
	return cfg, nil
}

func newFlowOutbound(cfg outboundProxyConfig, protectFn func(fd int) bool, report func(string, string)) flowOutbound {
	direct := &directFlowOutbound{protectFn: protectFn}
	if !cfg.Enabled {
		return direct
	}
	p := &proxyFlowOutbound{
		config:   cfg,
		direct:   direct,
		report:   report,
		statusCh: make(chan proxyStatusEvent, 16),
		stopCh:   make(chan struct{}),
	}
	if report != nil {
		go p.dispatchLoop()
	}
	return p
}

func (p *proxyFlowOutbound) dispatchLoop() {
	for {
		select {
		case evt := <-p.statusCh:
			if p.report != nil {
				p.report(evt.state, evt.message)
			}
		case <-p.stopCh:
			return
		}
	}
}

func (p *proxyFlowOutbound) status(state string, err error) {
	if p.report == nil {
		return
	}
	message := ""
	if err != nil {
		message = err.Error()
	}
	p.mu.Lock()
	if p.lastState == state && p.lastMessage == message {
		p.mu.Unlock()
		return
	}
	p.lastState = state
	p.lastMessage = message
	p.mu.Unlock()

	select {
	case p.statusCh <- proxyStatusEvent{state: state, message: message}:
	case <-p.stopCh:
	default:
		go func() {
			select {
			case p.statusCh <- proxyStatusEvent{state: state, message: message}:
			case <-p.stopCh:
			}
		}()
	}
}

func (p *proxyFlowOutbound) proxyAddress() string {
	return net.JoinHostPort(p.config.Host, strconv.Itoa(p.config.Port))
}

func (p *proxyFlowOutbound) DialTCP(ctx context.Context, target string) (net.Conn, error) {
	conn, err := p.direct.DialTCP(ctx, p.proxyAddress())
	if err != nil {
		err = fmt.Errorf("connect outbound proxy: %w", err)
		p.status("error", err)
		return nil, err
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	} else {
		_ = conn.SetDeadline(time.Now().Add(flowDialTimeout))
	}
	if p.config.Protocol == "socks5" {
		err = p.socksConnect(conn, socksCommandConnect, target)
	} else {
		err = p.httpConnect(conn, target)
	}
	_ = conn.SetDeadline(time.Time{})
	if err != nil {
		_ = conn.Close()
		p.status("error", err)
		return nil, err
	}
	p.status("ready", nil)
	return conn, nil
}

func (p *proxyFlowOutbound) DialUDP(ctx context.Context, target string) (net.Conn, error) {
	if !p.SupportsUDP() {
		return nil, errOutboundUDPUnsupported
	}
	packet, err := p.OpenPacket(ctx)
	if err != nil {
		return nil, err
	}
	host, _, err := net.SplitHostPort(target)
	if err != nil {
		packet.Close()
		return nil, err
	}
	var addr net.Addr = unresolvedUDPAddr(target)
	if net.ParseIP(host) != nil {
		resolved, resolveErr := net.ResolveUDPAddr("udp", target)
		if resolveErr != nil {
			packet.Close()
			return nil, resolveErr
		}
		addr = resolved
	}
	return &packetConnAdapter{PacketConn: packet, remote: addr}, nil
}

func (p *proxyFlowOutbound) OpenPacket(ctx context.Context) (net.PacketConn, error) {
	if !p.SupportsUDP() {
		return nil, errOutboundUDPUnsupported
	}
	control, err := p.direct.DialTCP(ctx, p.proxyAddress())
	if err != nil {
		err = fmt.Errorf("connect SOCKS5 proxy: %w", err)
		p.status("error", err)
		return nil, err
	}
	_ = control.SetDeadline(time.Now().Add(flowDialTimeout))
	if err := p.socksNegotiate(control); err != nil {
		control.Close()
		p.status("error", err)
		return nil, err
	}
	request, err := socksUDPAssociateNative()
	if err == nil {
		_, err = control.Write(request)
	}
	if err != nil {
		control.Close()
		err = fmt.Errorf("SOCKS5 UDP associate: %w", err)
		p.status("error", err)
		return nil, err
	}
	relay, err := readSocksReply(control)
	if err != nil {
		control.Close()
		p.status("error", err)
		return nil, err
	}
	_ = control.SetDeadline(time.Time{})
	relayAddr, err := net.ResolveUDPAddr("udp", relay)
	if err != nil {
		control.Close()
		err = fmt.Errorf("SOCKS5 UDP relay address: %w", err)
		p.status("error", err)
		return nil, err
	}
	if relayAddr.IP == nil || relayAddr.IP.IsUnspecified() {
		proxyIP := net.ParseIP(p.config.Host)
		relayAddr.IP = proxyIP
	}
	base, err := p.direct.OpenPacket(ctx)
	if err != nil {
		control.Close()
		p.status("error", err)
		return nil, err
	}
	p.status("ready", nil)
	return &socksPacketConn{PacketConn: base, control: control, relay: relayAddr}, nil
}

func (p *proxyFlowOutbound) SupportsUDP() bool { return p.config.Protocol == "socks5" }
func (p *proxyFlowOutbound) Close() error {
	p.closeOnce.Do(func() {
		close(p.stopCh)
	})
	return nil
}

func (p *proxyFlowOutbound) socksNegotiate(conn net.Conn) error {
	request, err := socksGreetingNative(p.config.Username, p.config.Password)
	if err != nil {
		return err
	}
	if _, err := conn.Write(request); err != nil {
		return fmt.Errorf("SOCKS5 greeting: %w", err)
	}
	reply := make([]byte, 2)
	if _, err := io.ReadFull(conn, reply); err != nil {
		return errors.New("invalid SOCKS5 greeting response")
	}
	method, err := socksMethodReplyNative(reply)
	if err != nil {
		return err
	}
	if method != socksMethodUserPass {
		return nil
	}
	auth, err := socksAuthNative(p.config.Username, p.config.Password)
	if err != nil {
		return err
	}
	if _, err := conn.Write(auth); err != nil {
		return fmt.Errorf("SOCKS5 authentication: %w", err)
	}
	if _, err := io.ReadFull(conn, reply); err != nil {
		return errors.New("SOCKS5 authentication failed")
	}
	return socksAuthReplyNative(reply)
}

func (p *proxyFlowOutbound) socksConnect(conn net.Conn, command byte, target string) error {
	if err := p.socksNegotiate(conn); err != nil {
		return err
	}
	request, err := socksRequestNative(command, target)
	if err != nil {
		return err
	}
	if _, err := conn.Write(request); err != nil {
		return fmt.Errorf("SOCKS5 request: %w", err)
	}
	_, err = readSocksReply(conn)
	return err
}

func (p *proxyFlowOutbound) httpConnect(conn net.Conn, target string) error {
	request, err := httpConnectRequestNative(target, p.config.Username, p.config.Password)
	if err != nil {
		return err
	}
	if _, err := conn.Write(request); err != nil {
		return fmt.Errorf("HTTP CONNECT write: %w", err)
	}
	// The reply is still parsed by `net/http`: the request passed here is the same shape the old
	// code built, so `resp` (status text and body) is unchanged.
	sent := &http.Request{
		Method: http.MethodConnect,
		URL:    &url.URL{Opaque: target},
		Host:   target,
		Header: make(http.Header),
	}
	resp, err := http.ReadResponse(bufio.NewReader(conn), sent)
	if err != nil {
		return fmt.Errorf("HTTP CONNECT response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return fmt.Errorf("HTTP proxy returned %s", resp.Status)
	}
	return nil
}

// readSocksReply reads a reply frame, asking the kernel how many bytes it still needs. Only the
// first read is wrapped: the address and port reads used to return `io` errors verbatim.
func readSocksReply(r io.Reader) (string, error) {
	buf := make([]byte, socksReplyBufferSize)
	read := 0
	for {
		address, needed, err := socksReplyNative(buf[:read])
		if err != nil {
			return "", err
		}
		if needed == 0 {
			return address, nil
		}
		if needed > len(buf) {
			return "", fmt.Errorf("SOCKS5 reply frame is %d bytes", needed)
		}
		first := read == 0
		got, err := io.ReadFull(r, buf[read:needed])
		read += got
		if err != nil {
			if first {
				return "", fmt.Errorf("SOCKS5 response: %w", err)
			}
			return "", err
		}
	}
}

type socksPacketConn struct {
	net.PacketConn
	control net.Conn
	relay   *net.UDPAddr
}

func (c *socksPacketConn) WriteTo(payload []byte, target net.Addr) (int, error) {
	packet, err := socksDatagramNative(target.String(), payload)
	if err != nil {
		return 0, err
	}
	if _, err := c.PacketConn.WriteTo(packet, c.relay); err != nil {
		return 0, err
	}
	return len(payload), nil
}

func (c *socksPacketConn) ReadFrom(payload []byte) (int, net.Addr, error) {
	buf := make([]byte, len(payload)+socksDatagramHeaderSize)
	n, _, err := c.PacketConn.ReadFrom(buf)
	if err != nil {
		return 0, nil, err
	}
	if n < 4 || buf[0] != 0 || buf[1] != 0 || buf[2] != 0 {
		return 0, nil, errors.New("invalid or fragmented SOCKS5 UDP packet")
	}
	address, hostIsIP, offset, err := socksDatagramParseNative(buf[3:n])
	if err != nil {
		return 0, nil, err
	}
	data := buf[3+offset : n]
	count := copy(payload, data)
	var addr net.Addr = unresolvedUDPAddr(address)
	if hostIsIP {
		addr, _ = net.ResolveUDPAddr("udp", address)
	}
	return count, addr, nil
}

func (c *socksPacketConn) Close() error {
	_ = c.control.Close()
	return c.PacketConn.Close()
}

type packetConnAdapter struct {
	net.PacketConn
	remote net.Addr
}

func (c *packetConnAdapter) Read(p []byte) (int, error) {
	n, _, err := c.ReadFrom(p)
	return n, err
}
func (c *packetConnAdapter) Write(p []byte) (int, error) { return c.WriteTo(p, c.remote) }
func (c *packetConnAdapter) RemoteAddr() net.Addr        { return c.remote }
