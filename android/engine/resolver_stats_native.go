//go:build cgo

// resolver_stats_native.go loads the Rust provider statistics kernel (rust/diting-resolver-core)
// and drives its C ABI (that crate's src/ffi.rs).
//
// The kernel owns one upstream's SRTT/RTTVAR estimator, the EWMA failure ratio, the decayed
// consecutive-failure penalty, the circuit breaker and the three adaptive delays. Go keeps the
// handle lifecycle and the time conversions; every call passes unix nanoseconds, so the kernel
// never reads a clock.
//
// The kernel is optional in the sense that a missing library only degrades scheduling: every
// provider behaves "cold" (default score, cold delays, every attempt allowed), which is exactly
// what a provider without statistics looked like before this model existed. It never changes an
// answer.
package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_resolver_lib_t;
static diting_resolver_lib_t diting_resolver_open(const char* path) { return LoadLibraryA(path); }
static void* diting_resolver_sym(diting_resolver_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_resolver_close(diting_resolver_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_resolver_lib_t;
static diting_resolver_lib_t diting_resolver_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_resolver_sym(diting_resolver_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_resolver_close(diting_resolver_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_resolver_abi_fn)(void);
typedef void* (*diting_resolver_new_fn)(void);
typedef void (*diting_resolver_handle_fn)(void*);
typedef uint32_t (*diting_resolver_success_fn)(void*, int64_t, int64_t);
typedef uint32_t (*diting_resolver_failure_fn)(void*, uint32_t, int64_t);
typedef uint32_t (*diting_resolver_now_fn)(void*, int64_t);
typedef int64_t (*diting_resolver_score_fn)(void*, int64_t);
typedef int64_t (*diting_resolver_delay_fn)(void*);
typedef uint32_t (*diting_resolver_count_fn)(void*);

static uint32_t diting_resolver_call_abi(void* fn) { return ((diting_resolver_abi_fn)fn)(); }
static void* diting_resolver_call_new(void* fn) { return ((diting_resolver_new_fn)fn)(); }
static void diting_resolver_call_handle(void* fn, void* handle) {
	((diting_resolver_handle_fn)fn)(handle);
}
static uint32_t diting_resolver_call_success(void* fn, void* handle, int64_t rtt_ns,
	int64_t now_ns) {
	return ((diting_resolver_success_fn)fn)(handle, rtt_ns, now_ns);
}
static uint32_t diting_resolver_call_failure(void* fn, void* handle, uint32_t weight,
	int64_t now_ns) {
	return ((diting_resolver_failure_fn)fn)(handle, weight, now_ns);
}
// The "handle + one i64 + u32" calls: policy failure and allow_attempt pass now_ns,
// record_censored passes the loser's elapsed time.
static uint32_t diting_resolver_call_time(void* fn, void* handle, int64_t value) {
	return ((diting_resolver_now_fn)fn)(handle, value);
}
static int64_t diting_resolver_call_score(void* fn, void* handle, int64_t now_ns) {
	return ((diting_resolver_score_fn)fn)(handle, now_ns);
}
static int64_t diting_resolver_call_reading(void* fn, void* handle) {
	return ((diting_resolver_delay_fn)fn)(handle);
}
static uint32_t diting_resolver_call_count(void* fn, void* handle) {
	return ((diting_resolver_count_fn)fn)(handle);
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

// resolverStatsABIVersion must match `ABI_VERSION` in rust/diting-resolver-core/src/ffi.rs.
const resolverStatsABIVersion = 1

type resolverStatsNativeLib struct {
	lib  C.diting_resolver_lib_t
	new  unsafe.Pointer
	free unsafe.Pointer

	recordSuccess       unsafe.Pointer
	recordFailure       unsafe.Pointer
	recordPolicyFailure unsafe.Pointer
	allowAttempt        unsafe.Pointer
	recordCensored      unsafe.Pointer
	score               unsafe.Pointer
	hedgeDelay          unsafe.Pointer
	attemptTimeout      unsafe.Pointer
	udpRetryDelay       unsafe.Pointer
	sampleCount         unsafe.Pointer
	failureCount        unsafe.Pointer
}

var (
	resolverStatsNativeOnce   sync.Once
	resolverStatsNativeShared *resolverStatsNativeLib
	resolverStatsNativeErr    error
)

func resolverStatsNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_resolver_core.dll"
	case "darwin":
		return "libditing_resolver_core.dylib"
	default:
		return "libditing_resolver_core.so"
	}
}

// resolverStatsNativeCandidates probes the packaged name first, then a local `cargo build` output
// so `go test` works without installing anything.
func resolverStatsNativeCandidates() []string {
	name := resolverStatsNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func resolverStatsNativeSymbols(lib *resolverStatsNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_resolver_new", &lib.new},
		{"diting_resolver_free", &lib.free},
		{"diting_resolver_record_success", &lib.recordSuccess},
		{"diting_resolver_record_failure", &lib.recordFailure},
		{"diting_resolver_record_policy_failure", &lib.recordPolicyFailure},
		{"diting_resolver_allow_attempt", &lib.allowAttempt},
		{"diting_resolver_record_censored", &lib.recordCensored},
		{"diting_resolver_score", &lib.score},
		{"diting_resolver_hedge_delay", &lib.hedgeDelay},
		{"diting_resolver_attempt_timeout", &lib.attemptTimeout},
		{"diting_resolver_udp_retry_delay", &lib.udpRetryDelay},
		{"diting_resolver_sample_count", &lib.sampleCount},
		{"diting_resolver_failure_count", &lib.failureCount},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_resolver_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadResolverStatsNative() (*resolverStatsNativeLib, error) {
	abiSymbol := C.CString("diting_resolver_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", resolverStatsNativeCandidates())
	for _, candidate := range resolverStatsNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_resolver_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_resolver_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_resolver_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_resolver_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_resolver_call_abi(abi))
		if version != resolverStatsABIVersion {
			C.diting_resolver_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, resolverStatsABIVersion)
			continue
		}
		lib := &resolverStatsNativeLib{lib: handle}
		if err := resolverStatsNativeSymbols(lib); err != nil {
			C.diting_resolver_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		logf("Resolver stats: Rust kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// resolverStatsKernel returns the loaded library; the failure is kept so the probe runs once per
// process.
func resolverStatsKernel() (*resolverStatsNativeLib, error) {
	resolverStatsNativeOnce.Do(func() {
		resolverStatsNativeShared, resolverStatsNativeErr = loadResolverStatsNative()
		if resolverStatsNativeErr != nil {
			logf("Resolver stats: Rust kernel unavailable, scheduling uses cold values: %v",
				resolverStatsNativeErr)
		}
	})
	return resolverStatsNativeShared, resolverStatsNativeErr
}

// nativeProviderStats owns one kernel handle.
type nativeProviderStats struct {
	lib     *resolverStatsNativeLib
	pointer unsafe.Pointer
}

func newNativeProviderStats() (*nativeProviderStats, error) {
	lib, err := resolverStatsKernel()
	if err != nil {
		return nil, err
	}
	pointer := C.diting_resolver_call_new(lib.new)
	if pointer == nil {
		return nil, errors.New("resolver stats kernel returned a null handle")
	}
	return &nativeProviderStats{lib: lib, pointer: pointer}, nil
}

func (h *nativeProviderStats) recordSuccess(rttNs, nowNs int64) {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_resolver_call_success(h.lib.recordSuccess, h.pointer, C.int64_t(rttNs), C.int64_t(nowNs))
}

func (h *nativeProviderStats) recordFailure(weight uint32, nowNs int64) {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_resolver_call_failure(h.lib.recordFailure, h.pointer, C.uint32_t(weight), C.int64_t(nowNs))
}

func (h *nativeProviderStats) recordPolicyFailure(nowNs int64) {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_resolver_call_time(h.lib.recordPolicyFailure, h.pointer, C.int64_t(nowNs))
}

func (h *nativeProviderStats) allowAttempt(nowNs int64) bool {
	if h == nil || h.pointer == nil {
		return true
	}
	return C.diting_resolver_call_time(h.lib.allowAttempt, h.pointer, C.int64_t(nowNs)) == 1
}

func (h *nativeProviderStats) recordCensored(elapsedNs int64) {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_resolver_call_time(h.lib.recordCensored, h.pointer, C.int64_t(elapsedNs))
}

func (h *nativeProviderStats) score(nowNs int64) int64 {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int64(C.diting_resolver_call_score(h.lib.score, h.pointer, C.int64_t(nowNs)))
}

func (h *nativeProviderStats) hedgeDelay() int64 {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int64(C.diting_resolver_call_reading(h.lib.hedgeDelay, h.pointer))
}

func (h *nativeProviderStats) attemptTimeout() int64 {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int64(C.diting_resolver_call_reading(h.lib.attemptTimeout, h.pointer))
}

func (h *nativeProviderStats) udpRetryDelay() int64 {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int64(C.diting_resolver_call_reading(h.lib.udpRetryDelay, h.pointer))
}

func (h *nativeProviderStats) sampleCount() int64 {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int64(C.diting_resolver_call_reading(h.lib.sampleCount, h.pointer))
}

func (h *nativeProviderStats) failureCount() uint32 {
	if h == nil || h.pointer == nil {
		return 0
	}
	return uint32(C.diting_resolver_call_count(h.lib.failureCount, h.pointer))
}

func (h *nativeProviderStats) free() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_resolver_call_handle(h.lib.free, h.pointer)
	h.pointer = nil
}
