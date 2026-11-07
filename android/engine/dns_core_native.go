//go:build cgo

// dns_core_native.go loads the Rust DNS answer / block kernel (rust/diting-dns-core) and drives its
// C ABI (that crate's src/ffi.rs).
//
// The kernel owns two things Go used to keep itself: the answer inspection every forwarding path
// runs on a fresh upstream reply (is it a null block, and which addresses do we log) and the
// per-domain dynamic block escalation. Go keeps the `dns.Msg` walk that feeds the payload, the
// `time.Duration` conversion and the handle lifecycle; every call passes unix nanoseconds, so the
// kernel never reads a clock.
//
// The kernel is optional in the sense that a missing library only degrades those two features: a
// null-block answer is then logged as a normal answer, and dynamic escalation stays off (every
// block keeps the configured response mode). It never changes what is answered.
package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_dns_lib_t;
static diting_dns_lib_t diting_dns_open(const char* path) { return LoadLibraryA(path); }
static void* diting_dns_sym(diting_dns_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_dns_close(diting_dns_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_dns_lib_t;
static diting_dns_lib_t diting_dns_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_dns_sym(diting_dns_lib_t lib, const char* name) { return dlsym(lib, name); }
static void diting_dns_close(diting_dns_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_dns_abi_fn)(void);
typedef uint32_t (*diting_dns_inspect_fn)(const void*, size_t, void**, size_t*);
typedef void (*diting_dns_free_bytes_fn)(void*, size_t);
typedef void* (*diting_dns_new_fn)(void);
typedef void (*diting_dns_handle_fn)(void*);
typedef uint32_t (*diting_dns_response_fn)(void*, const void*, size_t, uint32_t, uint32_t,
	int64_t, int64_t, uint32_t, int64_t);

static uint32_t diting_dns_call_abi(void* fn) { return ((diting_dns_abi_fn)fn)(); }
static uint32_t diting_dns_call_inspect(void* fn, const void* payload, size_t length, void** out,
	size_t* out_len) {
	return ((diting_dns_inspect_fn)fn)(payload, length, out, out_len);
}
static void diting_dns_call_free_bytes(void* fn, void* pointer, size_t length) {
	((diting_dns_free_bytes_fn)fn)(pointer, length);
}
static void* diting_dns_call_new(void* fn) { return ((diting_dns_new_fn)fn)(); }
static void diting_dns_call_handle(void* fn, void* handle) { ((diting_dns_handle_fn)fn)(handle); }
static uint32_t diting_dns_call_response(void* fn, void* handle, const void* domain,
	size_t domain_len, uint32_t enabled, uint32_t threshold, int64_t window_ns, int64_t nxdomain_ns,
	uint32_t fallback, int64_t now_ns) {
	return ((diting_dns_response_fn)fn)(handle, domain, domain_len, enabled, threshold, window_ns,
		nxdomain_ns, fallback, now_ns);
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

// dnsCoreABIVersion must match `ABI_VERSION` in rust/diting-dns-core/src/ffi.rs.
const dnsCoreABIVersion = 1

type dnsCoreNativeLib struct {
	lib C.diting_dns_lib_t

	inspectAnswer unsafe.Pointer
	freeBytes     unsafe.Pointer
	blocksNew     unsafe.Pointer
	blocksFree    unsafe.Pointer
	blocksReset   unsafe.Pointer
	blocksRespond unsafe.Pointer
}

var (
	dnsCoreNativeOnce   sync.Once
	dnsCoreNativeShared *dnsCoreNativeLib
	dnsCoreNativeErr    error
)

func dnsCoreNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_dns_core.dll"
	case "darwin":
		return "libditing_dns_core.dylib"
	default:
		return "libditing_dns_core.so"
	}
}

// dnsCoreNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func dnsCoreNativeCandidates() []string {
	name := dnsCoreNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func dnsCoreNativeSymbols(lib *dnsCoreNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_dns_inspect_answer", &lib.inspectAnswer},
		{"diting_dns_free_bytes", &lib.freeBytes},
		{"diting_dns_blocks_new", &lib.blocksNew},
		{"diting_dns_blocks_free", &lib.blocksFree},
		{"diting_dns_blocks_reset", &lib.blocksReset},
		{"diting_dns_blocks_response", &lib.blocksRespond},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_dns_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadDNSCoreNative() (*dnsCoreNativeLib, error) {
	abiSymbol := C.CString("diting_dns_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", dnsCoreNativeCandidates())
	for _, candidate := range dnsCoreNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_dns_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_dns_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_dns_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_dns_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_dns_call_abi(abi))
		if version != dnsCoreABIVersion {
			C.diting_dns_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, dnsCoreABIVersion)
			continue
		}
		lib := &dnsCoreNativeLib{lib: handle}
		if err := dnsCoreNativeSymbols(lib); err != nil {
			C.diting_dns_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		logf("DNS answer kernel: Rust kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// dnsCoreKernel returns the loaded library; the failure is kept so the probe runs once per process.
func dnsCoreKernel() (*dnsCoreNativeLib, error) {
	dnsCoreNativeOnce.Do(func() {
		dnsCoreNativeShared, dnsCoreNativeErr = loadDNSCoreNative()
		if dnsCoreNativeErr != nil {
			logf("DNS answer kernel: Rust kernel unavailable, answer inspection and dynamic "+
				"blocking are degraded: %v", dnsCoreNativeErr)
		}
	})
	return dnsCoreNativeShared, dnsCoreNativeErr
}

// dnsCoreAvailable reports whether the kernel loaded. Callers use it so a missing library is
// logged once by the loader instead of once per answer.
func dnsCoreAvailable() bool {
	_, err := dnsCoreKernel()
	return err == nil
}

// inspectNativeAnswer hands the encoded answer to the kernel and decodes the report.
func inspectNativeAnswer(payload []byte) (blocked bool, addresses string, err error) {
	lib, err := dnsCoreKernel()
	if err != nil {
		return false, "", err
	}
	var out unsafe.Pointer
	var outLen C.size_t
	status := C.diting_dns_call_inspect(
		lib.inspectAnswer,
		unsafe.Pointer(unsafe.SliceData(payload)),
		C.size_t(len(payload)),
		&out,
		&outLen,
	)
	if status != 0 {
		return false, "", fmt.Errorf("answer kernel rejected the request (status %d)", status)
	}
	defer C.diting_dns_call_free_bytes(lib.freeBytes, out, outLen)
	if out == nil || outLen == 0 {
		return false, "", errors.New("answer kernel returned an empty report")
	}
	return decodeAnswerResponse(C.GoBytes(out, C.int(outLen)))
}

// nativeDynamicBlocks owns the per-engine dynamic block tracker of the kernel.
type nativeDynamicBlocks struct {
	lib     *dnsCoreNativeLib
	pointer unsafe.Pointer
}

func newNativeDynamicBlocks() (*nativeDynamicBlocks, error) {
	lib, err := dnsCoreKernel()
	if err != nil {
		return nil, err
	}
	pointer := C.diting_dns_call_new(lib.blocksNew)
	if pointer == nil {
		return nil, errors.New("dns kernel returned a null block tracker")
	}
	return &nativeDynamicBlocks{lib: lib, pointer: pointer}, nil
}

func (h *nativeDynamicBlocks) reset() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_dns_call_handle(h.lib.blocksReset, h.pointer)
}

func (h *nativeDynamicBlocks) response(
	domain string,
	enabled bool,
	threshold uint32,
	windowNs, nxDomainNs int64,
	fallback uint32,
	nowNs int64,
) ResponseType {
	if h == nil || h.pointer == nil {
		return ResponseType(fallback)
	}
	flag := C.uint32_t(0)
	if enabled {
		flag = 1
	}
	pointer := unsafe.Pointer(unsafe.StringData(domain))
	length := C.size_t(len(domain))
	return ResponseType(C.diting_dns_call_response(
		h.lib.blocksRespond,
		h.pointer,
		pointer,
		length,
		flag,
		C.uint32_t(threshold),
		C.int64_t(windowNs),
		C.int64_t(nxDomainNs),
		C.uint32_t(fallback),
		C.int64_t(nowNs),
	))
}

func (h *nativeDynamicBlocks) free() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_dns_call_handle(h.lib.blocksFree, h.pointer)
	h.pointer = nil
}
