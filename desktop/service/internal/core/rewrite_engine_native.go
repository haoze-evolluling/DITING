package core

// rewrite_engine_native.go drives the rewrite engine compiled into rust/diting-rewrite-core.
//
// Responsibility split: Go still owns the configuration (`RewriteRule` is part of the JSON surface,
// and AddRule / DeleteRule / Configure edit the list), while the kernel owns everything that
// interprets it — normalization, the exact and wildcard indexes, PTR map, compiled explicit
// records, rcode overrides, the CNAME chase and RFC 1034 §3.6.2 owner merging. One `build` call
// compiles a whole snapshot; each query is a single `lookup` against that handle.
//
// Payload layout: see the header of rust/diting-rewrite-core/src/payload.rs. Strings are
// `u32`-length prefixed, and every payload starts with a layout byte so a stale pair is loud.
//
// The kernel is required: a missing library or a rejected build fails `NewRewriteEngine`, which
// fails service startup. Lookups cannot fail in practice (the handle was built and Go keeps the
// library loaded); if one does, it is logged and treated as "not matched" so the query keeps
// flowing to the next middleware.

import (
	"encoding/binary"
	"errors"
	"fmt"
	"log"
	"net"
	"runtime"
	"unsafe"

	"github.com/miekg/dns"
)

// rewriteEngineHandle is one compiled engine snapshot. The Go engine holds it behind its mutex and
// swaps it atomically when the configuration changes.
type rewriteEngineHandle struct {
	lib     *rewriteNativeLib
	pointer unsafe.Pointer
}

// buildRewriteEngine compiles a whole configuration into a fresh handle. Warnings are the lines the
// old Go compile pass logged while dropping an unusable rcode or explicit record.
func buildRewriteEngine(cfg RewriteConfig) (*rewriteEngineHandle, error) {
	lib, err := rewriteKernel()
	if err != nil {
		return nil, err
	}

	payload := encodeRewriteEngineConfig(cfg)
	var input unsafe.Pointer
	if len(payload) > 0 {
		input = unsafe.Pointer(&payload[0])
	}
	var handle unsafe.Pointer
	var out unsafe.Pointer
	var outLen uintptr
	status := lib.engineBuild(input, uintptr(len(payload)), &handle, &out, &outLen)
	runtime.KeepAlive(payload)
	response := copyRewritePayload(lib, out, outLen)

	switch status {
	case rewriteStatusOK:
		if handle == nil {
			return nil, errors.New("rewrite engine kernel returned no handle")
		}
		warnings, err := decodeRewriteEngineWarnings(response)
		if err != nil {
			lib.engineFree(handle)
			return nil, err
		}
		for _, warning := range warnings {
			log.Printf("[Rewrite] %s\n", warning)
		}
		return &rewriteEngineHandle{lib: lib, pointer: handle}, nil
	case rewriteStatusRejected:
		if len(response) == 0 {
			return nil, errors.New("rewrite engine rejected by the native kernel")
		}
		return nil, errors.New(string(response))
	default:
		return nil, fmt.Errorf("rewrite engine kernel returned status %d", status)
	}
}

// free drops the snapshot. Go calls it after swapping the engine pointer under the write lock, so
// no reader can still be inside a lookup on it.
func (h *rewriteEngineHandle) free() {
	if h == nil || h.pointer == nil {
		return
	}
	h.lib.engineFree(h.pointer)
	h.pointer = nil
}

