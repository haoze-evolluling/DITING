// proxy_native_payload.go is the byte layout the proxy kernel speaks
// (rust/diting-proxy-core/src/payload.rs) plus the typed wrappers around it.
//
// It lives outside the cgo file so the encode/decode side can be tested without a C toolchain: a
// drifted layout byte or a length that disagrees with the payload is rejected here, before any
// kernel call.

package tunnel

import (
	"encoding/binary"
	"errors"
	"fmt"
)

// proxyPayloadLayoutVersion must match `payload::LAYOUT_VERSION`.
const proxyPayloadLayoutVersion = 1

// Opcodes, in the order of the table in rust/diting-proxy-core/src/payload.rs.
const (
	proxyOpConfigure         byte = 0
	proxyOpSocksGreeting     byte = 1
	proxyOpSocksMethodReply  byte = 2
	proxyOpSocksAuth         byte = 3
	proxyOpSocksAuthReply    byte = 4
	proxyOpSocksRequest      byte = 5
	proxyOpSocksUDPAssociate byte = 6
	proxyOpSocksReply        byte = 7
	proxyOpSocksDatagram     byte = 8
	proxyOpSocksDatagramRead byte = 9
	proxyOpHTTPConnect       byte = 10
)

// Response envelope statuses.
const (
	proxyStatusOK    byte = 0
	proxyStatusError byte = 1
)

// errProxyUnavailable is what the non-cgo build and a missing library report.
var errProxyUnavailable = errors.New("Rust proxy kernel is unavailable")

// normalizedProxyConfig is the kernel's validated view of an outbound proxy config.
type normalizedProxyConfig struct {
	enabled  bool
	protocol string
	host     string
	port     int
	scope    string
	uids     []int
}

// run sends one request payload and returns the response body, turning an operation error into a
// Go error and refusing a malformed envelope.
func runProxyRequest(request []byte) ([]byte, error) {
	response, err := proxyCall(request)
	if err != nil {
		return nil, err
	}
	if len(response) == 0 {
		return nil, errors.New("proxy kernel response is empty")
	}
	switch response[0] {
	case proxyStatusOK:
		return response[1:], nil
	case proxyStatusError:
		reader := proxyReader{payload: response[1:]}
		message, ok := reader.text()
		if !ok || !reader.atEnd() {
			return nil, errors.New("proxy kernel returned a malformed error")
		}
		return nil, errors.New(message)
	default:
		return nil, fmt.Errorf("proxy kernel response status %d", response[0])
	}
}

// runProxyBytes is runProxyRequest for the operations whose result is one byte string.
func runProxyBytes(request []byte) ([]byte, error) {
	body, err := runProxyRequest(request)
	if err != nil {
		return nil, err
	}
	reader := proxyReader{payload: body}
	value, ok := reader.bytes()
	if !ok || !reader.atEnd() {
		return nil, errors.New("proxy kernel returned a malformed byte body")
	}
	return value, nil
}

// proxyRequest builds the envelope: layout byte, opcode and body.
func proxyRequest(op byte, body []byte) []byte {
	request := make([]byte, 0, 2+len(body))
	request = append(request, proxyPayloadLayoutVersion, op)
	return append(request, body...)
}

type proxyWriter struct{ buf []byte }

func (w *proxyWriter) byte(value byte) { w.buf = append(w.buf, value) }

func (w *proxyWriter) text(value string) { w.bytes([]byte(value)) }

func (w *proxyWriter) bytes(value []byte) {
	w.buf = binary.LittleEndian.AppendUint32(w.buf, uint32(len(value)))
	w.buf = append(w.buf, value...)
}

func (w *proxyWriter) int64(value int64) {
	w.buf = binary.LittleEndian.AppendUint64(w.buf, uint64(value))
}

type proxyReader struct {
	payload  []byte
	position int
}

func (r *proxyReader) atEnd() bool { return r.position == len(r.payload) }

