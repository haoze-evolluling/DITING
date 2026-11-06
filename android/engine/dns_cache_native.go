//go:build cgo

// dns_cache_native.go loads the Rust DNS cache wire kernel (rust/diting-dns-cache-core) and drives
// it through the C ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust parses the response (minimum TTL, TTL offsets, CNAME/SVCB/HTTPS
// targets, A/AAAA addresses), builds the question key and patches the ID/TTLs of a cache hit. Go
// keeps the sharded LRU, the TTL policy arithmetic, single-flight and the background sweeper.
//
// The kernel is required for the cache to work, but not for the tunnel: if the library is missing
// or has a stale ABI, `put` refuses to store an answer and every lookup misses, so queries go
// straight to the resolver. That is the same answer the old Go code produced without a cache, and
// the failure is logged once instead of silently serving different TTL/ID semantics.
package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_dnscache_lib_t;
static diting_dnscache_lib_t diting_dnscache_open(const char* path) { return LoadLibraryA(path); }
static void* diting_dnscache_sym(diting_dnscache_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_dnscache_close(diting_dnscache_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_dnscache_lib_t;
static diting_dnscache_lib_t diting_dnscache_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_dnscache_sym(diting_dnscache_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_dnscache_close(diting_dnscache_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_dnscache_abi_fn)(void);
typedef intptr_t (*diting_dnscache_key_fn)(const void*, size_t, void*, size_t, uint32_t*,
	uint16_t*, uint16_t*);
typedef uint32_t (*diting_dnscache_parse_fn)(const void*, size_t, void**, size_t*);
typedef intptr_t (*diting_dnscache_patch_fn)(const void*, size_t, const void*, size_t, uint16_t,
	uint32_t, void*, size_t);
typedef void (*diting_dnscache_free_fn)(void*, size_t);

static uint32_t diting_dnscache_call_abi(void* fn) { return ((diting_dnscache_abi_fn)fn)(); }
static intptr_t diting_dnscache_call_key(void* fn, const void* wire, size_t wire_len, void* out,
	size_t out_cap, uint32_t* name_len, uint16_t* qtype, uint16_t* qclass) {
	return ((diting_dnscache_key_fn)fn)(wire, wire_len, out, out_cap, name_len, qtype, qclass);
}
static uint32_t diting_dnscache_call_parse(void* fn, const void* wire, size_t wire_len,
	void** payload, size_t* payload_len) {
	return ((diting_dnscache_parse_fn)fn)(wire, wire_len, payload, payload_len);
}
static intptr_t diting_dnscache_call_patch(void* fn, const void* wire, size_t wire_len,
	const void* offsets, size_t offsets_len, uint16_t query_id, uint32_t ttl, void* out,
	size_t out_cap) {
	return ((diting_dnscache_patch_fn)fn)(wire, wire_len, offsets, offsets_len, query_id, ttl, out,
		out_cap);
}
static void diting_dnscache_call_free(void* fn, void* pointer, size_t length) {
	((diting_dnscache_free_fn)fn)(pointer, length);
}
*/
import "C"

import (
	"encoding/binary"
	"fmt"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"
)

// dnsCacheABIVersion must match `ABI_VERSION` in rust/diting-dns-cache-core/src/ffi.rs.
const dnsCacheABIVersion = 1

// dnsCachePayloadLayoutVersion must match `LAYOUT_VERSION` in
// rust/diting-dns-cache-core/src/payload.rs.
const dnsCachePayloadLayoutVersion = 1

// Payload flag bits of `encode_response_meta`.
const (
	dnsCacheFlagTruncated = 1 << 0
	dnsCacheFlagMinTTL    = 1 << 1
)

// Positions of the fixed prefix of the response payload.
const (
	dnsCachePayloadAnswerCount = 1
	dnsCachePayloadRcode       = 3
	dnsCachePayloadFlags       = 4
	dnsCachePayloadMinTTL      = 5
	dnsCachePayloadBody        = 9
)

type dnsCacheNativeLib struct {
	lib           C.diting_dnscache_lib_t
	questionKey   unsafe.Pointer
	parseResponse unsafe.Pointer
	patchResponse unsafe.Pointer
	freeBytes     unsafe.Pointer
}

var (
	dnsCacheNativeOnce   sync.Once
	dnsCacheNativeShared *dnsCacheNativeLib
	dnsCacheNativeErr    error
)

func dnsCacheNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_dns_cache_core.dll"
	case "darwin":
		return "libditing_dns_cache_core.dylib"
	default:
		return "libditing_dns_cache_core.so"
	}
}

// dnsCacheNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func dnsCacheNativeCandidates() []string {
	name := dnsCacheNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func dnsCacheNativeSymbols(lib *dnsCacheNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_dns_cache_question_key", &lib.questionKey},
		{"diting_dns_cache_parse_response", &lib.parseResponse},
		{"diting_dns_cache_patch_response", &lib.patchResponse},
		{"diting_dns_cache_free_bytes", &lib.freeBytes},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_dnscache_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadDNSCacheNative() (*dnsCacheNativeLib, error) {
	abiSymbol := C.CString("diting_dns_cache_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", dnsCacheNativeCandidates())
	for _, candidate := range dnsCacheNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_dnscache_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_dnscache_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_dnscache_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_dns_cache_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_dnscache_call_abi(abi))
		if version != dnsCacheABIVersion {
			C.diting_dnscache_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, dnsCacheABIVersion)
			continue
		}
		lib := &dnsCacheNativeLib{lib: handle}
		if err := dnsCacheNativeSymbols(lib); err != nil {
			C.diting_dnscache_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		logf("dnsCache: Rust DNS cache kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// dnsCacheKernel returns the loaded library; the failure is kept so the probe runs once per
// process instead of once per query.
func dnsCacheKernel() (*dnsCacheNativeLib, error) {
	dnsCacheNativeOnce.Do(func() {
		dnsCacheNativeShared, dnsCacheNativeErr = loadDNSCacheNative()
		if dnsCacheNativeErr != nil {
			logf("dnsCache: Rust DNS cache kernel unavailable, answers will not be cached: %v",
				dnsCacheNativeErr)
		}
	})
	return dnsCacheNativeShared, dnsCacheNativeErr
}

// nativeQuestionKey builds the cache key of rawQuery into dst.
//
// dst must be maxCacheKeyLen bytes: the key is written in place so the hit path allocates nothing.
func nativeQuestionKey(rawQuery, dst []byte) (key []byte, nameLen int, qtype, qclass uint16, ok bool) {
	lib, err := dnsCacheKernel()
	if err != nil || len(dst) == 0 {
		return nil, 0, 0, 0, false
	}
	var length C.uint32_t
	var kind C.uint16_t
	var class C.uint16_t
	written := C.diting_dnscache_call_key(
		lib.questionKey,
		unsafe.Pointer(unsafe.SliceData(rawQuery)),
		C.size_t(len(rawQuery)),
		unsafe.Pointer(&dst[0]),
		C.size_t(len(dst)),
		&length,
		&kind,
		&class,
	)
	if written < 0 || int(written) > len(dst) {
		return nil, 0, 0, 0, false
	}
	return dst[:int(written)], int(length), uint16(kind), uint16(class), true
}

// nativeParseResponse turns one response into the metadata a cache write stores.
func nativeParseResponse(rawResponse []byte) (*dnsCacheResponseMeta, bool) {
	lib, err := dnsCacheKernel()
	if err != nil {
		return nil, false
	}
	var payload unsafe.Pointer
	var payloadLen C.size_t
	status := C.diting_dnscache_call_parse(
		lib.parseResponse,
		unsafe.Pointer(unsafe.SliceData(rawResponse)),
		C.size_t(len(rawResponse)),
		&payload,
		&payloadLen,
	)
	if status != 0 || payload == nil || payloadLen == 0 {
		return nil, false
	}
	defer C.diting_dnscache_call_free(lib.freeBytes, payload, payloadLen)

	// Copy before the deferred free: the bytes belong to the library until it frees them.
	meta, err := decodeDNSCacheResponse(unsafe.Slice((*byte)(payload), int(payloadLen)))
	if err != nil {
		return nil, false
	}
	return meta, true
}

// nativePatchResponse copies rawResponse and replaces the ID and every indexed TTL. It returns nil
// when the kernel is unavailable or rejects the request; callers treat that as a miss.
func nativePatchResponse(rawResponse []byte, offsets []uint16, queryID uint16, ttl uint32) []byte {
	lib, err := dnsCacheKernel()
	if err != nil || len(rawResponse) < 12 {
		return nil
	}
	patched := make([]byte, len(rawResponse))
	written := C.diting_dnscache_call_patch(
		lib.patchResponse,
		unsafe.Pointer(&rawResponse[0]),
		C.size_t(len(rawResponse)),
		unsafe.Pointer(unsafe.SliceData(offsets)),
		C.size_t(len(offsets)),
		C.uint16_t(queryID),
		C.uint32_t(ttl),
		unsafe.Pointer(&patched[0]),
		C.size_t(len(patched)),
	)
	if int(written) != len(patched) {
		return nil
	}
	return patched
}

// decodeDNSCacheResponse reads the payload rust/diting-dns-cache-core/src/payload.rs encodes.
func decodeDNSCacheResponse(payload []byte) (*dnsCacheResponseMeta, error) {
	if len(payload) < dnsCachePayloadBody {
		return nil, fmt.Errorf("dns cache response payload is truncated (header)")
	}
	if payload[0] != dnsCachePayloadLayoutVersion {
		return nil, fmt.Errorf("dns cache response payload layout %d, expected %d",
			payload[0], dnsCachePayloadLayoutVersion)
	}
	flags := payload[dnsCachePayloadFlags]
	meta := &dnsCacheResponseMeta{
		answerCount: int(binary.LittleEndian.Uint16(payload[dnsCachePayloadAnswerCount:])),
		rcode:       payload[dnsCachePayloadRcode],
		truncated:   flags&dnsCacheFlagTruncated != 0,
	}
	if flags&dnsCacheFlagMinTTL != 0 {
		meta.minTTL = binary.LittleEndian.Uint32(payload[dnsCachePayloadMinTTL:])
		meta.minTTLFound = true
	}

	reader := dnsCachePayloadReader{data: payload, position: dnsCachePayloadBody}
	var err error
	if meta.answerTTLOffsets, err = reader.offsetList("answer_ttl_offsets"); err != nil {
		return nil, err
	}
	if meta.authorityTTLOffsets, err = reader.offsetList("authority_ttl_offsets"); err != nil {
		return nil, err
	}

	targetCount, err := reader.u16("chain_target_count")
	if err != nil {
		return nil, err
	}
	if targetCount > 0 {
		meta.chainTargets = make([]chainTarget, 0, targetCount)
	}
	for i := 0; i < int(targetCount); i++ {
		code, err := reader.u8("chain_target_kind")
		if err != nil {
			return nil, err
		}
		var kind string
		switch code {
		case 0:
			kind = "cname"
		case 1:
			kind = "svcb"
		default:
			return nil, fmt.Errorf("dns cache response payload has unknown chain kind %d", code)
		}
		domain, err := reader.text("chain_target_domain")
		if err != nil {
			return nil, err
		}
		meta.chainTargets = append(meta.chainTargets, chainTarget{domain: domain, kind: kind})
	}

	ipCount, err := reader.u16("ip_count")
	if err != nil {
		return nil, err
	}
	if ipCount > 0 {
		meta.ipList = make([]string, 0, ipCount)
	}
	for i := 0; i < int(ipCount); i++ {
		ip, err := reader.text("ip")
		if err != nil {
			return nil, err
		}
		meta.ipList = append(meta.ipList, ip)
	}

	if meta.resolvedIPs, err = reader.text("resolved_ips"); err != nil {
		return nil, err
	}
	if reader.remaining() != 0 {
		return nil, fmt.Errorf("dns cache response payload has %d trailing bytes", reader.remaining())
	}
	return meta, nil
}

type dnsCachePayloadReader struct {
	data     []byte
	position int
}

func (r *dnsCachePayloadReader) remaining() int {
	return len(r.data) - r.position
}

func (r *dnsCachePayloadReader) u8(field string) (byte, error) {
	if r.remaining() < 1 {
		return 0, fmt.Errorf("dns cache response payload is truncated (%s)", field)
	}
	value := r.data[r.position]
	r.position++
	return value, nil
}

func (r *dnsCachePayloadReader) u16(field string) (uint16, error) {
	if r.remaining() < 2 {
		return 0, fmt.Errorf("dns cache response payload is truncated (%s)", field)
	}
	value := binary.LittleEndian.Uint16(r.data[r.position:])
	r.position += 2
	return value, nil
}

func (r *dnsCachePayloadReader) u32(field string) (uint32, error) {
	if r.remaining() < 4 {
		return 0, fmt.Errorf("dns cache response payload is truncated (%s)", field)
	}
	value := binary.LittleEndian.Uint32(r.data[r.position:])
	r.position += 4
	return value, nil
}

func (r *dnsCachePayloadReader) offsetList(field string) ([]uint16, error) {
	count, err := r.u16(field)
	if err != nil {
		return nil, err
	}
	if count == 0 {
		return nil, nil
	}
	offsets := make([]uint16, 0, count)
	for i := 0; i < int(count); i++ {
		offset, err := r.u16(field)
		if err != nil {
			return nil, err
		}
		offsets = append(offsets, offset)
	}
	return offsets, nil
}

func (r *dnsCachePayloadReader) text(field string) (string, error) {
	length, err := r.u32(field)
	if err != nil {
		return "", err
	}
	if length > uint32(r.remaining()) {
		return "", fmt.Errorf("dns cache response payload is truncated (%s)", field)
	}
	value := string(r.data[r.position : r.position+int(length)])
	r.position += int(length)
	return value, nil
}