// lookup answers one query from the snapshot.
func (h *rewriteEngineHandle) lookup(domain string, qtype uint16) ([]dns.RR, int, bool, error) {
	var name unsafe.Pointer
	if len(domain) > 0 {
		name = unsafe.Pointer(unsafe.StringData(domain))
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := h.lib.engineLookup(h.pointer, name, uintptr(len(domain)), qtype, &out, &outLen)
	runtime.KeepAlive(domain)
	response := copyRewritePayload(h.lib, out, outLen)
	if status != rewriteStatusOK {
		return nil, dns.RcodeSuccess, false, rewriteEngineStatusError(status, response, "lookup")
	}
	return decodeRewriteEngineLookup(response)
}

// lookupPTR returns the PTR target names for one address.
func (h *rewriteEngineHandle) lookupPTR(ip net.IP) ([]string, error) {
	response, err := h.engineAddressCall(ip, h.lib.engineLookupPTR, "PTR")
	if err != nil {
		return nil, err
	}
	return decodeRewriteEngineDomains(response)
}

// lookupReverse returns the first PTR target name for one address.
func (h *rewriteEngineHandle) lookupReverse(ip net.IP) (string, error) {
	response, err := h.engineAddressCall(ip, h.lib.engineLookupReverse, "reverse")
	if err != nil {
		return "", err
	}
	return decodeRewriteEngineReverse(response)
}

// engineAddressCall runs one of the address-keyed entry points.
func (h *rewriteEngineHandle) engineAddressCall(ip net.IP, call func(handle unsafe.Pointer, ip unsafe.Pointer, ipLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32, label string) ([]byte, error) {
	if len(ip) == 0 {
		return nil, nil
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := call(h.pointer, unsafe.Pointer(&ip[0]), uintptr(len(ip)), &out, &outLen)
	runtime.KeepAlive(ip)
	response := copyRewritePayload(h.lib, out, outLen)
	if status != rewriteStatusOK {
		return nil, rewriteEngineStatusError(status, response, label)
	}
	return response, nil
}

func rewriteEngineStatusError(status uint32, response []byte, label string) error {
	if status == rewriteStatusRejected {
		if len(response) == 0 {
			return fmt.Errorf("rewrite engine %s rejected by the native kernel", label)
		}
		return fmt.Errorf("rewrite engine %s: %s", label, response)
	}
	return fmt.Errorf("rewrite engine %s returned status %d", label, status)
}

// encodeRewriteEngineConfig serializes the configuration in the layout src/payload.rs decodes.
func encodeRewriteEngineConfig(cfg RewriteConfig) []byte {
	ttl := cfg.TTL
	if ttl == 0 {
		ttl = DefaultRewriteTTL
	}
	payload := []byte{rewritePayloadLayoutVersion}
	if cfg.Enabled {
		payload = append(payload, 1)
	} else {
		payload = append(payload, 0)
	}
	payload = binary.LittleEndian.AppendUint32(payload, ttl)
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len(cfg.Rules)))
	for _, rule := range cfg.Rules {
		payload = appendRewriteText(payload, rule.Domain)
		payload = binary.LittleEndian.AppendUint32(payload, rule.TTL)
		payload = binary.LittleEndian.AppendUint32(payload, uint32(len(rule.IPs)))
		for _, address := range rule.IPs {
			payload = appendRewriteText(payload, address)
		}
		payload = appendRewriteText(payload, rule.CNAME)
		payload = binary.LittleEndian.AppendUint32(payload, uint32(len(rule.TXT)))
		for _, text := range rule.TXT {
			payload = appendRewriteText(payload, text)
		}
		payload = binary.LittleEndian.AppendUint32(payload, uint32(len(rule.Records)))
		for _, record := range rule.Records {
			payload = appendRewriteText(payload, record.Type)
			payload = appendRewriteText(payload, record.Value)
		}
		payload = appendRewriteText(payload, rule.RCode)
	}
	return payload
}

func decodeRewriteEngineWarnings(payload []byte) ([]string, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return nil, err
	}
	if layout != rewritePayloadLayoutVersion {
		return nil, fmt.Errorf("rewrite payload layout %d, expected %d", layout, rewritePayloadLayoutVersion)
	}
	count, err := reader.u32()
	if err != nil {
		return nil, err
	}
	warnings := make([]string, 0, count)
	for i := uint32(0); i < count; i++ {
		warning, err := reader.text32()
		if err != nil {
			return nil, err
		}
		warnings = append(warnings, warning)
	}
	if remaining := reader.remaining(); remaining != 0 {
		return nil, fmt.Errorf("rewrite payload has %d trailing bytes", remaining)
	}
	return warnings, nil
}

func decodeRewriteEngineLookup(payload []byte) ([]dns.RR, int, bool, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return nil, dns.RcodeSuccess, false, err
	}
	if layout != rewritePayloadLayoutVersion {
		return nil, dns.RcodeSuccess, false, fmt.Errorf("rewrite payload layout %d, expected %d", layout, rewritePayloadLayoutVersion)
	}
	matched, err := reader.u8()
	if err != nil {
		return nil, dns.RcodeSuccess, false, err
	}
	if matched > 1 {
		return nil, dns.RcodeSuccess, false, fmt.Errorf("rewrite engine returned matched flag %d", matched)
	}
	rcode, err := reader.u16()
	if err != nil {
		return nil, dns.RcodeSuccess, false, err
	}
	count, err := reader.u32()
	if err != nil {
		return nil, dns.RcodeSuccess, false, err
	}
	answers := make([]dns.RR, 0, count)
	for i := uint32(0); i < count; i++ {
		rr, err := decodeRewriteRecordFields(reader)
		if err != nil {
			return nil, dns.RcodeSuccess, false, err
		}
		answers = append(answers, rr)
	}
	if remaining := reader.remaining(); remaining != 0 {
		return nil, dns.RcodeSuccess, false, fmt.Errorf("rewrite payload has %d trailing bytes", remaining)
	}
	return answers, rcode, matched == 1, nil
}

func decodeRewriteEngineDomains(payload []byte) ([]string, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return nil, err
	}
	if layout != rewritePayloadLayoutVersion {
		return nil, fmt.Errorf("rewrite payload layout %d, expected %d", layout, rewritePayloadLayoutVersion)
	}
	count, err := reader.u32()
	if err != nil {
		return nil, err
	}
	domains := make([]string, 0, count)
	for i := uint32(0); i < count; i++ {
		domain, err := reader.text32()
		if err != nil {
			return nil, err
		}
		domains = append(domains, domain)
	}
	if remaining := reader.remaining(); remaining != 0 {
		return nil, fmt.Errorf("rewrite payload has %d trailing bytes", remaining)
	}
	return domains, nil
}

func decodeRewriteEngineReverse(payload []byte) (string, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return "", err
	}
	if layout != rewritePayloadLayoutVersion {
		return "", fmt.Errorf("rewrite payload layout %d, expected %d", layout, rewritePayloadLayoutVersion)
	}
	present, err := reader.u8()
	if err != nil {
		return "", err
	}
	if present == 0 {
		if remaining := reader.remaining(); remaining != 0 {
			return "", fmt.Errorf("rewrite payload has %d trailing bytes", remaining)
		}
		return "", nil
	}
	if present != 1 {
		return "", fmt.Errorf("rewrite engine returned present flag %d", present)
	}
	domain, err := reader.text32()
	if err != nil {
		return "", err
	}
	if remaining := reader.remaining(); remaining != 0 {
		return "", fmt.Errorf("rewrite payload has %d trailing bytes", remaining)
	}
	return domain, nil
}
