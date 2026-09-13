package tunnel

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"strings"
	"time"
)

// mitm_sniffer.go — peek at the first bytes of a flow, classify it as
// TLS or HTTP, and extract the SNI / Host header value for MITM
// routing decisions.

// peekFlow reads the first batch of client data (up to maxBytes) and
// returns the peeked bytes plus a Reader that replays them followed by
// the rest of the stream. One conn.Read is issued instead of
// bufio.Reader.Peek(maxBytes), which blocks until maxBytes arrive or the
// deadline fires (seconds of latency on a typical 200-600B ClientHello).
// The caller keeps using conn for writes; only reads come from the Reader.
func peekFlow(conn net.Conn, maxBytes int, timeout time.Duration) ([]byte, io.Reader, error) {
	conn.SetReadDeadline(time.Now().Add(timeout))
	defer conn.SetReadDeadline(time.Time{})

	buf := make([]byte, maxBytes)
	n, err := conn.Read(buf)
	if n == 0 {
		return nil, nil, err
	}
	peeked := buf[:n]
	return peeked, io.MultiReader(bytes.NewReader(peeked), conn), nil
}

// parseClientHelloSNI extracts the server_name extension from a TLS
// ClientHello record. Returns "" if the bytes aren't a ClientHello or
// the SNI extension is absent. No allocations on the unhappy path —
// this runs on every HTTPS connection.
func parseClientHelloSNI(record []byte) string {
	// TLS record layer: ContentType(1) Version(2) Length(2) Payload
	if len(record) < 5 || record[0] != 0x16 { // handshake
		return ""
	}
	recLen := int(binary.BigEndian.Uint16(record[3:5]))
	if recLen > len(record)-5 {
		recLen = len(record) - 5 // truncated but might still contain SNI
	}
	body := record[5 : 5+recLen]

	// Handshake header: Type(1) Length(3)
	if len(body) < 4 || body[0] != 0x01 { // 0x01 = ClientHello
		return ""
	}
	// We ignore the handshake length check — use body slice directly.
	ch := body[4:]

	// ClientHello:
	//   legacy_version(2) random(32) session_id(<=32 prefixed)
	//   cipher_suites cm extensions
	if len(ch) < 2+32+1 {
		return ""
	}
	p := 34
	sidLen := int(ch[p])
	p += 1 + sidLen
	if p+2 > len(ch) {
		return ""
	}
	csLen := int(binary.BigEndian.Uint16(ch[p : p+2]))
	p += 2 + csLen
	if p+1 > len(ch) {
		return ""
	}
	cmLen := int(ch[p])
	p += 1 + cmLen
	if p+2 > len(ch) {
		return ""
	}
	extLen := int(binary.BigEndian.Uint16(ch[p : p+2]))
	p += 2
	if p+extLen > len(ch) {
		extLen = len(ch) - p
	}
	ext := ch[p : p+extLen]

	// Scan extensions for server_name (0x0000).
	for len(ext) >= 4 {
		extType := binary.BigEndian.Uint16(ext[0:2])
		extDataLen := int(binary.BigEndian.Uint16(ext[2:4]))
		if 4+extDataLen > len(ext) {
			return ""
		}
		extData := ext[4 : 4+extDataLen]

		if extType == 0x0000 {
			// server_name extension body:
			//   list_len(2) [ name_type(1) name_len(2) name ]*
			if len(extData) < 5 {
				return ""
			}
			listLen := int(binary.BigEndian.Uint16(extData[0:2]))
			if 2+listLen > len(extData) {
				return ""
			}
			list := extData[2 : 2+listLen]
			if len(list) < 3 || list[0] != 0x00 {
				return "" // not host_name
			}
			nameLen := int(binary.BigEndian.Uint16(list[1:3]))
			if 3+nameLen > len(list) {
				return ""
			}
			return string(list[3 : 3+nameLen])
		}
		ext = ext[4+extDataLen:]
	}
	return ""
}

// looksLikeHTTPRequest returns true when the first bytes look like an
// HTTP/1.x request line.
func looksLikeHTTPRequest(b []byte) bool {
	if len(b) < 7 {
		return false
	}
	// Cheap heuristic: an alphabetic method token, a space, then '/',
	// catches every standard verb without enumerating them.
	for i := 0; i < len(b) && i < 16; i++ {
		if b[i] == ' ' {
			if i+2 < len(b) && b[i+1] == '/' {
				return true
			}
			return false
		}
		c := b[i]
		if !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
			return false
		}
	}
	return false
}

// parseHTTPHost extracts the Host header value from a raw HTTP request
// peek. Case-insensitive header-name match, trims whitespace. Returns
// "" if not found.
func parseHTTPHost(b []byte) string {
	idx := 0
	for idx < len(b) {
		nl := -1
		for j := idx; j < len(b)-1; j++ {
			if b[j] == '\r' && b[j+1] == '\n' {
				nl = j
				break
			}
		}
		if nl < 0 {
			return ""
		}
		line := b[idx:nl]
		idx = nl + 2

		// Empty line → end of headers.
		if len(line) == 0 {
			return ""
		}

		// Skip the request line (first line has no colon before SP).
		// Header lines contain ':'.
		colon := -1
		for j := 0; j < len(line); j++ {
			if line[j] == ':' {
				colon = j
				break
			}
		}
		if colon <= 0 {
			continue
		}
		name := line[:colon]
		if strings.EqualFold(string(name), "Host") {
			value := strings.TrimSpace(string(line[colon+1:]))
			// Strip port, if any.
			if i := strings.IndexByte(value, ':'); i >= 0 {
				value = value[:i]
			}
			return value
		}
	}
	return ""
}

// peekReplayConn wraps a net.Conn so Read yields bytes from the peeked
// reader first, then falls through to the connection. Write, Close,
// and deadlines pass through to the underlying conn unchanged.
type peekReplayConn struct {
	net.Conn
	r io.Reader
}

func (c *peekReplayConn) Read(b []byte) (int, error) {
	return c.r.Read(b)
}

// intToStr converts a positive int to decimal ASCII without strconv
// allocation overhead in the hot path.
func intToStr(i int) string {
	if i == 0 {
		return "0"
	}
	var buf [20]byte
	pos := len(buf)
	neg := i < 0
	if neg {
		i = -i
	}
	for i > 0 {
		pos--
		buf[pos] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		pos--
		buf[pos] = '-'
	}
	return string(buf[pos:])
}
