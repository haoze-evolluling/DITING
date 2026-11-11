package core

// rewrite_native.go loads the Rust rewrite-record kernel (rust/diting-rewrite-core) and drives it
// through the C ABI in that crate's src/ffi.rs.
//
// This file covers the single-record entry point. The `$dnsrewrite` value grammar lives in
// rewrite_action_native.go and the rewrite engine that answers queries in rewrite_engine_native.go;
// all three use the same loaded library (and the same ABI version).
//
// Responsibility split: Rust owns the record syntax — the supported type table, the value grammar
// for A/AAAA/CNAME/NS/PTR/TXT/MX/SRV/HTTPS/SVCB, the SVCB parameter list and the target-domain
// check — and answers with one typed record. Go keeps the `dns.RR` construction, because the answer
// goes straight into a `dns.Msg`: the reply carries the numeric type plus the unpacked fields.
//
// The kernel is required. A missing library, a stale ABI or a rejected payload fails
// buildRewriteRR, which fails `compileRewriteRecords` for a custom rewrite rule. There is no second
// parser left, and a silent one would only keep working until a value it read differently reached
// a client.
//
// Loading is pure Go (syscall.LazyDLL on Windows, purego elsewhere), so the module stays
// CGO_ENABLED=0.

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"runtime"
	"sync"
	"unsafe"

	"github.com/miekg/dns"
)

// rewriteNativeABIVersion must match `ABI_VERSION` in rust/diting-rewrite-core/src/ffi.rs.
//
// Version 3 added the two `$dnsrewrite` action entry points; a version 2 library has neither, so the
// loader refuses it instead of the first parse failing at run time.
const rewriteNativeABIVersion = 3

// Payload layout and status codes; keep in sync with src/payload.rs and src/ffi.rs.
const (
	rewritePayloadLayoutVersion = 1

	rewriteStatusOK       = 0
	rewriteStatusRejected = 1
)

// SVCB parameter keys, mirroring `dns.SVCBKey` in rust/diting-rewrite-core/src/record.rs.
const (
	rewriteSVCBKeyMandatory uint16 = iota
	rewriteSVCBKeyALPN
	rewriteSVCBKeyNoDefaultALPN
	rewriteSVCBKeyPort
	rewriteSVCBKeyIPv4Hint
	rewriteSVCBKeyECHConfig
	rewriteSVCBKeyIPv6Hint
	rewriteSVCBKeyDoHPath
)

