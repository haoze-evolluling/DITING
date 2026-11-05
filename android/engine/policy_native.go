//go:build cgo

// policy_native.go loads the Rust policy kernel (rust/diting-policy-core) and drives it through
// the C ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust owns the rule tables, the wildcard index, the DTRI lookup, the
// seven-level priority walk, domain normalization and the decision cache; Go keeps the snapshot
// lifecycle and the network stack. A query is one call into the library, cache hit or not.
//
// The kernel is required. A missing library, a stale ABI or a rejected payload fails
// ApplyRuleSnapshot, which fails the engine start: there is no second walk to fall back to, and a
// silent one would only hide the difference until it changed an answer.
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
typedef void* (*diting_build_fn)(const void*, size_t, char*, size_t);
typedef uint32_t (*diting_flags_fn)(const void*);
typedef int32_t (*diting_evaluate_fn)(const void*, const void*, size_t, const void*, size_t,
	uint32_t, const void**, size_t*);
typedef void (*diting_prewarm_fn)(const void*, const void*);
typedef void (*diting_free_fn)(void*);

static uint32_t diting_call_abi(void* fn) { return ((diting_abi_fn)fn)(); }
static void* diting_call_build(void* fn, const void* json, size_t len, char* err, size_t cap) {
	return ((diting_build_fn)fn)(json, len, err, cap);
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
static void diting_call_prewarm(void* fn, const void* handle, const void* previous) {
	((diting_prewarm_fn)fn)(handle, previous);
}
static void diting_call_free(void* fn, void* handle) { ((diting_free_fn)fn)(handle); }
*/
import "C"

import (
	"fmt"
	"path/filepath"
	"runtime"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"
)

// nativePolicyABIVersion must match `ABI_VERSION` in rust/diting-policy-core/src/ffi.rs.
const nativePolicyABIVersion = 4

// Snapshot shape bits reported by `diting_policy_snapshot_flags`.
const (
	nativeFlagHasRules       = 1 << 0
	nativeFlagAppSensitive   = 1 << 1
	nativeFlagQtypeSensitive = 1 << 2
)

type nativeLib struct {
	lib              C.diting_lib_t
	build            unsafe.Pointer
	flags            unsafe.Pointer
	evaluate         unsafe.Pointer
	evaluateUncached unsafe.Pointer
	prewarm          unsafe.Pointer
	free             unsafe.Pointer
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

// nativeLibraryCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func nativeLibraryCandidates() []string {
	name := nativeLibraryName()
	candidates := []string{name}
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
		{"diting_policy_evaluate_uncached", &lib.evaluateUncached},
		{"diting_policy_prewarm", &lib.prewarm},
		{"diting_policy_snapshot_free", &lib.free},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_lib_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadNativeLibrary() (*nativeLib, error) {
	abiName := C.CString("diting_policy_abi_version")
	defer C.free(unsafe.Pointer(abiName))
	lastErr := fmt.Errorf("library not found in %v", nativeLibraryCandidates())
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
			lastErr = fmt.Errorf("%s: missing diting_policy_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_call_abi(abi))
		if version != nativePolicyABIVersion {
			C.diting_lib_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, nativePolicyABIVersion)
			continue
		}
		lib := &nativeLib{lib: handle}
		if err := nativeSymbols(lib); err != nil {
			C.diting_lib_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		logf("policyEngine: Rust policy kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// nativeKernel returns the loaded library; the failure is kept so every snapshot apply reports the
// same reason instead of retrying the probe.
func nativeKernel() (*nativeLib, error) {
	nativeOnce.Do(func() {
		nativeShared, nativeSharedErr = loadNativeLibrary()
	})
	if nativeSharedErr != nil {
		return nil, nativeSharedErr
	}
	return nativeShared, nil
}

// nativePolicy is one built snapshot. It is safe for concurrent use.
type nativePolicy struct {
	lib    *nativeLib
	handle unsafe.Pointer
	// flags carry hasRules/appSensitive/qtypeSensitive, read once by policySnapshot.
	flags  uint32
	freed  atomic.Bool
	// inflight counts evaluations inside the library so release() never frees a handle a query is
	// still using (the delayed release after a snapshot swap is a heuristic, this makes it exact).
	inflight atomic.Int32
}

func newNativePolicy(jsonSnapshot string) (*nativePolicy, error) {
	lib, err := nativeKernel()
	if err != nil {
		return nil, fmt.Errorf("load rust policy kernel: %w", err)
	}
	var errBuf [256]byte
	handle := C.diting_call_build(
		lib.build,
		unsafe.Pointer(unsafe.StringData(jsonSnapshot)),
		C.size_t(len(jsonSnapshot)),
		(*C.char)(unsafe.Pointer(&errBuf[0])),
		C.size_t(len(errBuf)),
	)
	if handle == nil {
		message := C.GoString((*C.char)(unsafe.Pointer(&errBuf[0])))
		if message == "" {
			message = "snapshot build failed"
		}
		return nil, fmt.Errorf("build rust policy snapshot: %s", message)
	}
	policy := &nativePolicy{
		lib:    lib,
		handle: handle,
		flags:  uint32(C.diting_call_flags(lib.flags, handle)),
	}
	return policy, nil
}

// evaluate answers one query: the kernel normalizes the domain and the app name, checks the
// decision cache and only walks the rules on a miss. An error code is logged and reported as "no
// match": the kernel only rejects input it cannot decode as UTF-8.
//
// The reason string stays owned by the Rust snapshot: the library only hands back a pointer and a
// length, so a query costs one FFI round trip and allocates nothing unless a rule matched.
func (p *nativePolicy) evaluate(domain, appName string, qtype uint16) (blocked bool, reason string) {
	if p == nil {
		return false, ""
	}
	return p.ask(p.lib.evaluate, domain, appName, qtype)
}

// evaluateUncached is the same walk and normalization without the decision cache. The tests and
// benchmarks use it to prove that a cache hit never changes an answer.
func (p *nativePolicy) evaluateUncached(domain, appName string, qtype uint16) (bool, string) {
	if p == nil {
		return false, ""
	}
	return p.ask(p.lib.evaluateUncached, domain, appName, qtype)
}

func (p *nativePolicy) ask(symbol unsafe.Pointer, domain, appName string, qtype uint16) (blocked bool, reason string) {
	if p == nil || p.freed.Load() {
		return false, ""
	}
	p.pin()
	defer p.unpin()

	var reasonPtr unsafe.Pointer
	reasonLen := C.size_t(0)
	code := C.diting_call_evaluate(
		symbol,
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
		logf("policyEngine: Rust policy kernel evaluate failed (code=%d)", int32(code))
		return false, ""
	}
	if reasonPtr == nil || reasonLen == 0 {
		return code == 1, ""
	}
	// Copy before returning: the bytes belong to the snapshot, which this call keeps alive.
	return code == 1, string(unsafe.Slice((*byte)(reasonPtr), int(reasonLen)))
}

// prewarm re-evaluates prev's hottest cached keys against p. The kernel decides whether the two
// snapshots can share keys. The caller pins both handles before scheduling this on a goroutine, so
// a delayed call cannot arrive after release() has already freed the previous snapshot.
func (p *nativePolicy) prewarm(prev *nativePolicy) {
	if p == nil || prev == nil || p.freed.Load() || prev.freed.Load() {
		return
	}
	C.diting_call_prewarm(p.lib.prewarm, p.handle, prev.handle)
}

// pin marks a call as in-flight. release() waits for in-flight calls to leave the library first: a
// cgo call is not preemptible, so a query can outlive the two-second grace period the snapshot swap
// relies on.
func (p *nativePolicy) pin() {
	if p != nil {
		p.inflight.Add(1)
	}
}

func (p *nativePolicy) unpin() {
	if p != nil {
		p.inflight.Add(-1)
	}
}

// release frees the handle once; repeated or late calls are no-ops.
//
// It waits for in-flight calls (queries and prewarming) to leave the library first.
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
