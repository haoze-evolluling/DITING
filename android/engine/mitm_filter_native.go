//go:build cgo

// mitm_filter_native.go loads the Rust MITM filter kernel (rust/diting-mitm-core) and drives its C
// ABI (that crate's src/ffi.rs).
//
// The kernel owns the allow list, the `path.Match` exclusion patterns, the sensitive-host
// heuristics, the blacklist with its failure streaks and the persistent blacklist file. Go keeps
// the log lines and the handle lifecycle. Every stateful call passes `now_ms` so the kernel never
// reads a clock of its own.
//
// The kernel is required: `NewMitmFilter` fails without it, which fails `StartStackMitm`, so the
// tunnel runs without interception instead of silently decrypting endpoints the old filter
// skipped.
package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_mitm_lib_t;
static diting_mitm_lib_t diting_mitm_open(const char* path) { return LoadLibraryA(path); }
static void* diting_mitm_sym(diting_mitm_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_mitm_close(diting_mitm_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_mitm_lib_t;
static diting_mitm_lib_t diting_mitm_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_mitm_sym(diting_mitm_lib_t lib, const char* name) { return dlsym(lib, name); }
static void diting_mitm_close(diting_mitm_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_mitm_abi_fn)(void);
typedef void* (*diting_mitm_new_fn)(void);
typedef void (*diting_mitm_handle_fn)(void*);
typedef void (*diting_mitm_free_bytes_fn)(void*, size_t);
typedef uint32_t (*diting_mitm_text_fn)(void*, const void*, size_t);
typedef uint32_t (*diting_mitm_uid_fn)(void*, int64_t);
typedef uint32_t (*diting_mitm_flag_fn)(void*);
typedef uint32_t (*diting_mitm_allow_fn)(void*, const void*, size_t, int64_t);
typedef void (*diting_mitm_failure_fn)(void*, const void*, size_t, const void*, size_t, int64_t,
	void**, size_t*);
typedef uint32_t (*diting_mitm_blacklist_fn)(void*, const void*, size_t, const void*, size_t,
	int64_t, void**, size_t*);
typedef void (*diting_mitm_remove_fn)(void*, const void*, size_t);
typedef uint32_t (*diting_mitm_path_fn)(void*, const void*, size_t, int64_t);
typedef uint32_t (*diting_mitm_count_fn)(void*, int64_t);

static uint32_t diting_mitm_call_abi(void* fn) { return ((diting_mitm_abi_fn)fn)(); }
static void* diting_mitm_call_new(void* fn) { return ((diting_mitm_new_fn)fn)(); }
static void diting_mitm_call_handle(void* fn, void* handle) { ((diting_mitm_handle_fn)fn)(handle); }
static void diting_mitm_call_free_bytes(void* fn, void* pointer, size_t length) {
	((diting_mitm_free_bytes_fn)fn)(pointer, length);
}
static uint32_t diting_mitm_call_text(void* fn, void* handle, const void* text, size_t length) {
	return ((diting_mitm_text_fn)fn)(handle, text, length);
}
static uint32_t diting_mitm_call_uid(void* fn, void* handle, int64_t uid) {
	return ((diting_mitm_uid_fn)fn)(handle, uid);
}
static uint32_t diting_mitm_call_flag(void* fn, void* handle) {
	return ((diting_mitm_flag_fn)fn)(handle);
}
static uint32_t diting_mitm_call_allow(void* fn, void* handle, const void* host, size_t host_len,
	int64_t now_ms) {
	return ((diting_mitm_allow_fn)fn)(handle, host, host_len, now_ms);
}
static void diting_mitm_call_failure(void* fn, void* handle, const void* host, size_t host_len,
	const void* text, size_t text_len, int64_t now_ms, void** payload, size_t* payload_len) {
	((diting_mitm_failure_fn)fn)(handle, host, host_len, text, text_len, now_ms, payload,
		payload_len);
}
static uint32_t diting_mitm_call_blacklist(void* fn, void* handle, const void* host,
	size_t host_len, const void* reason, size_t reason_len, int64_t now_ms, void** payload,
	size_t* payload_len) {
	return ((diting_mitm_blacklist_fn)fn)(handle, host, host_len, reason, reason_len, now_ms,
		payload, payload_len);
}
static void diting_mitm_call_remove(void* fn, void* handle, const void* host, size_t host_len) {
	((diting_mitm_remove_fn)fn)(handle, host, host_len);
}
static uint32_t diting_mitm_call_path(void* fn, void* handle, const void* path, size_t path_len,
	int64_t now_ms) {
	return ((diting_mitm_path_fn)fn)(handle, path, path_len, now_ms);
}
static uint32_t diting_mitm_call_count(void* fn, void* handle, int64_t now_ms) {
	return ((diting_mitm_count_fn)fn)(handle, now_ms);
}
*/
import "C"

import (
	"encoding/binary"
	"errors"
	"fmt"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"
)

// mitmFilterABIVersion must match `ABI_VERSION` in rust/diting-mitm-core/src/ffi.rs.
const mitmFilterABIVersion = 1

// mitmFilterPayloadLayoutVersion must match `payload::LAYOUT_VERSION`.
const mitmFilterPayloadLayoutVersion = 1

// Report flag bits; see rust/diting-mitm-core/src/payload.rs.
const (
	mitmReportRecorded    = 1 << 0
	mitmReportBlacklisted = 1 << 1
	mitmReportAdded       = 1 << 2
)

type mitmNativeLib struct {
	lib C.diting_mitm_lib_t

	newFilter unsafe.Pointer
	free      unsafe.Pointer
	freeBytes unsafe.Pointer

	setUIDs  unsafe.Pointer
	isUID    unsafe.Pointer
	hasUIDs  unsafe.Pointer
	setRules unsafe.Pointer
	allows   unsafe.Pointer

	failure   unsafe.Pointer
	blacklist unsafe.Pointer
	clear     unsafe.Pointer
	remove    unsafe.Pointer
	loadPath  unsafe.Pointer
	count     unsafe.Pointer
}

var (
	mitmNativeOnce   sync.Once
	mitmNativeShared *mitmNativeLib
	mitmNativeErr    error
)

func mitmNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_mitm_core.dll"
	case "darwin":
		return "libditing_mitm_core.dylib"
	default:
		return "libditing_mitm_core.so"
	}
}

// mitmNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func mitmNativeCandidates() []string {
	name := mitmNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func mitmNativeSymbols(lib *mitmNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_mitm_new", &lib.newFilter},
		{"diting_mitm_free", &lib.free},
		{"diting_mitm_free_bytes", &lib.freeBytes},
		{"diting_mitm_set_allowed_uids", &lib.setUIDs},
		{"diting_mitm_is_uid_allowed", &lib.isUID},
		{"diting_mitm_has_allowed_uids", &lib.hasUIDs},
		{"diting_mitm_set_bypass_rules", &lib.setRules},
		{"diting_mitm_allows_interception", &lib.allows},
		{"diting_mitm_record_failure", &lib.failure},
		{"diting_mitm_blacklist", &lib.blacklist},
		{"diting_mitm_clear", &lib.clear},
		{"diting_mitm_remove", &lib.remove},
		{"diting_mitm_load_persistent", &lib.loadPath},
		{"diting_mitm_blacklist_count", &lib.count},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_mitm_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadMitmNative() (*mitmNativeLib, error) {
	abiSymbol := C.CString("diting_mitm_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", mitmNativeCandidates())
	for _, candidate := range mitmNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_mitm_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_mitm_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_mitm_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_mitm_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_mitm_call_abi(abi))
		if version != mitmFilterABIVersion {
			C.diting_mitm_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, mitmFilterABIVersion)
			continue
		}
		lib := &mitmNativeLib{lib: handle}
		if err := mitmNativeSymbols(lib); err != nil {
			C.diting_mitm_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		logf("MITM Filter: Rust kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// mitmKernel returns the loaded library; the failure is kept so the probe runs once per process.
func mitmKernel() (*mitmNativeLib, error) {
	mitmNativeOnce.Do(func() {
		mitmNativeShared, mitmNativeErr = loadMitmNative()
		if mitmNativeErr != nil {
			logf("MITM Filter: Rust kernel unavailable, MITM cannot start: %v", mitmNativeErr)
		}
	})
	return mitmNativeShared, mitmNativeErr
}

// nativeMitmFilter owns one Rust filter handle.
type nativeMitmFilter struct {
	lib     *mitmNativeLib
	pointer unsafe.Pointer
}

func newNativeMitmFilter() (*nativeMitmFilter, error) {
	lib, err := mitmKernel()
	if err != nil {
		return nil, err
	}
	pointer := C.diting_mitm_call_new(lib.newFilter)
	if pointer == nil {
		return nil, errors.New("mitm kernel returned a null filter handle")
	}
	return &nativeMitmFilter{lib: lib, pointer: pointer}, nil
}

// mitmText hands a Go string to the kernel. The kernel never keeps the pointer.
func mitmText(value string) (unsafe.Pointer, C.size_t) {
	if value == "" {
		return nil, 0
	}
	return unsafe.Pointer(unsafe.StringData(value)), C.size_t(len(value))
}

// copyMitmPayload copies a payload out of the library and frees it.
func copyMitmPayload(lib *mitmNativeLib, pointer unsafe.Pointer, length C.size_t) []byte {
	if pointer == nil {
		return nil
	}
	defer C.diting_mitm_call_free_bytes(lib.freeBytes, pointer, length)
	if length == 0 {
		return nil
	}
	return C.GoBytes(pointer, C.int(length))
}

func (h *nativeMitmFilter) setAllowedUIDs(csv string) int {
	if h == nil || h.pointer == nil {
		return 0
	}
	text, length := mitmText(csv)
	return int(C.diting_mitm_call_text(h.lib.setUIDs, h.pointer, text, length))
}

func (h *nativeMitmFilter) isUIDAllowed(uid int64) bool {
	if h == nil || h.pointer == nil {
		return false
	}
	return C.diting_mitm_call_uid(h.lib.isUID, h.pointer, C.int64_t(uid)) == 1
}

func (h *nativeMitmFilter) hasAllowedUIDs() bool {
	if h == nil || h.pointer == nil {
		return false
	}
	return C.diting_mitm_call_flag(h.lib.hasUIDs, h.pointer) == 1
}

func (h *nativeMitmFilter) setBypassRules(content string) int {
	if h == nil || h.pointer == nil {
		return 0
	}
	text, length := mitmText(content)
	return int(C.diting_mitm_call_text(h.lib.setRules, h.pointer, text, length))
}

func (h *nativeMitmFilter) allowsInterception(host string, nowMs int64) bool {
	if h == nil || h.pointer == nil {
		return false
	}
	text, length := mitmText(host)
	return C.diting_mitm_call_allow(h.lib.allows, h.pointer, text, length, C.int64_t(nowMs)) == 1
}

func (h *nativeMitmFilter) recordFailure(host, errText string, nowMs int64) mitmReport {
	if h == nil || h.pointer == nil {
		return mitmReport{}
	}
	hostPtr, hostLen := mitmText(host)
	textPtr, textLen := mitmText(errText)
	var payload unsafe.Pointer
	var payloadLen C.size_t
	C.diting_mitm_call_failure(
		h.lib.failure,
		h.pointer,
		hostPtr,
		hostLen,
		textPtr,
		textLen,
		C.int64_t(nowMs),
		&payload,
		&payloadLen,
	)
	return h.decodeReport(copyMitmPayload(h.lib, payload, payloadLen))
}

func (h *nativeMitmFilter) blacklist(host, reason string, nowMs int64) (mitmReport, bool) {
	if h == nil || h.pointer == nil {
		return mitmReport{}, false
	}
	hostPtr, hostLen := mitmText(host)
	reasonPtr, reasonLen := mitmText(reason)
	var payload unsafe.Pointer
	var payloadLen C.size_t
	status := C.diting_mitm_call_blacklist(
		h.lib.blacklist,
		h.pointer,
		hostPtr,
		hostLen,
		reasonPtr,
		reasonLen,
		C.int64_t(nowMs),
		&payload,
		&payloadLen,
	)
	if status == 0 {
		return mitmReport{}, false
	}
	return h.decodeReport(copyMitmPayload(h.lib, payload, payloadLen)), true
}

func (h *nativeMitmFilter) clear() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_mitm_call_handle(h.lib.clear, h.pointer)
}

func (h *nativeMitmFilter) remove(host string) {
	if h == nil || h.pointer == nil {
		return
	}
	text, length := mitmText(host)
	C.diting_mitm_call_remove(h.lib.remove, h.pointer, text, length)
}

func (h *nativeMitmFilter) loadPersistent(path string, nowMs int64) int {
	if h == nil || h.pointer == nil {
		return 0
	}
	text, length := mitmText(path)
	return int(C.diting_mitm_call_path(h.lib.loadPath, h.pointer, text, length, C.int64_t(nowMs)))
}

func (h *nativeMitmFilter) blacklistCount(nowMs int64) int {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int(C.diting_mitm_call_count(h.lib.count, h.pointer, C.int64_t(nowMs)))
}

func (h *nativeMitmFilter) free() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_mitm_call_handle(h.lib.free, h.pointer)
	h.pointer = nil
}