// rewriteNativeLib is one loaded kernel: the record builder, the action parser, the type list and
// the engine entry points.
type rewriteNativeLib struct {
	buildRecord         func(input unsafe.Pointer, inputLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32
	parseAction         func(input unsafe.Pointer, inputLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32
	actionKey           func(input unsafe.Pointer, inputLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32
	recordTypes         func(out *unsafe.Pointer, outLen *uintptr) uint32
	engineBuild         func(input unsafe.Pointer, inputLen uintptr, handle *unsafe.Pointer, out *unsafe.Pointer, outLen *uintptr) uint32
	engineLookup        func(handle unsafe.Pointer, name unsafe.Pointer, nameLen uintptr, qtype uint16, out *unsafe.Pointer, outLen *uintptr) uint32
	engineLookupPTR     func(handle unsafe.Pointer, ip unsafe.Pointer, ipLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32
	engineLookupReverse func(handle unsafe.Pointer, ip unsafe.Pointer, ipLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32
	engineFree          func(handle unsafe.Pointer)
	freeBytes           func(pointer unsafe.Pointer, length uintptr)
}

var (
	rewriteNativeOnce   sync.Once
	rewriteNativeShared *rewriteNativeLib
	rewriteNativeErr    error
)

func loadRewriteNativeLibrary() (*rewriteNativeLib, error) {
	return loadNativeLibrary("DITING_REWRITE_CORE_LIB", "diting_rewrite_core", "rewrite record kernel", loadRewriteLibrary)
}

// rewriteKernel returns the loaded library; the failure is kept so every build reports the same
// reason instead of retrying the probe.
func rewriteKernel() (*rewriteNativeLib, error) {
	rewriteNativeOnce.Do(func() {
		rewriteNativeShared, rewriteNativeErr = loadRewriteNativeLibrary()
	})
	if rewriteNativeErr != nil {
		return nil, rewriteNativeErr
	}
	return rewriteNativeShared, nil
}

// buildRewriteRR 把一条 RewriteRecord 编译成应答记录。
//
// name 取自查询名而非规则里的域名，这样泛域名规则也能返回与查询相符的记录名。
// 返回 nil 表示该记录类型与查询类型不一致（调用方据此产出权威 NODATA）。
//
// 取值语法与校验全部在 Rust 内核里（rust/diting-rewrite-core/src/record.rs），这里只把回传的
// 字段填进 `dns.RR`：自定义重写规则与 `$dnsrewrite` 修饰符共用这一条路径。
func buildRewriteRR(name string, qtype uint16, rec RewriteRecord, ttl uint32) (dns.RR, error) {
	lib, err := rewriteKernel()
	if err != nil {
		return nil, err
	}

	payload := encodeRewriteRecordRequest(name, qtype, rec, ttl)
	var input unsafe.Pointer
	if len(payload) > 0 {
		input = unsafe.Pointer(&payload[0])
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := lib.buildRecord(input, uintptr(len(payload)), &out, &outLen)
	runtime.KeepAlive(payload)

	response := copyRewritePayload(lib, out, outLen)
	switch status {
	case rewriteStatusOK:
		return decodeRewriteRecord(response)
	case rewriteStatusRejected:
		if len(response) == 0 {
			return nil, errors.New("rewrite record rejected by the native kernel")
		}
		return nil, errors.New(string(response))
	default:
		return nil, fmt.Errorf("rewrite kernel returned status %d", status)
	}
}

// encodeRewriteRecordRequest builds the request payload src/payload.rs decodes.
func encodeRewriteRecordRequest(name string, qtype uint16, rec RewriteRecord, ttl uint32) []byte {
	payload := []byte{rewritePayloadLayoutVersion}
	payload = binary.LittleEndian.AppendUint16(payload, qtype)
	payload = binary.LittleEndian.AppendUint32(payload, ttl)
	payload = appendRewriteText(payload, name)
	payload = appendRewriteText(payload, rec.Type)
	return appendRewriteText(payload, rec.Value)
}

func appendRewriteText(payload []byte, value string) []byte {
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len(value)))
	return append(payload, value...)
}

// decodeRewriteRecord turns the kernel reply into the record the caller asked for, or nil when the
// record type does not answer this query type.
func decodeRewriteRecord(payload []byte) (dns.RR, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return nil, err
	}
	if layout != rewritePayloadLayoutVersion {
		return nil, fmt.Errorf("rewrite payload layout %d, expected %d", layout, rewritePayloadLayoutVersion)
	}
	hasRecord, err := reader.u8()
	if err != nil {
		return nil, err
	}
	switch hasRecord {
	case 0:
		return finishRewriteRecord(reader, nil)
	case 1:
	default:
		return nil, fmt.Errorf("rewrite payload has unknown record flag %d", hasRecord)
	}

	rr, err := decodeRewriteRecordFields(reader)
	if err != nil {
		return nil, err
	}
	return finishRewriteRecord(reader, rr)
}

// decodeRewriteRecordFields reads one record (type, owner, TTL and value) without the layout byte,
// so the engine reply can stream several of them through the same decoder.
func decodeRewriteRecordFields(reader *payloadReader) (dns.RR, error) {
	rrtype, err := reader.u16()
	if err != nil {
		return nil, err
	}
	owner, err := reader.text32()
	if err != nil {
		return nil, err
	}
	ttl, err := reader.u32()
	if err != nil {
		return nil, err
	}
	header := dns.RR_Header{
		Name:   owner,
		Rrtype: uint16(rrtype),
		Class:  dns.ClassINET,
		Ttl:    ttl,
	}

	var rr dns.RR
	switch header.Rrtype {
	case dns.TypeA:
		address, err := reader.bytes(4)
		if err != nil {
			return nil, err
		}
		rr = &dns.A{Hdr: header, A: net.IP(address)}
	case dns.TypeAAAA:
		address, err := reader.bytes(16)
		if err != nil {
			return nil, err
		}
		rr = &dns.AAAA{Hdr: header, AAAA: net.IP(address)}
	case dns.TypeCNAME:
		target, err := reader.text32()
		if err != nil {
			return nil, err
		}
		rr = &dns.CNAME{Hdr: header, Target: target}
	case dns.TypeNS:
		ns, err := reader.text32()
		if err != nil {
			return nil, err
		}
		rr = &dns.NS{Hdr: header, Ns: ns}
	case dns.TypePTR:
		ptr, err := reader.text32()
		if err != nil {
			return nil, err
		}
		rr = &dns.PTR{Hdr: header, Ptr: ptr}
	case dns.TypeTXT:
		count, err := reader.u32()
		if err != nil {
			return nil, err
		}
		texts := make([]string, 0, count)
		for i := uint32(0); i < count; i++ {
			text, err := reader.text32()
			if err != nil {
				return nil, err
			}
			texts = append(texts, text)
		}
		rr = &dns.TXT{Hdr: header, Txt: texts}
	case dns.TypeMX:
		preference, err := reader.u16()
		if err != nil {
			return nil, err
		}
		exchange, err := reader.text32()
		if err != nil {
			return nil, err
		}
		rr = &dns.MX{Hdr: header, Preference: uint16(preference), Mx: exchange}
	case dns.TypeSRV:
		priority, err := reader.u16()
		if err != nil {
			return nil, err
		}
		weight, err := reader.u16()
		if err != nil {
			return nil, err
		}
		port, err := reader.u16()
		if err != nil {
			return nil, err
		}
		target, err := reader.text32()
		if err != nil {
			return nil, err
		}
		rr = &dns.SRV{
			Hdr:      header,
			Priority: uint16(priority),
			Weight:   uint16(weight),
			Port:     uint16(port),
			Target:   target,
		}
	case dns.TypeHTTPS, dns.TypeSVCB:
		built, err := decodeRewriteSVCB(reader, header)
		if err != nil {
			return nil, err
		}
		rr = built
	default:
		return nil, fmt.Errorf("rewrite kernel returned unsupported record type %d", header.Rrtype)
	}
	return rr, nil
}

// finishRewriteRecord rejects a payload with bytes left over, then returns the record.
func finishRewriteRecord(reader *payloadReader, rr dns.RR) (dns.RR, error) {
	if remaining := reader.remaining(); remaining != 0 {
		return nil, fmt.Errorf("rewrite payload has %d trailing bytes", remaining)
	}
	return rr, nil
}

// decodeRewriteSVCB reads the SVCB/HTTPS body: priority, target and the parameter list.
func decodeRewriteSVCB(reader *payloadReader, header dns.RR_Header) (dns.RR, error) {
	priority, err := reader.u16()
	if err != nil {
		return nil, err
	}
	target, err := reader.text32()
	if err != nil {
		return nil, err
	}
	count, err := reader.u16()
	if err != nil {
		return nil, err
	}
	params := make([]dns.SVCBKeyValue, 0, count)
	for i := 0; i < count; i++ {
		param, err := decodeRewriteSVCBParam(reader)
		if err != nil {
			return nil, err
		}
		params = append(params, param)
	}

	svcb := dns.SVCB{Hdr: header, Priority: uint16(priority), Target: target, Value: params}
	if header.Rrtype == dns.TypeHTTPS {
		return &dns.HTTPS{SVCB: svcb}, nil
	}
	return &svcb, nil
}

// decodeRewriteSVCBParam reads one parameter: its key and the data that key implies.
func decodeRewriteSVCBParam(reader *payloadReader) (dns.SVCBKeyValue, error) {
	key, err := reader.u16()
	if err != nil {
		return nil, err
	}
	switch uint16(key) {
	case rewriteSVCBKeyMandatory:
		count, err := reader.u16()
		if err != nil {
			return nil, err
		}
		codes := make([]dns.SVCBKey, 0, count)
		for i := 0; i < count; i++ {
			code, err := reader.u16()
			if err != nil {
				return nil, err
			}
			codes = append(codes, dns.SVCBKey(code))
		}
		return &dns.SVCBMandatory{Code: codes}, nil
	case rewriteSVCBKeyALPN:
		count, err := reader.u16()
		if err != nil {
			return nil, err
		}
		alpn := make([]string, 0, count)
		for i := 0; i < count; i++ {
			value, err := reader.text32()
			if err != nil {
				return nil, err
			}
			alpn = append(alpn, value)
		}
		return &dns.SVCBAlpn{Alpn: alpn}, nil
	case rewriteSVCBKeyNoDefaultALPN:
		return &dns.SVCBNoDefaultAlpn{}, nil
	case rewriteSVCBKeyPort:
		port, err := reader.u16()
		if err != nil {
			return nil, err
		}
		return &dns.SVCBPort{Port: uint16(port)}, nil
	case rewriteSVCBKeyIPv4Hint:
		count, err := reader.u16()
		if err != nil {
			return nil, err
		}
		hints := make([]net.IP, 0, count)
		for i := 0; i < count; i++ {
			address, err := reader.bytes(4)
			if err != nil {
				return nil, err
			}
			hints = append(hints, net.IP(address))
		}
		return &dns.SVCBIPv4Hint{Hint: hints}, nil
	case rewriteSVCBKeyECHConfig:
		length, err := reader.u32()
		if err != nil {
			return nil, err
		}
		raw, err := reader.bytes(int(length))
		if err != nil {
			return nil, err
		}
		return &dns.SVCBECHConfig{ECH: raw}, nil
	case rewriteSVCBKeyIPv6Hint:
		count, err := reader.u16()
		if err != nil {
			return nil, err
		}
		hints := make([]net.IP, 0, count)
		for i := 0; i < count; i++ {
			address, err := reader.bytes(16)
			if err != nil {
				return nil, err
			}
			hints = append(hints, net.IP(address))
		}
		return &dns.SVCBIPv6Hint{Hint: hints}, nil
	case rewriteSVCBKeyDoHPath:
		template, err := reader.text32()
		if err != nil {
			return nil, err
		}
		return &dns.SVCBDoHPath{Template: template}, nil
	default:
		return nil, fmt.Errorf("rewrite kernel returned unsupported SVCB parameter %d", key)
	}
}

// fetchRewriteRecordTypes asks the kernel for the supported type names (sorted).
func fetchRewriteRecordTypes() ([]string, error) {
	lib, err := rewriteKernel()
	if err != nil {
		return nil, err
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := lib.recordTypes(&out, &outLen)
	response := copyRewritePayload(lib, out, outLen)
	if status != rewriteStatusOK {
		return nil, fmt.Errorf("rewrite kernel returned status %d for the type list", status)
	}

	reader := &payloadReader{data: response}
	layout, err := reader.u8()
	if err != nil {
		return nil, err
	}
	if layout != rewritePayloadLayoutVersion {
		return nil, fmt.Errorf("rewrite payload layout %d, expected %d", layout, rewritePayloadLayoutVersion)
	}
	count, err := reader.u16()
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, count)
	for i := 0; i < count; i++ {
		name, err := reader.text32()
		if err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	if remaining := reader.remaining(); remaining != 0 {
		return nil, fmt.Errorf("rewrite payload has %d trailing bytes", remaining)
	}
	return names, nil
}

// copyRewritePayload copies a kernel payload out and releases it, so the copy lives on in Go.
func copyRewritePayload(lib *rewriteNativeLib, pointer unsafe.Pointer, length uintptr) []byte {
	if pointer == nil || length == 0 {
		if pointer != nil {
			lib.freeBytes(pointer, length)
		}
		return nil
	}
	payload := make([]byte, int(length))
	copy(payload, unsafe.Slice((*byte)(pointer), int(length)))
	lib.freeBytes(pointer, length)
	return payload
}
