//go:build cgo

// proxy_native.go loads the Rust outbound-proxy kernel (rust/diting-proxy-core) and drives its C
// ABI (that crate's src/ffi.rs).
//
// The kernel owns the SOCKS5 / HTTP CONNECT wire codecs and the proxy config normalization; Go
// keeps every socket, deadline, the status channel and the error wrapping. One symbol carries all
// the operations because they share the same "payload in, payload out" shape (see
// proxy_native_payload.go for the layout).
//
// Unlike the DNS cache kernel this one has no degraded mode: without the library the proxy cannot
// be configured (the config would not be validated) and no handshake can be encoded, so
// `ConfigureOutboundProxy` and every proxied dial report it. Direct traffic never comes here.

package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_proxy_lib_t;
static diting_proxy_lib_t diting_proxy_open(const char* path) { return LoadLibraryA(path); }
static void* diting_proxy_sym(diting_proxy_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_proxy_close(diting_proxy_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_proxy_lib_t;
static diting_proxy_lib_t diting_proxy_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_proxy_sym(diting_proxy_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_proxy_close(diting_proxy_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_proxy_abi_fn)(void);
typedef uint32_t (*diting_proxy_call_fn)(const char*, size_t, char**, size_t*);
typedef void (*diting_proxy_free_fn)(char*, size_t);

static uint32_t diting_proxy_call_abi(void* fn) { return ((diting_proxy_abi_fn)fn)(); }
static uint32_t diting_proxy_call_run(void* fn, const char* request, size_t request_len,
	char** out, size_t* out_len) {
	return ((diting_proxy_call_fn)fn)(request, request_len, out, out_len);
}
static void diting_proxy_call_free(void* fn, char* pointer, size_t length) {
	((diting_proxy_free_fn)fn)(pointer, length);
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

// proxyABIVersion must match `ABI_VERSION` in rust/diting-proxy-core/src/ffi.rs.
const proxyABIVersion = 1

type proxyNativeLib struct {
	lib  C.diting_proxy_lib_t
	call unsafe.Pointer
	free unsafe.Pointer
}

var (
	proxyNativeOnce   sync.Once
	proxyNativeShared *proxyNativeLib
	proxyNativeErr    error
)

func proxyNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_proxy_core.dll"
	case "darwin":
		return "libditing_proxy_core.dylib"
	default:
		return "libditing_proxy_core.so"
	}
}

// proxyNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func proxyNativeCandidates() []string {
	name := proxyNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func loadProxyNative() (*proxyNativeLib, error) {
	abiSymbol := C.CString("diting_proxy_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))
	callSymbol := C.CString("diting_proxy_call")
	defer C.free(unsafe.Pointer(callSymbol))
	freeSymbol := C.CString("diting_proxy_free_bytes")
	defer C.free(unsafe.Pointer(freeSymbol))

	lastErr := fmt.Errorf("library not found in %v", proxyNativeCandidates())
	for _, candidate := range proxyNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_proxy_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_proxy_sym(handle, abiSymbol)
		call := C.diting_proxy_sym(handle, callSymbol)
		free := C.diting_proxy_sym(handle, freeSymbol)
		if abi == nil || call == nil || free == nil {
			C.diting_proxy_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_proxy symbols", candidate)
			continue
		}
		if version := uint32(C.diting_proxy_call_abi(abi)); version != proxyABIVersion {
			C.diting_proxy_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, proxyABIVersion)
			continue
		}
		logf("OutboundProxy: Rust kernel loaded from %s (abi=%d)", candidate, proxyABIVersion)
		return &proxyNativeLib{lib: handle, call: call, free: free}, nil
	}
	return nil, lastErr
}

// proxyKernel returns the loaded library; the failure is kept so the probe runs once per process.
func proxyKernel() (*proxyNativeLib, error) {
	proxyNativeOnce.Do(func() {
		proxyNativeShared, proxyNativeErr = loadProxyNative()
		if proxyNativeErr != nil {
			logf("OutboundProxy: Rust kernel unavailable, the proxy cannot be configured or used: %v",
				proxyNativeErr)
		}
	})
	return proxyNativeShared, proxyNativeErr
}

// proxyCall runs one request payload through the kernel and returns the response payload.
func proxyCall(request []byte) ([]byte, error) {
	lib, err := proxyKernel()
	if err != nil {
		return nil, err
	}
	var requestPointer *C.char
	if len(request) > 0 {
		requestPointer = (*C.char)(unsafe.Pointer(&request[0]))
	}
	var out *C.char
	var outLen C.size_t
	status := C.diting_proxy_call_run(lib.call, requestPointer, C.size_t(len(request)), &out, &outLen)
	if status != 0 {
		return nil, fmt.Errorf("proxy kernel rejected the call (status %d)", status)
	}
	if out == nil || outLen == 0 {
		return nil, fmt.Errorf("proxy kernel returned an empty response")
	}
	response := C.GoBytes(unsafe.Pointer(out), C.int(outLen))
	C.diting_proxy_call_free(lib.free, out, outLen)
	return response, nil
}
