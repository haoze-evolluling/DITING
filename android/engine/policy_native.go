//go:build cgo

// policy_native.go loads the Rust policy kernel (rust/diting-policy-core) and drives it through
// the C ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust owns the rule tables, the wildcard index, the DTRI lookup and the
// seven-level priority walk; Go keeps the snapshot lifecycle, the decision cache, domain
// normalization and - crucially - the exact same walk as its own implementation
// (policy_snapshot.go), which stays in place for three reasons:
//
//   - it is the fallback when the library is missing, stale or has a different ABI;
//   - it is the reference the native path is cross-checked against on every snapshot apply;
//   - it is the oracle the randomized parity test compares against.
//
// The library is optional by design: `go test` on a workstation without a C toolchain simply
// builds the stub (policy_native_stub.go) and everything keeps using Go.
package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_lib_t;
static diting_lib_t diting_lib_open(const char* path) { return LoadLibraryA(path); }
static void* diting_lib_sym(diting_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_lib_close(diting_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_lib_t;
static diting_lib_t diting_lib_open(const char* path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }
static void* diting_lib_sym(diting_lib_t lib, const char* name) { return dlsym(lib, name); }
static void diting_lib_close(diting_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_abi_fn)(void);
typedef void* (*diting_build_fn)(const void*, size_t, uint32_t, char*, size_t);
typedef uint32_t (*diting_flags_fn)(const void*);
typedef int32_t (*diting_evaluate_fn)(const void*, const void*, size_t, const void*, size_t,
	uint32_t, const void**, size_t*);
typedef void (*diting_free_fn)(void*);
typedef size_t (*diting_lower_fn)(const void*, size_t, void*, size_t);

static uint32_t diting_call_abi(void* fn) { return ((diting_abi_fn)fn)(); }
static void* diting_call_build(void* fn, const void* json, size_t len, uint32_t expect_regex,
	char* err, size_t cap) {
	return ((diting_build_fn)fn)(json, len, expect_regex, err, cap);
}
static uint32_t diting_call_flags(void* fn, const void* handle) {
	return ((diting_flags_fn)fn)(handle);
}
static int32_t diting_call_evaluate(void* fn, const void* handle, const void* domain,
	size_t domain_len, const void* app, size_t app_len, uint32_t qtype, const void** reason,
	size_t* reason_len) {
	return ((diting_evaluate_fn)fn)(handle, domain, domain_len, app, app_len, qtype, reason,
		reason_len);
}
static void diting_call_free(void* fn, void* handle) { ((diting_free_fn)fn)(handle); }
static size_t diting_call_lower(void* fn, const void* text, size_t len, void* out, size_t cap) {
	return ((diting_lower_fn)fn)(text, len, out, cap);
}
*/
import "C"

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"
)

// nativePolicyABIVersion must match ABI_VERSION in rust/diting-policy-core/src/ffi.rs.
const nativePolicyABIVersion = 2

const (
	nativeFlagHasRules       = 1 << 0
	nativeFlagAppSensitive   = 1 << 1
	nativeFlagQtypeSensitive = 1 << 2
)

type nativeLib struct {
	lib      C.diting_lib_t
	build    unsafe.Pointer
	flags    unsafe.Pointer
	evaluate unsafe.Pointer
	free     unsafe.Pointer
	lower    unsafe.Pointer
}

var (
	nativeOnce      sync.Once
	nativeShared    *nativeLib
	nativeSharedErr error
)

func nativeLibraryName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_policy_core.dll"
	case "darwin":
		return "libditing_policy_core.dylib"
	default:
		return "libditing_policy_core.so"
	}
}

// nativeLibraryCandidates mirrors the probing the Dart fast paths do: an explicit override, the
// packaged name, then a local `cargo build` output so `go test` works without installing anything.
func nativeLibraryCandidates() []string {
	name := nativeLibraryName()
	candidates := make([]string, 0, 6)
	if override := strings.TrimSpace(os.Getenv("DITING_POLICY_CORE_LIB")); override != "" {
		candidates = append(candidates, override)
	}
	candidates = append(candidates, name)
	for _, profile := range []string{"release", "debug"} {
		path := filepath.Join("..", "..", "rust", "target", profile, name)
		candidates = append(candidates, path)
	}
	return candidates
}

func nativeSymbols(lib *nativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_policy_snapshot_build", &lib.build},
		{"diting_policy_snapshot_flags", &lib.flags},
		{"diting_policy_evaluate", &lib.evaluate},
		{"diting_policy_snapshot_free", &lib.free},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_lib_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return &nativeLoadError{reason: "missing symbol " + entry.name}
		}
		*entry.slot = pointer
	}
	// The lowercase probe is optional: it only backs the parity test.
	name := C.CString("diting_policy_debug_lower")
	lib.lower = C.diting_lib_sym(lib.lib, name)
	C.free(unsafe.Pointer(name))
	return nil
}

type nativeLoadError struct{ reason string }

func (e *nativeLoadError) Error() string { return e.reason }

