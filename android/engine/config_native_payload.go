// config_native_payload.go encodes the requests and decodes the responses of
// rust/diting-config-core (the layout is documented in that crate's src/payload.rs):
//
//	request:  | u8 op | body |
//	response: | u8 status (0 ok, 1 error) | body |
//
// `str` is `u32 little-endian length | bytes`, every integer is `i64`. Nothing here needs cgo, so the
// layout tests run on a machine without a C toolchain.

package tunnel

// configPayloadLayoutVersion must match `LAYOUT_VERSION` in rust/diting-config-core/src/payload.rs.
const configPayloadLayoutVersion = 1

// Opcodes, in the order of the table in that crate's payload.rs.
const (
	configOpDNSConfig    = 0
	configOpProtocol     = 1
	configOpResponseType = 2
	configOpDoQURL       = 3
	configOpDomain       = 4
	configOpRewrite      = 5
)

// Response status bytes.
const (
	configStatusOK    = 0
	configStatusError = 1
)

// configPayload is the request builder: op byte first, then the encoded fields.
type configPayload struct {
	body []byte
}

func newConfigPayload(op byte) *configPayload {
	return &configPayload{body: []byte{op}}
}

func appendConfigText(out []byte, text string) []byte {
	out = append(out,
		byte(len(text)), byte(len(text)>>8), byte(len(text)>>16), byte(len(text)>>24))
	return append(out, text...)
}

func appendConfigInt64(out []byte, value int64) []byte {
	return append(out,
		byte(uint64(value)), byte(uint64(value)>>8), byte(uint64(value)>>16),
		byte(uint64(value)>>24), byte(uint64(value)>>32), byte(uint64(value)>>40),
		byte(uint64(value)>>48), byte(uint64(value)>>56))
}

func (p *configPayload) text(value string) *configPayload {
	p.body = appendConfigText(p.body, value)
	return p
}

func (p *configPayload) int64(value int64) *configPayload {
	p.body = appendConfigInt64(p.body, value)
	return p
}

func (p *configPayload) bool(value bool) *configPayload {
	if value {
		return p.int64(1)
	}
	return p.int64(0)
}

// configPayloadReader walks a response body field by field; every read reports whether the payload
// was long enough.
type configPayloadReader struct {
	payload  []byte
	position int
}

func (r *configPayloadReader) atEnd() bool { return r.position == len(r.payload) }

func (r *configPayloadReader) take(length int) ([]byte, bool) {
	if length < 0 || length > len(r.payload)-r.position {
		return nil, false
	}
	slice := r.payload[r.position : r.position+length]
	r.position += length
	return slice, true
}

func (r *configPayloadReader) text() (string, bool) {
	head, ok := r.take(4)
	if !ok {
		return "", false
	}
	length := int(uint32(head[0]) | uint32(head[1])<<8 | uint32(head[2])<<16 | uint32(head[3])<<24)
	slice, ok := r.take(length)
	if !ok {
		return "", false
	}
	return string(slice), true
}

func (r *configPayloadReader) int64() (int64, bool) {
	slice, ok := r.take(8)
	if !ok {
		return 0, false
	}
	value := int64(0)
	for index := 7; index >= 0; index-- {
		value = value<<8 | int64(slice[index])
	}
	return value, true
}
