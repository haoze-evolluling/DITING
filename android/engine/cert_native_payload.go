//go:build cgo

// cert_native_payload.go decodes the response payloads of rust/diting-cert-core (layout documented
// in that crate's src/ffi.rs): a sequence of `u32 little-endian length | bytes` text fields,
// optionally followed by one `i64`.

package tunnel

func binaryLittleEndianUint32(bytes []byte) uint32 {
	return uint32(bytes[0]) | uint32(bytes[1])<<8 | uint32(bytes[2])<<16 | uint32(bytes[3])<<24
}

// certPayloadReader walks a response payload field by field; every read reports whether the
// payload was long enough.
type certPayloadReader struct {
	payload  []byte
	position int
}

func (r *certPayloadReader) atEnd() bool { return r.position == len(r.payload) }

func (r *certPayloadReader) take(length int) ([]byte, bool) {
	if length < 0 || length > len(r.payload)-r.position {
		return nil, false
	}
	slice := r.payload[r.position : r.position+length]
	r.position += length
	return slice, true
}

func (r *certPayloadReader) text() (string, bool) {
	lengthBytes, ok := r.take(4)
	if !ok {
		return "", false
	}
	slice, ok := r.take(int(binaryLittleEndianUint32(lengthBytes)))
	if !ok {
		return "", false
	}
	return string(slice), true
}

func (r *certPayloadReader) int64() (int64, bool) {
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
