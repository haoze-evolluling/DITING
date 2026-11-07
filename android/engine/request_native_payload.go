// request_native_payload.go encodes the request/decision payloads of rust/diting-request-core
// (the layout is documented in that crate's src/payload.rs):
//
//	rule set:  | i64 count | (str kind, str pattern) * count |
//	match in:  | str scheme | str host | str path |
//	match out: | i64 matched | i64 blocked | str pattern | str domain host |
//
// `str` is `u32 little-endian length | bytes`. Nothing here needs cgo, so the layout tests run on a
// machine without a C toolchain.

package tunnel

// requestPayloadLayoutVersion must match `LAYOUT_VERSION` in
// rust/diting-request-core/src/payload.rs.
const requestPayloadLayoutVersion = 1

// encodeRequestRules builds the rule set payload. The rules go in as they came out of JSON: the
// kernel owns the normalization (trim, lower-case, kind whitelist, scheme prefix).
func encodeRequestRules(rules []requestRule) []byte {
	payload := make([]byte, 0, 8+len(rules)*16)
	payload = appendRequestInt64(payload, int64(len(rules)))
	for _, rule := range rules {
		payload = appendRequestText(payload, rule.Kind)
		payload = appendRequestText(payload, rule.Pattern)
	}
	return payload
}

// encodeRequestMatch builds the decision request for one HTTP request.
func encodeRequestMatch(scheme, host, path string) []byte {
	payload := make([]byte, 0, 12+len(scheme)+len(host)+len(path))
	payload = appendRequestText(payload, scheme)
	payload = appendRequestText(payload, host)
	payload = appendRequestText(payload, path)
	return payload
}

func appendRequestText(out []byte, text string) []byte {
	out = append(out,
		byte(len(text)), byte(len(text)>>8), byte(len(text)>>16), byte(len(text)>>24))
	return append(out, text...)
}

func appendRequestInt64(out []byte, value int64) []byte {
	return append(out,
		byte(uint64(value)), byte(uint64(value)>>8), byte(uint64(value)>>16),
		byte(uint64(value)>>24), byte(uint64(value)>>32), byte(uint64(value)>>40),
		byte(uint64(value)>>48), byte(uint64(value)>>56))
}

// requestDecision is one decoded match response.
type requestDecision struct {
	matched    bool
	blocked    bool
	pattern    string
	domainHost string
}

// decodeRequestDecision reads the match response; `ok` is false for a malformed payload.
func decodeRequestDecision(payload []byte) (requestDecision, bool) {
	reader := requestPayloadReader{payload: payload}
	matched, matchedOK := reader.int64()
	blocked, blockedOK := reader.int64()
	pattern, patternOK := reader.text()
	domainHost, hostOK := reader.text()
	if !matchedOK || !blockedOK || !patternOK || !hostOK || !reader.atEnd() {
		return requestDecision{}, false
	}
	return requestDecision{
		matched:    matched != 0,
		blocked:    blocked != 0,
		pattern:    pattern,
		domainHost: domainHost,
	}, true
}

// requestPayloadReader walks a response body field by field; every read reports whether the payload
// was long enough.
type requestPayloadReader struct {
	payload  []byte
	position int
}

func (r *requestPayloadReader) atEnd() bool { return r.position == len(r.payload) }

func (r *requestPayloadReader) take(length int) ([]byte, bool) {
	if length < 0 || length > len(r.payload)-r.position {
		return nil, false
	}
	slice := r.payload[r.position : r.position+length]
	r.position += length
	return slice, true
}

func (r *requestPayloadReader) text() (string, bool) {
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

func (r *requestPayloadReader) int64() (int64, bool) {
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