// decodeReport reads the report payload the kernel encodes (see payload.rs).
func (h *nativeMitmFilter) decodeReport(data []byte) mitmReport {
	if len(data) == 0 {
		return mitmReport{}
	}
	report, err := decodeMitmReport(data)
	if err != nil {
		logf("MITM Filter: bad report payload from the kernel: %v", err)
		return mitmReport{}
	}
	return report
}

func decodeMitmReport(payload []byte) (mitmReport, error) {
	reader := &mitmPayloadReader{data: payload}
	if err := reader.expectLayout(); err != nil {
		return mitmReport{}, err
	}
	flags, err := reader.u8("flags")
	if err != nil {
		return mitmReport{}, err
	}
	count, err := reader.u32("count")
	if err != nil {
		return mitmReport{}, err
	}
	threshold, err := reader.u32("threshold")
	if err != nil {
		return mitmReport{}, err
	}
	ttlMs, err := reader.i64("ttl_ms")
	if err != nil {
		return mitmReport{}, err
	}
	host, err := reader.text("host")
	if err != nil {
		return mitmReport{}, err
	}
	reason, err := reader.text("reason")
	if err != nil {
		return mitmReport{}, err
	}
	writeError, err := reader.text("write_error")
	if err != nil {
		return mitmReport{}, err
	}
	if err := reader.expectEnd(); err != nil {
		return mitmReport{}, err
	}
	report := mitmReport{
		recorded:    flags&mitmReportRecorded != 0,
		blacklisted: flags&mitmReportBlacklisted != 0,
		added:       flags&mitmReportAdded != 0,
		count:       count,
		threshold:   threshold,
		host:        host,
		writeError:  writeError,
	}
	if report.added {
		report.reason = reason
		report.ttlMs = ttlMs
	}
	return report, nil
}

