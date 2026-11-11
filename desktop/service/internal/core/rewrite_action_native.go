package core

// rewrite_action_native.go drives the `$dnsrewrite` action entry points of the Rust rewrite kernel
// (rust/diting-rewrite-core/src/action.rs) through the C ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust owns the value grammar — the rcode keyword table, the explicit
// `RCODE;TYPE;VALUE` split, the shorthand (`IP`, `CNAME`, bare), the validation through the same
// record builder a configured rewrite rule uses, and the normalization of the key cancelling
// exceptions are compared by. Go keeps the `RewriteAction` struct, the `dns.RR` construction and
// the display text.
//
// The key normalization has to live with the comparison: the rule index compares keys it received
// from Go, so computing them anywhere else would let two spellings of one address
// (`127.0.0.1` / `::ffff:127.0.0.1`) silently fail to cancel each other.
//
// The kernel is required. A missing library or a rejected request fails the parse, which drops the
// whole rule exactly like an unparsable value did before, and fails the rule index build (via
// `filterEncodeRules`) instead of indexing a key no exception can ever match.

import (
	"encoding/binary"
	"errors"
	"fmt"
	"runtime"
	"unsafe"
)

// parseRewriteAction hands one `$dnsrewrite` value to the kernel.
//
// value is the raw text after `=`, case preserved: record values and rcode keywords are case
// sensitive on the record side, and the kernel decides which spelling it accepts.
func parseRewriteAction(value string) (*RewriteAction, error) {
	lib, err := rewriteKernel()
	if err != nil {
		return nil, err
	}
	response, status := callRewriteActionEntry(lib, lib.parseAction, encodeRewriteActionParseRequest(value))
	switch status {
	case rewriteStatusOK:
		return decodeRewriteAction(response)
	case rewriteStatusRejected:
		if len(response) == 0 {
			return nil, errors.New("$dnsrewrite rejected by the native kernel")
		}
		return nil, errors.New(string(response))
	default:
		return nil, fmt.Errorf("rewrite kernel returned status %d", status)
	}
}

// rewriteActionKey asks the kernel for the normalized key of one action.
func rewriteActionKey(action *RewriteAction) (string, error) {
	lib, err := rewriteKernel()
	if err != nil {
		return "", err
	}
	response, status := callRewriteActionEntry(lib, lib.actionKey, encodeRewriteActionKeyRequest(action))
	switch status {
	case rewriteStatusOK:
		return decodeRewriteActionKey(response)
	case rewriteStatusRejected:
		if len(response) == 0 {
			return "", errors.New("rewrite action rejected by the native kernel")
		}
		return "", errors.New(string(response))
	default:
		return "", fmt.Errorf("rewrite kernel returned status %d", status)
	}
}

// callRewriteActionEntry runs one fixed-request action entry point and copies the reply.
func callRewriteActionEntry(
	lib *rewriteNativeLib,
	entry func(input unsafe.Pointer, inputLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32,
	request []byte,
) ([]byte, uint32) {
	var input unsafe.Pointer
	if len(request) > 0 {
		input = unsafe.Pointer(&request[0])
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := entry(input, uintptr(len(request)), &out, &outLen)
	runtime.KeepAlive(request)
	return copyRewritePayload(lib, out, outLen), status
}

// encodeRewriteActionParseRequest builds the parse request src/payload.rs decodes.
func encodeRewriteActionParseRequest(value string) []byte {
	payload := []byte{rewritePayloadLayoutVersion}
	return appendRewriteText(payload, value)
}

// encodeRewriteActionKeyRequest builds the key request from the action fields Go holds.
//
// RCode only ever holds one of the six `dns.Rcode*` values, so the `u16` on the wire covers it and
// the kernel's own parse never produces anything larger.
func encodeRewriteActionKeyRequest(action *RewriteAction) []byte {
	payload := []byte{rewritePayloadLayoutVersion, 0}
	if action.Bare {
		payload[1] = 1
	}
	payload = binary.LittleEndian.AppendUint16(payload, uint16(action.RCode))
	payload = binary.LittleEndian.AppendUint16(payload, action.RRType)
	return appendRewriteText(payload, action.Value)
}

// decodeRewriteAction reads the parsed action: bare flag, rcode, rrtype and raw value.
func decodeRewriteAction(payload []byte) (*RewriteAction, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return nil, err
	}
	if layout != rewritePayloadLayoutVersion {
		return nil, fmt.Errorf("rewrite payload layout %d, expected %d", layout, rewritePayloadLayoutVersion)
	}
	bare, err := reader.u8()
	if err != nil {
		return nil, err
	}
	switch bare {
	case 0, 1:
	default:
		return nil, fmt.Errorf("rewrite action payload has unknown bare flag %d", bare)
	}
	rcode, err := reader.u16()
	if err != nil {
		return nil, err
	}
	rrtype, err := reader.u16()
	if err != nil {
		return nil, err
	}
	value, err := reader.text32()
	if err != nil {
		return nil, err
	}
	if remaining := reader.remaining(); remaining != 0 {
		return nil, fmt.Errorf("rewrite action payload has %d trailing bytes", remaining)
	}
	return &RewriteAction{Bare: bare == 1, RCode: rcode, RRType: uint16(rrtype), Value: value}, nil
}

// decodeRewriteActionKey reads the normalized key.
func decodeRewriteActionKey(payload []byte) (string, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return "", err
	}
	if layout != rewritePayloadLayoutVersion {
		return "", fmt.Errorf("rewrite payload layout %d, expected %d", layout, rewritePayloadLayoutVersion)
	}
	key, err := reader.text32()
	if err != nil {
		return "", err
	}
	if remaining := reader.remaining(); remaining != 0 {
		return "", fmt.Errorf("rewrite action key payload has %d trailing bytes", remaining)
	}
	return key, nil
}