func (r *proxyReader) take(length int) ([]byte, bool) {
	if length < 0 || length > len(r.payload)-r.position {
		return nil, false
	}
	slice := r.payload[r.position : r.position+length]
	r.position += length
	return slice, true
}

func (r *proxyReader) byte() (byte, bool) {
	slice, ok := r.take(1)
	if !ok {
		return 0, false
	}
	return slice[0], true
}

func (r *proxyReader) uint32() (uint32, bool) {
	slice, ok := r.take(4)
	if !ok {
		return 0, false
	}
	return binary.LittleEndian.Uint32(slice), true
}

func (r *proxyReader) int64() (int64, bool) {
	slice, ok := r.take(8)
	if !ok {
		return 0, false
	}
	return int64(binary.LittleEndian.Uint64(slice)), true
}

func (r *proxyReader) bytes() ([]byte, bool) {
	length, ok := r.uint32()
	if !ok {
		return nil, false
	}
	return r.take(int(length))
}

func (r *proxyReader) text() (string, bool) {
	slice, ok := r.bytes()
	if !ok {
		return "", false
	}
	return string(slice), true
}

// normalizeOutboundProxyNative validates and normalizes a decoded config.
func normalizeOutboundProxyNative(cfg outboundProxyConfig) (normalizedProxyConfig, error) {
	var writer proxyWriter
	if cfg.Enabled {
		writer.byte(1)
	} else {
		writer.byte(0)
	}
	writer.text(cfg.Protocol)
	writer.text(cfg.Host)
	writer.int64(int64(cfg.Port))
	writer.text(cfg.Username)
	writer.text(cfg.Password)
	writer.text(cfg.Scope)
	writer.buf = binary.LittleEndian.AppendUint32(writer.buf, uint32(len(cfg.UIDs)))
	for _, uid := range cfg.UIDs {
		writer.int64(int64(uid))
	}

	body, err := runProxyRequest(proxyRequest(proxyOpConfigure, writer.buf))
	if err != nil {
		return normalizedProxyConfig{}, err
	}
	reader := proxyReader{payload: body}
	enabled, ok := reader.byte()
	if !ok {
		return normalizedProxyConfig{}, errors.New("proxy config response is truncated")
	}
	var normalized normalizedProxyConfig
	normalized.enabled = enabled != 0
	if normalized.protocol, ok = reader.text(); !ok {
		return normalizedProxyConfig{}, errors.New("proxy config response has no protocol")
	}
	if normalized.host, ok = reader.text(); !ok {
		return normalizedProxyConfig{}, errors.New("proxy config response has no host")
	}
	port, ok := reader.int64()
	if !ok {
		return normalizedProxyConfig{}, errors.New("proxy config response has no port")
	}
	normalized.port = int(port)
	if normalized.scope, ok = reader.text(); !ok {
		return normalizedProxyConfig{}, errors.New("proxy config response has no scope")
	}
	count, ok := reader.uint32()
	if !ok {
		return normalizedProxyConfig{}, errors.New("proxy config response has no uid count")
	}
	normalized.uids = make([]int, 0, count)
	for i := uint32(0); i < count; i++ {
		uid, ok := reader.int64()
		if !ok {
			return normalizedProxyConfig{}, errors.New("proxy config response has a short uid list")
		}
		normalized.uids = append(normalized.uids, int(uid))
	}
	if !reader.atEnd() {
		return normalizedProxyConfig{}, errors.New("proxy config response has trailing bytes")
	}
	return normalized, nil
}

// socksGreetingNative builds the SOCKS5 greeting for the configured credentials.
func socksGreetingNative(username, password string) ([]byte, error) {
	var writer proxyWriter
	writer.text(username)
	writer.text(password)
	return runProxyBytes(proxyRequest(proxyOpSocksGreeting, writer.buf))
}

// socksMethodReplyNative reads the proxy's method selection; the value is 0x00 or 0x02.
func socksMethodReplyNative(reply []byte) (byte, error) {
	var writer proxyWriter
	writer.bytes(reply)
	body, err := runProxyRequest(proxyRequest(proxyOpSocksMethodReply, writer.buf))
	if err != nil {
		return 0, err
	}
	reader := proxyReader{payload: body}
	method, ok := reader.byte()
	if !ok || !reader.atEnd() {
		return 0, errors.New("proxy method reply is malformed")
	}
	return method, nil
}

