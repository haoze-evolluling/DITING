//go:build cgo

// allowlist_native.go loads the Rust app-allowlist kernel (rust/diting-allowlist-core) and drives
// its C ABI (that crate's src/ffi.rs).
//
// Responsibility split: the kernel owns the normalized allowed-domain sets, the suffix walk, the
// per-UID TTL grants, the answer fan-out and the 256-entry pruning. Go keeps the JSON config, the
// `dns.Msg` A/AAAA traversal and the `net.IP` loopback fast path. Every call that needs a clock
// passes unix nanoseconds, so the kernel never reads one.
//
// If the library is missing or has a stale ABI the wrapper logs once and treats a *configured*
// allowlist as fail-closed: DNS queries and connections are denied instead of silently allowing
// everything. That is the only safe degradation for an authorization feature, and it never affects
// engines that did not configure any rule.
package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_allowlist_lib_t;
static diting_allowlist_lib_t diting_allowlist_open(const char* path) { return LoadLibraryA(path); }
static void* diting_allowlist_sym(diting_allowlist_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_allowlist_close(diting_allowlist_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_allowlist_lib_t;
static diting_allowlist_lib_t diting_allowlist_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_allowlist_sym(diting_allowlist_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_allowlist_close(diting_allowlist_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_allowlist_abi_fn)(void);
typedef void* (*diting_allowlist_new_fn)(void);
typedef void (*diting_allowlist_handle_fn)(void*);
typedef uint32_t (*diting_allowlist_configure_fn)(void*, const void*, size_t);
typedef uint32_t (*diting_allowlist_has_uids_fn)(void*);
typedef uint32_t (*diting_allowlist_domain_fn)(void*, int32_t, const char*, size_t);
typedef uint32_t (*diting_allowlist_connection_fn)(void*, int32_t, const void*, size_t, int64_t);
typedef uint32_t (*diting_allowlist_remember_fn)(void*, const void*, size_t, int64_t);
typedef uint32_t (*diting_allowlist_count_fn)(void*, int32_t);

static uint32_t diting_allowlist_call_abi(void* fn) { return ((diting_allowlist_abi_fn)fn)(); }
static void* diting_allowlist_call_new(void* fn) { return ((diting_allowlist_new_fn)fn)(); }
static void diting_allowlist_call_handle(void* fn, void* handle) {
	((diting_allowlist_handle_fn)fn)(handle);
}
static uint32_t diting_allowlist_call_configure(void* fn, void* handle, const void* payload,
	size_t length) {
	return ((diting_allowlist_configure_fn)fn)(handle, payload, length);
}
static uint32_t diting_allowlist_call_has_uids(void* fn, void* handle) {
	return ((diting_allowlist_has_uids_fn)fn)(handle);
}
static uint32_t diting_allowlist_call_domain(void* fn, void* handle, int32_t uid,
	const char* domain, size_t length) {
	return ((diting_allowlist_domain_fn)fn)(handle, uid, domain, length);
}
static uint32_t diting_allowlist_call_connection(void* fn, void* handle, int32_t uid,
	const void* address, size_t length, int64_t now_ns) {
	return ((diting_allowlist_connection_fn)fn)(handle, uid, address, length, now_ns);
}
static uint32_t diting_allowlist_call_remember(void* fn, void* handle, const void* payload,
	size_t length, int64_t now_ns) {
	return ((diting_allowlist_remember_fn)fn)(handle, payload, length, now_ns);
}
static uint32_t diting_allowlist_call_grant_count(void* fn, void* handle, int32_t uid) {
	return ((diting_allowlist_count_fn)fn)(handle, uid);
}
*/
import "C"

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"path/filepath"
	"runtime"
	"sync"
	"time"
	"unsafe"
)

// allowlistABIVersion must match `ABI_VERSION` in rust/diting-allowlist-core/src/ffi.rs.
const allowlistABIVersion = 1

// allowlistPayloadLayoutVersion must match `LAYOUT_VERSION` in the kernel's payload.rs.
const allowlistPayloadLayoutVersion = 1

type allowlistNativeLib struct {
	lib C.diting_allowlist_lib_t

	new        unsafe.Pointer
	free       unsafe.Pointer
	configure  unsafe.Pointer
	hasUIDs    unsafe.Pointer
	domain     unsafe.Pointer
	connection unsafe.Pointer
	remember   unsafe.Pointer
	grantCount unsafe.Pointer
}

var (
	allowlistNativeOnce   sync.Once
	allowlistNativeShared *allowlistNativeLib
	allowlistNativeErr    error
)

func allowlistNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_allowlist_core.dll"
	case "darwin":
		return "libditing_allowlist_core.dylib"
	default:
		return "libditing_allowlist_core.so"
	}
}

// allowlistNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func allowlistNativeCandidates() []string {
	name := allowlistNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func allowlistNativeSymbols(lib *allowlistNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_allowlist_new", &lib.new},
		{"diting_allowlist_free", &lib.free},
		{"diting_allowlist_configure", &lib.configure},
		{"diting_allowlist_has_uids", &lib.hasUIDs},
		{"diting_allowlist_domain_allowed", &lib.domain},
		{"diting_allowlist_connection_allowed", &lib.connection},
		{"diting_allowlist_remember", &lib.remember},
		{"diting_allowlist_grant_count", &lib.grantCount},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_allowlist_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadAllowlistNative() (*allowlistNativeLib, error) {
	abiSymbol := C.CString("diting_allowlist_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", allowlistNativeCandidates())
	for _, candidate := range allowlistNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_allowlist_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_allowlist_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_allowlist_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_allowlist_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_allowlist_call_abi(abi))
		if version != allowlistABIVersion {
			C.diting_allowlist_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, allowlistABIVersion)
			continue
		}
		lib := &allowlistNativeLib{lib: handle}
		if err := allowlistNativeSymbols(lib); err != nil {
			C.diting_allowlist_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		logf("AppAllowlist: Rust kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// allowlistKernel returns the loaded library; the failure is kept so the probe runs once per
// process.
func allowlistKernel() (*allowlistNativeLib, error) {
	allowlistNativeOnce.Do(func() {
		allowlistNativeShared, allowlistNativeErr = loadAllowlistNative()
		if allowlistNativeErr != nil {
			logf("AppAllowlist: Rust kernel unavailable; a configured allowlist fails closed: %v",
				allowlistNativeErr)
		}
	})
	return allowlistNativeShared, allowlistNativeErr
}

// nativeAllowlist owns one engine's kernel handle.
type nativeAllowlist struct {
	lib     *allowlistNativeLib
	pointer unsafe.Pointer
}

func newNativeAllowlist() (*nativeAllowlist, error) {
	lib, err := allowlistKernel()
	if err != nil {
		return nil, err
	}
	pointer := C.diting_allowlist_call_new(lib.new)
	if pointer == nil {
		return nil, errors.New("allowlist kernel returned a null handle")
	}
	return &nativeAllowlist{lib: lib, pointer: pointer}, nil
}

// allowlistText hands a Go string to the kernel. The kernel never keeps the pointer.
func allowlistText(value string) (unsafe.Pointer, C.size_t) {
	if value == "" {
		return nil, 0
	}
	return unsafe.Pointer(unsafe.StringData(value)), C.size_t(len(value))
}

// allowlistBytes hands a Go byte slice to the kernel; empty becomes null / 0.
func allowlistBytes(value []byte) (unsafe.Pointer, C.size_t) {
	if len(value) == 0 {
		return nil, 0
	}
	return unsafe.Pointer(&value[0]), C.size_t(len(value))
}

func encodeAllowlistConfigure(entries []appAllowlistEntry) []byte {
	payload := make([]byte, 5)
	payload[0] = allowlistPayloadLayoutVersion
	binary.LittleEndian.PutUint32(payload[1:5], uint32(len(entries)))
	for _, entry := range entries {
		var fixed [8]byte
		binary.LittleEndian.PutUint32(fixed[0:4], uint32(entry.uid))
		binary.LittleEndian.PutUint32(fixed[4:8], uint32(len(entry.domains)))
		payload = append(payload, fixed[:]...)
		for _, domain := range entry.domains {
			var length [4]byte
			binary.LittleEndian.PutUint32(length[:], uint32(len(domain)))
			payload = append(payload, length[:]...)
			payload = append(payload, domain...)
		}
	}
	return payload
}

func encodeAllowlistRemember(uid int, questionName string, records []allowlistRecord) []byte {
	payload := make([]byte, 9)
	payload[0] = allowlistPayloadLayoutVersion
	binary.LittleEndian.PutUint32(payload[1:5], uint32(uid))
	binary.LittleEndian.PutUint32(payload[5:9], uint32(len(questionName)))
	payload = append(payload, questionName...)
	var count [4]byte
	binary.LittleEndian.PutUint32(count[:], uint32(len(records)))
	payload = append(payload, count[:]...)
	for _, record := range records {
		payload = append(payload, byte(len(record.address)))
		payload = append(payload, record.address...)
		var ttl [4]byte
		binary.LittleEndian.PutUint32(ttl[:], record.ttl)
		payload = append(payload, ttl[:]...)
	}
	return payload
}

func (h *nativeAllowlist) configure(entries []appAllowlistEntry) error {
	if h == nil || h.pointer == nil {
		return errors.New("allowlist kernel is not available")
	}
	payload := encodeAllowlistConfigure(entries)
	status := C.diting_allowlist_call_configure(h.lib.configure, h.pointer,
		unsafe.Pointer(&payload[0]), C.size_t(len(payload)))
	if status != 0 {
		return fmt.Errorf("allowlist configure failed (status %d)", uint32(status))
	}
	return nil
}

func (h *nativeAllowlist) hasUIDs() bool {
	if h == nil || h.pointer == nil {
		return false
	}
	return C.diting_allowlist_call_has_uids(h.lib.hasUIDs, h.pointer) == 1
}

func (h *nativeAllowlist) domainAllowed(uid int, domain string) bool {
	if h == nil || h.pointer == nil {
		return false
	}
	text, length := allowlistText(domain)
	return C.diting_allowlist_call_domain(h.lib.domain, h.pointer, C.int32_t(uid),
		(*C.char)(text), length) == 1
}

func (h *nativeAllowlist) connectionAllowed(uid int, ip net.IP, now time.Time) bool {
	if h == nil || h.pointer == nil {
		return false
	}
	address, length := allowlistBytes(ip)
	return C.diting_allowlist_call_connection(h.lib.connection, h.pointer, C.int32_t(uid),
		address, length, C.int64_t(now.UnixNano())) == 1
}

func (h *nativeAllowlist) remember(uid int, questionName string, records []allowlistRecord, now time.Time) error {
	if h == nil || h.pointer == nil {
		return errors.New("allowlist kernel is not available")
	}
	payload := encodeAllowlistRemember(uid, questionName, records)
	status := C.diting_allowlist_call_remember(h.lib.remember, h.pointer,
		unsafe.Pointer(&payload[0]), C.size_t(len(payload)), C.int64_t(now.UnixNano()))
	if status != 0 {
		return fmt.Errorf("allowlist remember failed (status %d)", uint32(status))
	}
	return nil
}

func (h *nativeAllowlist) grantCount(uid int) int {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int(C.diting_allowlist_call_grant_count(h.lib.grantCount, h.pointer, C.int32_t(uid)))
}