func loadNativeLibrary() (*nativeLib, error) {
	if strings.EqualFold(strings.TrimSpace(os.Getenv("DITING_POLICY_CORE")), "off") ||
		strings.EqualFold(strings.TrimSpace(os.Getenv("DITING_POLICY_CORE")), "go") {
		return nil, &nativeLoadError{reason: "disabled by DITING_POLICY_CORE"}
	}
	abiName := C.CString("diting_policy_abi_version")
	defer C.free(unsafe.Pointer(abiName))
	var lastErr error = &nativeLoadError{reason: "library not found"}
	for _, candidate := range nativeLibraryCandidates() {
		path := C.CString(candidate)
		handle := C.diting_lib_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_lib_sym(handle, abiName)
		if abi == nil {
			C.diting_lib_close(handle)
			lastErr = &nativeLoadError{reason: candidate + ": missing diting_policy_abi_version"}
			continue
		}
		version := uint32(C.diting_call_abi(abi))
		if version != nativePolicyABIVersion {
			C.diting_lib_close(handle)
			lastErr = &nativeLoadError{reason: candidate + ": ABI mismatch"}
			continue
		}
		lib := &nativeLib{lib: handle}
		if err := nativeSymbols(lib); err != nil {
			C.diting_lib_close(handle)
			lastErr = err
			continue
		}
		logf("policyEngine: Rust policy kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// nativeKernel returns the loaded library, or nil when this process has to stay on the Go engine.
func nativeKernel() *nativeLib {
	nativeOnce.Do(func() {
		nativeShared, nativeSharedErr = loadNativeLibrary()
		if nativeSharedErr != nil {
			logf("policyEngine: Rust policy kernel unavailable (%v); using the Go engine", nativeSharedErr)
		}
	})
	return nativeShared
}

// nativePolicy is one built snapshot. It is safe for concurrent use; `broken` latches a fault so
// later queries take the Go walk instead of paying for another failing call.
type nativePolicy struct {
	lib    *nativeLib
	handle unsafe.Pointer
	flags  uint32
	broken atomic.Bool
	freed  atomic.Bool
	// inflight counts evaluations inside the library so release() never frees a handle a query is
	// still using (the delayed release after a snapshot swap is a heuristic, this makes it exact).
	inflight atomic.Int32
}

func newNativePolicy(jsonSnapshot string, expectRegex int) (*nativePolicy, error) {
	lib := nativeKernel()
	if lib == nil {
		// Already logged once by nativeKernel; wrap the sentinel so a snapshot apply does not
		// repeat the same line on every rule reload.
		return nil, fmt.Errorf("%w: %v", errNativePolicyUnavailable, nativeSharedErr)
	}
	var errBuf [256]byte
	handle := C.diting_call_build(
		lib.build,
		unsafe.Pointer(unsafe.StringData(jsonSnapshot)),
		C.size_t(len(jsonSnapshot)),
		C.uint32_t(expectRegex),
		(*C.char)(unsafe.Pointer(&errBuf[0])),
		C.size_t(len(errBuf)),
	)
	if handle == nil {
		message := C.GoString((*C.char)(unsafe.Pointer(&errBuf[0])))
		if message == "" {
			message = "snapshot build failed"
		}
		return nil, &nativeLoadError{reason: message}
	}
	policy := &nativePolicy{
		lib:    lib,
		handle: handle,
		flags:  uint32(C.diting_call_flags(lib.flags, handle)),
	}
	return policy, nil
}

// evaluate runs the native walk. `ok == false` means "this snapshot's native path is gone", and
// the caller has to use the Go walk.
//
// The reason string stays owned by the Rust snapshot: the library only hands back a pointer and a
// length, so a query costs one FFI round trip and allocates nothing unless a rule matched.
func (p *nativePolicy) evaluate(domain, appName string, qtype uint16) (blocked bool, reason string, ok bool) {
	if p == nil || p.freed.Load() || p.broken.Load() {
		return false, "", false
	}
	p.inflight.Add(1)
	defer p.inflight.Add(-1)

	var reasonPtr unsafe.Pointer
	reasonLen := C.size_t(0)
	code := C.diting_call_evaluate(
		p.lib.evaluate,
		p.handle,
		unsafe.Pointer(unsafe.StringData(domain)),
		C.size_t(len(domain)),
		unsafe.Pointer(unsafe.StringData(appName)),
		C.size_t(len(appName)),
		C.uint32_t(qtype),
		&reasonPtr,
		&reasonLen,
	)
	switch code {
	case 0, 1:
	default:
		p.broken.Store(true)
		logf("policyEngine: Rust policy kernel evaluate failed (code=%d); falling back to Go", int32(code))
		return false, "", false
	}
	if reasonPtr == nil || reasonLen == 0 {
		return code == 1, "", true
	}
	// Copy before returning: the bytes belong to the snapshot, which this call keeps alive.
	return code == 1, string(unsafe.Slice((*byte)(reasonPtr), int(reasonLen))), true
}

// release frees the handle once; repeated or late calls are no-ops.
//
// It waits for in-flight evaluations to leave the library first: a cgo call is not preemptible, so
// a query can outlive the two-second grace period the snapshot swap relies on.
func (p *nativePolicy) release() {
	if p == nil || p.freed.Swap(true) {
		return
	}
	for deadline := time.Now().Add(time.Second); p.inflight.Load() != 0; {
		if time.Now().After(deadline) {
			logf("policyEngine: releasing a Rust snapshot with evaluations still running")
			break
		}
		runtime.Gosched()
	}
	C.diting_call_free(p.lib.free, p.handle)
}

// nativeLower probes the Rust `strings.ToLower` port from the parity test.
func nativeLower(text string) (string, bool) {
	lib := nativeKernel()
	if lib == nil || lib.lower == nil {
		return "", false
	}
	var inline [256]byte
	length := int(C.diting_call_lower(
		lib.lower,
		unsafe.Pointer(unsafe.StringData(text)),
		C.size_t(len(text)),
		unsafe.Pointer(&inline[0]),
		C.size_t(len(inline)),
	))
	if length == -1 {
		return "", false
	}
	if length <= len(inline) {
		return string(inline[:length]), true
	}
	buffer := make([]byte, length)
	C.diting_call_lower(
		lib.lower,
		unsafe.Pointer(unsafe.StringData(text)),
		C.size_t(len(text)),
		unsafe.Pointer(&buffer[0]),
		C.size_t(len(buffer)),
	)
	return string(buffer[:length]), true
}