// socksAuthNative builds the username/password sub-negotiation request.
func socksAuthNative(username, password string) ([]byte, error) {
	var writer proxyWriter
	writer.text(username)
	writer.text(password)
	return runProxyBytes(proxyRequest(proxyOpSocksAuth, writer.buf))
}

// socksAuthReplyNative validates the sub-negotiation reply.
func socksAuthReplyNative(reply []byte) error {
	var writer proxyWriter
	writer.bytes(reply)
	_, err := runProxyRequest(proxyRequest(proxyOpSocksAuthReply, writer.buf))
	return err
}

// socksRequestNative builds the command request (version, command, address).
func socksRequestNative(command byte, target string) ([]byte, error) {
	var writer proxyWriter
	writer.byte(command)
	writer.text(target)
	return runProxyBytes(proxyRequest(proxyOpSocksRequest, writer.buf))
}

// socksUDPAssociateNative builds the fixed UDP ASSOCIATE request.
func socksUDPAssociateNative() ([]byte, error) {
	return runProxyBytes(proxyRequest(proxyOpSocksUDPAssociate, nil))
}

// socksReplyNative parses a reply frame. `needed` is the total frame length when the buffer is
// still short (0 once `address` is valid, which is never empty for a complete frame).
func socksReplyNative(frame []byte) (address string, needed int, err error) {
	var writer proxyWriter
	writer.bytes(frame)
	body, err := runProxyRequest(proxyRequest(proxyOpSocksReply, writer.buf))
	if err != nil {
		return "", 0, err
	}
	reader := proxyReader{payload: body}
	kind, ok := reader.byte()
	if !ok {
		return "", 0, errors.New("proxy reply response is truncated")
	}
	switch kind {
	case 0:
		address, ok = reader.text()
		if !ok || !reader.atEnd() {
			return "", 0, errors.New("proxy reply response has no address")
		}
		return address, 0, nil
	case 1:
		total, ok := reader.uint32()
		if !ok || !reader.atEnd() {
			return "", 0, errors.New("proxy reply response has no frame length")
		}
		return "", int(total), nil
	default:
		return "", 0, fmt.Errorf("proxy reply response kind %d", kind)
	}
}

// socksDatagramNative frames one UDP payload for the relay.
func socksDatagramNative(target string, payload []byte) ([]byte, error) {
	var writer proxyWriter
	writer.text(target)
	writer.bytes(payload)
	return runProxyBytes(proxyRequest(proxyOpSocksDatagram, writer.buf))
}

// socksDatagramParseNative decodes the address part of a reply datagram, returning the offset of
// the payload inside the bytes it was given.
func socksDatagramParseNative(datagram []byte) (string, bool, int, error) {
	var writer proxyWriter
	writer.bytes(datagram)
	body, err := runProxyRequest(proxyRequest(proxyOpSocksDatagramRead, writer.buf))
	if err != nil {
		return "", false, 0, err
	}
	reader := proxyReader{payload: body}
	address, ok := reader.text()
	if !ok {
		return "", false, 0, errors.New("datagram response has no address")
	}
	flag, ok := reader.byte()
	if !ok {
		return "", false, 0, errors.New("datagram response has no host flag")
	}
	position, ok := reader.uint32()
	if !ok || !reader.atEnd() {
		return "", false, 0, errors.New("datagram response has no offset")
	}
	return address, flag != 0, int(position), nil
}

// httpConnectRequestNative serializes the CONNECT request (`http.Request.Write` output).
func httpConnectRequestNative(target, username, password string) ([]byte, error) {
	var writer proxyWriter
	writer.text(target)
	writer.text(username)
	writer.text(password)
	return runProxyBytes(proxyRequest(proxyOpHTTPConnect, writer.buf))
}