type mitmPayloadReader struct {
	data     []byte
	position int
}

func (r *mitmPayloadReader) remaining() int {
	return len(r.data) - r.position
}

func (r *mitmPayloadReader) truncated(field string) error {
	return fmt.Errorf("mitm report payload is truncated (%s)", field)
}

func (r *mitmPayloadReader) expectLayout() error {
	if r.remaining() < 1 {
		return r.truncated("layout")
	}
	if r.data[0] != mitmFilterPayloadLayoutVersion {
		return fmt.Errorf("mitm report payload layout %d, expected %d",
			r.data[0], mitmFilterPayloadLayoutVersion)
	}
	r.position = 1
	return nil
}

func (r *mitmPayloadReader) u8(field string) (byte, error) {
	if r.remaining() < 1 {
		return 0, r.truncated(field)
	}
	value := r.data[r.position]
	r.position++
	return value, nil
}

func (r *mitmPayloadReader) u32(field string) (uint32, error) {
	if r.remaining() < 4 {
		return 0, r.truncated(field)
	}
	value := binary.LittleEndian.Uint32(r.data[r.position:])
	r.position += 4
	return value, nil
}

func (r *mitmPayloadReader) i64(field string) (int64, error) {
	if r.remaining() < 8 {
		return 0, r.truncated(field)
	}
	value := binary.LittleEndian.Uint64(r.data[r.position:])
	r.position += 8
	return int64(value), nil
}

func (r *mitmPayloadReader) text(field string) (string, error) {
	length, err := r.u32(field + " length")
	if err != nil {
		return "", err
	}
	if uint64(length) > uint64(r.remaining()) {
		return "", r.truncated(field)
	}
	value := r.data[r.position : r.position+int(length)]
	r.position += int(length)
	return string(value), nil
}

func (r *mitmPayloadReader) expectEnd() error {
	if r.remaining() != 0 {
		return fmt.Errorf("mitm report payload has %d trailing bytes", r.remaining())
	}
	return nil
}
