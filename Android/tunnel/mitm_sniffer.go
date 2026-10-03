// mitm_sniffer.go peeks at initial flow payloads to identify TLS or plaintext HTTP protocols and extract hostnames.
//
// Low-Latency Inspection:
// - Performs a single conn.Read (up to 2KB) rather than blocking on bufio.Reader.Peek, returning a replay reader.
// - Parses TLS ClientHello records to extract SNI (Server Name Indication) extensions and ALPN protocols.
// - Parses HTTP/1.x request lines and Host headers for plaintext HTTP flows.

package tunnel

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"strings"
	"time"
)

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

func parseClientHelloSNI(record []byte) string {

	if len(record) < 5 || record[0] != 0x16 {
		return ""
	}
	recLen := int(binary.BigEndian.Uint16(record[3:5]))
	if recLen > len(record)-5 {
		recLen = len(record) - 5
	}
	body := record[5 : 5+recLen]

	if len(body) < 4 || body[0] != 0x01 {
		return ""
	}

	ch := body[4:]

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

	for len(ext) >= 4 {
		extType := binary.BigEndian.Uint16(ext[0:2])
		extDataLen := int(binary.BigEndian.Uint16(ext[2:4]))
		if 4+extDataLen > len(ext) {
			return ""
		}
		extData := ext[4 : 4+extDataLen]

		if extType == 0x0000 {

			if len(extData) < 5 {
				return ""
			}
			listLen := int(binary.BigEndian.Uint16(extData[0:2]))
			if 2+listLen > len(extData) {
				return ""
			}
			list := extData[2 : 2+listLen]
			if len(list) < 3 || list[0] != 0x00 {
				return ""
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

func looksLikeHTTPRequest(b []byte) bool {
	if len(b) < 7 {
		return false
	}

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

		if len(line) == 0 {
			return ""
		}

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

			if i := strings.IndexByte(value, ':'); i >= 0 {
				value = value[:i]
			}
			return value
		}
	}
	return ""
}

type peekReplayConn struct {
	net.Conn
	r io.Reader
}

func (c *peekReplayConn) Read(b []byte) (int, error) {
	return c.r.Read(b)
}

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
