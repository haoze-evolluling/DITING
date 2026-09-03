package tunnel

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
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

type proxyFlowOutbound struct {
	config outboundProxyConfig
	direct *directFlowOutbound
	report func(string, string)
}

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
	cfg.Protocol = strings.ToLower(strings.TrimSpace(cfg.Protocol))
	if cfg.Protocol != "socks5" && cfg.Protocol != "http" {
		return cfg, fmt.Errorf("unsupported outbound proxy protocol %q", cfg.Protocol)
	}
	ip := net.ParseIP(strings.TrimSpace(cfg.Host))
	if ip == nil || !ip.IsLoopback() {
		return cfg, errors.New("outbound proxy host must be 127.0.0.1 or ::1")
	}
	cfg.Host = ip.String()
	if cfg.Port < 1 || cfg.Port > 65535 {
		return cfg, errors.New("outbound proxy port must be between 1 and 65535")
	}
	if len(cfg.Username) > 255 || len(cfg.Password) > 255 {
		return cfg, errors.New("SOCKS5 credentials must not exceed 255 bytes")
	}
	return cfg, nil
}

func newFlowOutbound(cfg outboundProxyConfig, protectFn func(fd int) bool, report func(string, string)) flowOutbound {
	direct := &directFlowOutbound{protectFn: protectFn}
	if !cfg.Enabled {
		return direct
	}
	return &proxyFlowOutbound{config: cfg, direct: direct, report: report}
}

func (p *proxyFlowOutbound) status(state string, err error) {
	if p.report == nil {
		return
	}
	message := ""
	if err != nil {
		message = err.Error()
	}
	p.report(state, message)
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
		err = p.socksConnect(conn, 0x01, target)
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
		p.status("error", errOutboundUDPUnsupported)
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
		p.status("error", errOutboundUDPUnsupported)
		return nil, errOutboundUDPUnsupported
	}
	control, err := p.direct.DialTCP(ctx, p.proxyAddress())
	if err != nil {
		return nil, fmt.Errorf("connect SOCKS5 proxy: %w", err)
	}
	_ = control.SetDeadline(time.Now().Add(flowDialTimeout))
	if err := p.socksNegotiate(control); err != nil {
		control.Close()
		return nil, err
	}
	if _, err := control.Write([]byte{0x05, 0x03, 0x00, 0x01, 0, 0, 0, 0, 0, 0}); err != nil {
		control.Close()
		return nil, fmt.Errorf("SOCKS5 UDP associate: %w", err)
	}
	relay, err := readSocksReply(control)
	if err != nil {
		control.Close()
		return nil, err
	}
	_ = control.SetDeadline(time.Time{})
	relayAddr, err := net.ResolveUDPAddr("udp", relay)
	if err != nil {
		control.Close()
		return nil, fmt.Errorf("SOCKS5 UDP relay address: %w", err)
	}
	if relayAddr.IP == nil || relayAddr.IP.IsUnspecified() {
		proxyIP := net.ParseIP(p.config.Host)
		relayAddr.IP = proxyIP
	}
	base, err := p.direct.OpenPacket(ctx)
	if err != nil {
		control.Close()
		return nil, err
	}
	p.status("ready", nil)
	return &socksPacketConn{PacketConn: base, control: control, relay: relayAddr}, nil
}

func (p *proxyFlowOutbound) SupportsUDP() bool { return p.config.Protocol == "socks5" }
func (p *proxyFlowOutbound) Close() error      { return nil }

func (p *proxyFlowOutbound) socksNegotiate(conn net.Conn) error {
	methods := []byte{0x00}
	if p.config.Username != "" || p.config.Password != "" {
		methods = append(methods, 0x02)
	}
	request := append([]byte{0x05, byte(len(methods))}, methods...)
	if _, err := conn.Write(request); err != nil {
		return fmt.Errorf("SOCKS5 greeting: %w", err)
	}
	reply := make([]byte, 2)
	if _, err := io.ReadFull(conn, reply); err != nil || reply[0] != 0x05 {
		return errors.New("invalid SOCKS5 greeting response")
	}
	if reply[1] == 0xff {
		return errors.New("SOCKS5 proxy rejected authentication methods")
	}
	if reply[1] == 0x02 {
		user, pass := []byte(p.config.Username), []byte(p.config.Password)
		auth := []byte{0x01, byte(len(user))}
		auth = append(auth, user...)
		auth = append(auth, byte(len(pass)))
		auth = append(auth, pass...)
		if _, err := conn.Write(auth); err != nil {
			return fmt.Errorf("SOCKS5 authentication: %w", err)
		}
		if _, err := io.ReadFull(conn, reply); err != nil || reply[1] != 0x00 {
			return errors.New("SOCKS5 authentication failed")
		}
	} else if reply[1] != 0x00 {
		return fmt.Errorf("unsupported SOCKS5 authentication method %d", reply[1])
	}
	return nil
}

func (p *proxyFlowOutbound) socksConnect(conn net.Conn, command byte, target string) error {
	if err := p.socksNegotiate(conn); err != nil {
		return err
	}
	addr, err := encodeSocksAddress(target)
	if err != nil {
		return err
	}
	request := append([]byte{0x05, command, 0x00}, addr...)
	if _, err := conn.Write(request); err != nil {
		return fmt.Errorf("SOCKS5 request: %w", err)
	}
	_, err = readSocksReply(conn)
	return err
}

