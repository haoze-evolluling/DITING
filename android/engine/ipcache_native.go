//go:build cgo

// ipcache_native.go loads the Rust IP → domain LRU kernel (rust/diting-ipcache-core) and drives
// its C ABI (that crate's src/ffi.rs).
//
// The kernel owns the map, the recency order, the in-place update + move-to-front, the eviction
// and the default capacity. Go keeps the `net.IP` → text conversion at the call sites and the
// buffer for the returned domain.
//
// If the library is missing or has a stale ABI the hints are disabled: every lookup misses. That
// only costs the hostname label of direct-IP flows; the tunnel and its answers are unaffected.

package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_ipcache_lib_t;
static diting_ipcache_lib_t diting_ipcache_open(const char* path) { return LoadLibraryA(path); }
static void* diting_ipcache_sym(diting_ipcache_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_ipcache_close(diting_ipcache_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_ipcache_lib_t;
static diting_ipcache_lib_t diting_ipcache_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_ipcache_sym(diting_ipcache_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_ipcache_close(diting_ipcache_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_ipcache_abi_fn)(void);
typedef void* (*diting_ipcache_new_fn)(int32_t);
typedef void (*diting_ipcache_handle_fn)(void*);
typedef uint32_t (*diting_ipcache_put_fn)(void*, const char*, size_t, const char*, size_t);
typedef intptr_t (*diting_ipcache_get_fn)(void*, const char*, size_t, void*, size_t);
typedef uint32_t (*diting_ipcache_len_fn)(void*);

static uint32_t diting_ipcache_call_abi(void* fn) { return ((diting_ipcache_abi_fn)fn)(); }
static void* diting_ipcache_call_new(void* fn, int32_t max_size) {
	return ((diting_ipcache_new_fn)fn)(max_size);
}
static void diting_ipcache_call_handle(void* fn, void* handle) {
	((diting_ipcache_handle_fn)fn)(handle);
}
static uint32_t diting_ipcache_call_put(void* fn, void* handle, const char* ip, size_t ip_len,
	const char* domain, size_t domain_len) {
	return ((diting_ipcache_put_fn)fn)(handle, ip, ip_len, domain, domain_len);
}
static intptr_t diting_ipcache_call_get(void* fn, void* handle, const char* ip, size_t ip_len,
	void* out, size_t out_cap) {
	return ((diting_ipcache_get_fn)fn)(handle, ip, ip_len, out, out_cap);
}
static uint32_t diting_ipcache_call_len(void* fn, void* handle) {
	return ((diting_ipcache_len_fn)fn)(handle);
}
*/
import "C"

import (
	"errors"
	"fmt"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"
)

// ipCacheABIVersion must match `ABI_VERSION` in rust/diting-ipcache-core/src/ffi.rs.
const ipCacheABIVersion = 1

// ipCacheDomainBuffer bounds one returned domain text. Valid DNS names are at most 255 bytes.
const ipCacheDomainBuffer = 512

type ipCacheNativeLib struct {
	lib C.diting_ipcache_lib_t

	new  unsafe.Pointer
	free unsafe.Pointer
	put  unsafe.Pointer
	get  unsafe.Pointer
	len  unsafe.Pointer
}

var (
	ipCacheNativeOnce   sync.Once
	ipCacheNativeShared *ipCacheNativeLib
	ipCacheNativeErr    error
)

func ipCacheNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_ipcache_core.dll"
	case "darwin":
		return "libditing_ipcache_core.dylib"
	default:
		return "libditing_ipcache_core.so"
	}
}

// ipCacheNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func ipCacheNativeCandidates() []string {
	name := ipCacheNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func ipCacheNativeSymbols(lib *ipCacheNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_ipcache_new", &lib.new},
		{"diting_ipcache_free", &lib.free},
		{"diting_ipcache_put", &lib.put},
		{"diting_ipcache_get", &lib.get},
		{"diting_ipcache_len", &lib.len},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_ipcache_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadIPCacheNative() (*ipCacheNativeLib, error) {
	abiSymbol := C.CString("diting_ipcache_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", ipCacheNativeCandidates())
	for _, candidate := range ipCacheNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_ipcache_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_ipcache_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_ipcache_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_ipcache_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_ipcache_call_abi(abi))
		if version != ipCacheABIVersion {
			C.diting_ipcache_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, ipCacheABIVersion)
			continue
		}
		lib := &ipCacheNativeLib{lib: handle}
		if err := ipCacheNativeSymbols(lib); err != nil {
			C.diting_ipcache_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		logf("IPDomainCache: Rust kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// ipCacheKernel returns the loaded library; the failure is kept so the probe runs once per process.
func ipCacheKernel() (*ipCacheNativeLib, error) {
	ipCacheNativeOnce.Do(func() {
		ipCacheNativeShared, ipCacheNativeErr = loadIPCacheNative()
		if ipCacheNativeErr != nil {
			logf("IPDomainCache: Rust kernel unavailable, hostname hints are disabled: %v",
				ipCacheNativeErr)
		}
	})
	return ipCacheNativeShared, ipCacheNativeErr
}

// nativeIPDomainCache owns one engine's cache handle.
type nativeIPDomainCache struct {
	lib     *ipCacheNativeLib
	pointer unsafe.Pointer
}

func newNativeIPDomainCache(maxSize int) (*nativeIPDomainCache, error) {
	lib, err := ipCacheKernel()
	if err != nil {
		return nil, err
	}
	pointer := C.diting_ipcache_call_new(lib.new, C.int32_t(maxSize))
	if pointer == nil {
		return nil, errors.New("ipcache kernel returned a null handle")
	}
	return &nativeIPDomainCache{lib: lib, pointer: pointer}, nil
}

// ipCacheText hands a Go string to the kernel. The kernel never keeps the pointer.
func ipCacheText(value string) (unsafe.Pointer, C.size_t) {
	if value == "" {
		return nil, 0
	}
	return unsafe.Pointer(unsafe.StringData(value)), C.size_t(len(value))
}

func (h *nativeIPDomainCache) put(ip, domain string) {
	if h == nil || h.pointer == nil {
		return
	}
	ipPtr, ipLen := ipCacheText(ip)
	domainPtr, domainLen := ipCacheText(domain)
	C.diting_ipcache_call_put(h.lib.put, h.pointer, (*C.char)(ipPtr), ipLen,
		(*C.char)(domainPtr), domainLen)
}

func (h *nativeIPDomainCache) get(ip string) string {
	if h == nil || h.pointer == nil {
		return ""
	}
	ipPtr, ipLen := ipCacheText(ip)
	var out [ipCacheDomainBuffer]byte
	written := C.diting_ipcache_call_get(h.lib.get, h.pointer, (*C.char)(ipPtr), ipLen,
		unsafe.Pointer(&out[0]), C.size_t(len(out)))
	if written <= 0 {
		return ""
	}
	return string(out[:int(written)])
}

func (h *nativeIPDomainCache) len() int {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int(C.diting_ipcache_call_len(h.lib.len, h.pointer))
}
