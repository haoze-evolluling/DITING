//go:build cgo

// dns_cache_native.go loads the Rust DNS cache kernel (rust/diting-dns-cache-core) and drives its
// C ABI (that crate's src/ffi.rs).
//
// Responsibility split: the kernel owns the wire layer, the sharded container, the TTL policy, the
// background sweeper and the snapshot projection. Go keeps the single-flight coalescer around the
// resolver callback (it runs a Go function) and marshals the projection to JSON.
//
// The kernel is required for the cache to work, but not for the tunnel: if the library is missing
// or has a stale ABI, `newNativeDNSCache` fails, nothing is stored and every lookup misses, so
// queries go straight to the resolver. That is the same answer the old Go code produced without a
// cache, and the failure is logged once instead of silently serving different TTL/ID semantics.
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
typedef void (*diting_dnscache_free_bytes_fn)(void*, size_t);

static uint32_t diting_dnscache_call_abi(void* fn) { return ((diting_dnscache_abi_fn)fn)(); }
static intptr_t diting_dnscache_call_key(void* fn, const void* wire, size_t wire_len, void* out,
	size_t out_cap, uint32_t* name_len, uint16_t* qtype, uint16_t* qclass) {
	return ((diting_dnscache_key_fn)fn)(wire, wire_len, out, out_cap, name_len, qtype, qclass);
}
static void diting_dnscache_call_free(void* fn, void* pointer, size_t length) {
	((diting_dnscache_free_bytes_fn)fn)(pointer, length);
}
*/
import "C"

import (
	"fmt"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"
)

type dnsCacheNativeLib struct {
	lib unsafe.Pointer

	questionKey unsafe.Pointer
	freeBytes   unsafe.Pointer

	newCache     unsafe.Pointer
	freeHandle   unsafe.Pointer
	closeHandle  unsafe.Pointer
	updatePolicy unsafe.Pointer
	clear        unsafe.Pointer
	get          unsafe.Pointer
	put          unsafe.Pointer
	refreshBegin unsafe.Pointer
	refreshDone  unsafe.Pointer
	stats        unsafe.Pointer
	snapshot     unsafe.Pointer
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
		{"diting_dns_cache_free_bytes", &lib.freeBytes},
		{"diting_dns_cache_new", &lib.newCache},
		{"diting_dns_cache_free", &lib.freeHandle},
		{"diting_dns_cache_close", &lib.closeHandle},
		{"diting_dns_cache_update_policy", &lib.updatePolicy},
		{"diting_dns_cache_clear", &lib.clear},
		{"diting_dns_cache_get", &lib.get},
		{"diting_dns_cache_put", &lib.put},
		{"diting_dns_cache_refresh_begin", &lib.refreshBegin},
		{"diting_dns_cache_refresh_done", &lib.refreshDone},
		{"diting_dns_cache_stats", &lib.stats},
		{"diting_dns_cache_snapshot", &lib.snapshot},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_dnscache_sym(C.diting_dnscache_lib_t(lib.lib), name)
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
		lib := &dnsCacheNativeLib{lib: unsafe.Pointer(handle)}
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

// freeDNSCachePayload drops a payload the library handed back.
func freeDNSCachePayload(lib *dnsCacheNativeLib, pointer unsafe.Pointer, length uintptr) {
	if pointer == nil || length == 0 {
		return
	}
	C.diting_dnscache_call_free(lib.freeBytes, pointer, C.size_t(length))
}