func (p *proxyFlowOutbound) httpConnect(conn net.Conn, target string) error {
	req := &http.Request{Method: http.MethodConnect, URL: &url.URL{Opaque: target}, Host: target, Header: make(http.Header)}
	if p.config.Username != "" || p.config.Password != "" {
		token := base64.StdEncoding.EncodeToString([]byte(p.config.Username + ":" + p.config.Password))
		req.Header.Set("Proxy-Authorization", "Basic "+token)
	}
	if err := req.Write(conn); err != nil {
		return fmt.Errorf("HTTP CONNECT write: %w", err)
	}
	resp, err := http.ReadResponse(bufio.NewReader(conn), req)
	if err != nil {
		return fmt.Errorf("HTTP CONNECT response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return fmt.Errorf("HTTP proxy returned %s", resp.Status)
	}
	return nil
}

func encodeSocksAddress(target string) ([]byte, error) {
	host, portText, err := net.SplitHostPort(target)
	if err != nil {
		return nil, fmt.Errorf("invalid target %q: %w", target, err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port < 0 || port > 65535 {
		return nil, fmt.Errorf("invalid target port %q", portText)
	}
	var out []byte
	if ip := net.ParseIP(host); ip != nil {
		if v4 := ip.To4(); v4 != nil {
			out = append([]byte{0x01}, v4...)
		} else {
			out = append([]byte{0x04}, ip.To16()...)
		}
	} else {
		if len(host) == 0 || len(host) > 255 {
			return nil, errors.New("SOCKS5 target hostname length is invalid")
		}
		out = append([]byte{0x03, byte(len(host))}, []byte(host)...)
	}
	return append(out, byte(port>>8), byte(port)), nil
}

func readSocksReply(r io.Reader) (string, error) {
	header := make([]byte, 4)
	if _, err := io.ReadFull(r, header); err != nil {
		return "", fmt.Errorf("SOCKS5 response: %w", err)
	}
	if header[0] != 0x05 || header[1] != 0x00 {
		return "", fmt.Errorf("SOCKS5 request failed with code %d", header[1])
	}
	host, err := readSocksHost(r, header[3])
	if err != nil {
		return "", err
	}
	portBytes := make([]byte, 2)
	if _, err := io.ReadFull(r, portBytes); err != nil {
		return "", err
	}
	return net.JoinHostPort(host, strconv.Itoa(int(binary.BigEndian.Uint16(portBytes)))), nil
}

func readSocksHost(r io.Reader, atyp byte) (string, error) {
	var size int
	switch atyp {
	case 0x01:
		size = 4
	case 0x04:
		size = 16
	case 0x03:
		length := []byte{0}
		if _, err := io.ReadFull(r, length); err != nil {
			return "", err
		}
		size = int(length[0])
	default:
		return "", fmt.Errorf("invalid SOCKS5 address type %d", atyp)
	}
	buf := make([]byte, size)
	if _, err := io.ReadFull(r, buf); err != nil {
		return "", err
	}
	if atyp == 0x03 {
		return string(buf), nil
	}
	return net.IP(buf).String(), nil
}

type socksPacketConn struct {
	net.PacketConn
	control net.Conn
	relay   *net.UDPAddr
}

func (c *socksPacketConn) WriteTo(payload []byte, target net.Addr) (int, error) {
	header, err := encodeSocksAddress(target.String())
	if err != nil {
		return 0, err
	}
	packet := append([]byte{0, 0, 0}, header...)
	packet = append(packet, payload...)
	if _, err := c.PacketConn.WriteTo(packet, c.relay); err != nil {
		return 0, err
	}
	return len(payload), nil
}

func (c *socksPacketConn) ReadFrom(payload []byte) (int, net.Addr, error) {
	buf := make([]byte, len(payload)+262)
	n, _, err := c.PacketConn.ReadFrom(buf)
	if err != nil {
		return 0, nil, err
	}
	if n < 4 || buf[0] != 0 || buf[1] != 0 || buf[2] != 0 {
		return 0, nil, errors.New("invalid or fragmented SOCKS5 UDP packet")
	}
	host, port, offset, err := decodeSocksDatagramAddress(buf[3:n])
	if err != nil {
		return 0, nil, err
	}
	data := buf[3+offset : n]
	count := copy(payload, data)
	address := net.JoinHostPort(host, strconv.Itoa(port))
	var addr net.Addr = unresolvedUDPAddr(address)
	if net.ParseIP(host) != nil {
		addr, _ = net.ResolveUDPAddr("udp", address)
	}
	return count, addr, nil
}

func (c *socksPacketConn) Close() error {
	_ = c.control.Close()
	return c.PacketConn.Close()
}

func decodeSocksDatagramAddress(raw []byte) (string, int, int, error) {
	reader := bytes.NewReader(raw)
	atyp, err := reader.ReadByte()
	if err != nil {
		return "", 0, 0, err
	}
	host, err := readSocksHost(reader, atyp)
	if err != nil {
		return "", 0, 0, err
	}
	portBytes := make([]byte, 2)
	if _, err := io.ReadFull(reader, portBytes); err != nil {
		return "", 0, 0, err
	}
	return host, int(binary.BigEndian.Uint16(portBytes)), len(raw) - reader.Len(), nil
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
func (c *packetConnAdapter) RemoteAddr() net.Addr         { return c.remote }
