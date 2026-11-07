//go:build cgo

// request_native.go loads the Rust request filter (rust/diting-request-core) and drives its C ABI
// (that crate's src/ffi.rs).
//
// The kernel owns the rule table (trim, lower-case, the `block` / `allow` whitelist, the mandatory
// `http(s)://` prefix) and the per-request decision (host fold, default-port strip, `path == ""`,
// the `scheme://host path` URL build, the longest-prefix walk with allow winning ties, and the host
// the domain-rule fallback should be asked about). Go keeps `encoding/json`, `net/http`, the domain
// fallback and the log lines.
//
// The kernel holds one immutable rule set per handle, because this filter runs for every plaintext
// HTTP request: a settings change builds a new handle and closes the old one (under the engine lock,
// so a request in flight never sees a freed handle). A missing library means no request rule ever
// matches: the domain-rule fallback still decides, and the raw host is used for it.

package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_request_lib_t;
static diting_request_lib_t diting_request_open(const char* path) { return LoadLibraryA(path); }
static void* diting_request_sym(diting_request_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_request_close_lib(diting_request_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_request_lib_t;
static diting_request_lib_t diting_request_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_request_sym(diting_request_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_request_close_lib(diting_request_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_request_abi_fn)(void);
typedef uint32_t (*diting_request_new_fn)(const char*, size_t, void**);
typedef uint32_t (*diting_request_match_fn)(const void*, const char*, size_t, char**, size_t*);
typedef void (*diting_request_close_fn)(void*);
typedef void (*diting_request_free_fn)(char*, size_t);

static uint32_t diting_request_call_abi(void* fn) { return ((diting_request_abi_fn)fn)(); }
static uint32_t diting_request_call_new(void* fn, const char* rules, size_t rules_len,
	void** handle) {
	return ((diting_request_new_fn)fn)(rules, rules_len, handle);
}
static uint32_t diting_request_call_match(void* fn, const void* handle, const char* request,
	size_t request_len, char** out, size_t* out_len) {
	return ((diting_request_match_fn)fn)(handle, request, request_len, out, out_len);
}
static void diting_request_call_close(void* fn, void* handle) {
	((diting_request_close_fn)fn)(handle);
}
static void diting_request_call_free(void* fn, char* pointer, size_t length) {
	((diting_request_free_fn)fn)(pointer, length);
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

// requestABIVersion must match `ABI_VERSION` in rust/diting-request-core/src/ffi.rs.
const requestABIVersion = 1

// errRequestKernelMissing is reported when the kernel library is absent.
var errRequestKernelMissing = errors.New("Rust request kernel is unavailable")

// Kernel status codes (the crate's `ffi` constants).
const (
	requestStatusOK         = 0
	requestStatusBadArg     = 1
	requestStatusBadPayload = 2
	requestStatusPanic      = 3
)

type requestNativeLib struct {
	lib    C.diting_request_lib_t
	newSet unsafe.Pointer
	match  unsafe.Pointer
	close  unsafe.Pointer
	free   unsafe.Pointer
}

var (
	requestNativeOnce   sync.Once
	requestNativeShared *requestNativeLib
	requestNativeErr    error
)

func requestNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_request_core.dll"
	case "darwin":
		return "libditing_request_core.dylib"
	default:
		return "libditing_request_core.so"
	}
}

// requestNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func requestNativeCandidates() []string {
	name := requestNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func loadRequestNative() (*requestNativeLib, error) {
	abiSymbol := C.CString("diting_request_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", requestNativeCandidates())
	for _, candidate := range requestNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_request_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_request_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_request_close_lib(handle)
			lastErr = fmt.Errorf("%s: missing diting_request_abi_version", candidate)
			continue
		}
		if version := uint32(C.diting_request_call_abi(abi)); version != requestABIVersion {
			C.diting_request_close_lib(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, requestABIVersion)
			continue
		}
		lib := &requestNativeLib{lib: handle}
		slots := []struct {
			name string
			slot *unsafe.Pointer
		}{
			{"diting_request_new", &lib.newSet},
			{"diting_request_match", &lib.match},
			{"diting_request_close", &lib.close},
			{"diting_request_free_bytes", &lib.free},
		}
		missing := ""
		for _, entry := range slots {
			name := C.CString(entry.name)
			pointer := C.diting_request_sym(handle, name)
			C.free(unsafe.Pointer(name))
			if pointer == nil {
				missing = entry.name
				break
			}
			*entry.slot = pointer
		}
		if missing != "" {
			C.diting_request_close_lib(handle)
			lastErr = fmt.Errorf("%s: missing symbol %s", candidate, missing)
			continue
		}
		logf("RequestFilter: Rust kernel loaded from %s (abi=%d)", candidate, requestABIVersion)
		return lib, nil
	}
	return nil, lastErr
}

// requestKernel returns the loaded library; the failure is kept so the probe runs once per process.
func requestKernel() (*requestNativeLib, error) {
	requestNativeOnce.Do(func() {
		requestNativeShared, requestNativeErr = loadRequestNative()
		if requestNativeErr != nil {
			logf("RequestFilter: Rust kernel unavailable, URL rules are inactive: %v",
				requestNativeErr)
		}
	})
	return requestNativeShared, requestNativeErr
}

// nativeRequestRules owns one kernel handle.
type nativeRequestRules struct {
	lib     *requestNativeLib
	pointer unsafe.Pointer
}

// newNativeRequestRules normalizes the rules and returns a handle for them.
func newNativeRequestRules(rules []requestRule) (*nativeRequestRules, error) {
	lib, err := requestKernel()
	if err != nil {
		return nil, err
	}
	payload := encodeRequestRules(rules)
	var requestPointer *C.char
	if len(payload) > 0 {
		requestPointer = (*C.char)(unsafe.Pointer(&payload[0]))
	}
	var handle unsafe.Pointer
	status := uint32(C.diting_request_call_new(lib.newSet, requestPointer, C.size_t(len(payload)),
		&handle))
	if status != requestStatusOK || handle == nil {
		return nil, fmt.Errorf("request kernel rejected the rule set (status %d)", status)
	}
	return &nativeRequestRules{lib: lib, pointer: handle}, nil
}

// match decides one request.
func (r *nativeRequestRules) match(scheme, host, path string) (requestDecision, error) {
	if r == nil || r.pointer == nil {
		return requestDecision{}, errRequestKernelMissing
	}
	payload := encodeRequestMatch(scheme, host, path)
	var requestPointer *C.char
	if len(payload) > 0 {
		requestPointer = (*C.char)(unsafe.Pointer(&payload[0]))
	}
	var out *C.char
	var outLen C.size_t
	status := uint32(C.diting_request_call_match(r.lib.match, r.pointer, requestPointer,
		C.size_t(len(payload)), &out, &outLen))
	if status != requestStatusOK {
		return requestDecision{}, fmt.Errorf("request kernel rejected the match (status %d)", status)
	}
	if out == nil || outLen == 0 {
		return requestDecision{}, fmt.Errorf("request kernel returned an empty decision")
	}
	response := C.GoBytes(unsafe.Pointer(out), C.int(outLen))
	C.diting_request_call_free(r.lib.free, out, outLen)
	decision, ok := decodeRequestDecision(response)
	if !ok {
		return requestDecision{}, fmt.Errorf("request kernel returned a malformed decision")
	}
	return decision, nil
}

func (r *nativeRequestRules) release() {
	if r == nil || r.pointer == nil {
		return
	}
	C.diting_request_call_close(r.lib.close, r.pointer)
	r.pointer = nil
}
