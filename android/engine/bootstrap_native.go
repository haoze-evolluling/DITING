//go:build cgo

// bootstrap_native.go loads the Rust bootstrap scoring kernel (rust/diting-bootstrap-core) and
// drives its C ABI (that crate's src/ffi.rs).
//
// Responsibility split: the kernel owns the per-endpoint health model (half-life decay, EWMA
// latency, jitter, consecutive-failure penalty, cooldown), the weighted primary pick with its
// exploration rate, the fallback order and the one-minute host cache. Go keeps the JSON config,
// the UDP query itself, the logging callback and the `net.IP` fast path.
//
// Randomness is injected: Go passes two `rand.Float64()` rolls and one `rand.Uint64()` index roll,
// so the kernel never owns a random source. The index roll is reduced modulo the candidate count
// (Go used `rand.Intn`; the difference is modulo bias below 2^-40), which the distribution test
// covers.
//
// The kernel needs every timestamp: all calls take unix nanoseconds and the kernel never reads a
// clock, so a trace can be replayed. If the library is missing or has a stale ABI the resolver
// treats bootstrap as disabled (callers dial the provider hostname through the normal path), which
// is the same shape as a resolver configured without bootstrap servers. It never changes an answer.
package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_bootstrap_lib_t;
static diting_bootstrap_lib_t diting_bootstrap_open(const char* path) { return LoadLibraryA(path); }
static void* diting_bootstrap_sym(diting_bootstrap_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_bootstrap_close(diting_bootstrap_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_bootstrap_lib_t;
static diting_bootstrap_lib_t diting_bootstrap_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_bootstrap_sym(diting_bootstrap_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_bootstrap_close(diting_bootstrap_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_bootstrap_abi_fn)(void);
typedef void* (*diting_bootstrap_new_fn)(void);
typedef void (*diting_bootstrap_handle_fn)(void*);
typedef uint32_t (*diting_bootstrap_status_fn)(void*);
typedef uint32_t (*diting_bootstrap_record_fn)(void*, const char*, size_t, uint32_t, int64_t,
	int64_t);
typedef intptr_t (*diting_bootstrap_score_fn)(void*, const char*, size_t, double, int64_t,
	void*, size_t);
typedef intptr_t (*diting_bootstrap_plan_fn)(void*, int64_t, double, double, uint64_t,
	const void*, size_t, void*, size_t);
typedef intptr_t (*diting_bootstrap_cache_get_fn)(void*, const char*, size_t, int64_t,
	void*, size_t);
typedef uint32_t (*diting_bootstrap_cache_put_fn)(void*, const char*, size_t, const char*, size_t,
	int64_t);
typedef uint32_t (*diting_bootstrap_count_fn)(void*);

static uint32_t diting_bootstrap_call_abi(void* fn) { return ((diting_bootstrap_abi_fn)fn)(); }
static void* diting_bootstrap_call_new(void* fn) { return ((diting_bootstrap_new_fn)fn)(); }
static void diting_bootstrap_call_handle(void* fn, void* handle) {
	((diting_bootstrap_handle_fn)fn)(handle);
}
static uint32_t diting_bootstrap_call_status(void* fn, void* handle) {
	return ((diting_bootstrap_status_fn)fn)(handle);
}
static uint32_t diting_bootstrap_call_record(void* fn, void* handle, const char* id,
	size_t id_len, uint32_t success, int64_t elapsed_ms, int64_t now_ns) {
	return ((diting_bootstrap_record_fn)fn)(handle, id, id_len, success, elapsed_ms, now_ns);
}
static intptr_t diting_bootstrap_call_score(void* fn, void* handle, const char* id, size_t id_len,
	double entry_weight, int64_t now_ns, void* out, size_t out_cap) {
	return ((diting_bootstrap_score_fn)fn)(handle, id, id_len, entry_weight, now_ns, out, out_cap);
}
static intptr_t diting_bootstrap_call_plan(void* fn, void* handle, int64_t now_ns,
	double explore_roll, double weight_roll, uint64_t index_roll, const void* entries,
	size_t entries_len, void* out, size_t out_cap) {
	return ((diting_bootstrap_plan_fn)fn)(handle, now_ns, explore_roll, weight_roll, index_roll,
		entries, entries_len, out, out_cap);
}
static intptr_t diting_bootstrap_call_cache_get(void* fn, void* handle, const char* host,
	size_t host_len, int64_t now_ns, void* out, size_t out_cap) {
	return ((diting_bootstrap_cache_get_fn)fn)(handle, host, host_len, now_ns, out, out_cap);
}
static uint32_t diting_bootstrap_call_cache_put(void* fn, void* handle, const char* host,
	size_t host_len, const char* ip, size_t ip_len, int64_t now_ns) {
	return ((diting_bootstrap_cache_put_fn)fn)(handle, host, host_len, ip, ip_len, now_ns);
}
static uint32_t diting_bootstrap_call_count(void* fn, void* handle) {
	return ((diting_bootstrap_count_fn)fn)(handle);
}
*/
import "C"

import (
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"
)

// bootstrapABIVersion must match `ABI_VERSION` in rust/diting-bootstrap-core/src/ffi.rs.
const bootstrapABIVersion = 1

// bootstrapPayloadLayoutVersion must match `LAYOUT_VERSION` in the kernel's payload.rs.
const bootstrapPayloadLayoutVersion = 1

// bootstrapMaxAddressBytes bounds one cached address text (`net.IP.String()` is at most 45).
const bootstrapMaxAddressBytes = 64

type bootstrapNativeLib struct {
	lib C.diting_bootstrap_lib_t

	new         unsafe.Pointer
	free        unsafe.Pointer
	reset       unsafe.Pointer
	clearCache  unsafe.Pointer
	record      unsafe.Pointer
	score       unsafe.Pointer
	plan        unsafe.Pointer
	cacheGet    unsafe.Pointer
	cachePut    unsafe.Pointer
	healthCount unsafe.Pointer
}

var (
	bootstrapNativeOnce   sync.Once
	bootstrapNativeShared *bootstrapNativeLib
	bootstrapNativeErr    error
)

func bootstrapNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_bootstrap_core.dll"
	case "darwin":
		return "libditing_bootstrap_core.dylib"
	default:
		return "libditing_bootstrap_core.so"
	}
}

// bootstrapNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func bootstrapNativeCandidates() []string {
	name := bootstrapNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func bootstrapNativeSymbols(lib *bootstrapNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_bootstrap_new", &lib.new},
		{"diting_bootstrap_free", &lib.free},
		{"diting_bootstrap_reset", &lib.reset},
		{"diting_bootstrap_clear_cache", &lib.clearCache},
		{"diting_bootstrap_record_result", &lib.record},
		{"diting_bootstrap_score", &lib.score},
		{"diting_bootstrap_plan", &lib.plan},
		{"diting_bootstrap_cache_get", &lib.cacheGet},
		{"diting_bootstrap_cache_put", &lib.cachePut},
		{"diting_bootstrap_health_count", &lib.healthCount},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_bootstrap_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadBootstrapNative() (*bootstrapNativeLib, error) {
	abiSymbol := C.CString("diting_bootstrap_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", bootstrapNativeCandidates())
	for _, candidate := range bootstrapNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_bootstrap_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_bootstrap_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_bootstrap_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_bootstrap_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_bootstrap_call_abi(abi))
		if version != bootstrapABIVersion {
			C.diting_bootstrap_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, bootstrapABIVersion)
			continue
		}
		lib := &bootstrapNativeLib{lib: handle}
		if err := bootstrapNativeSymbols(lib); err != nil {
			C.diting_bootstrap_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		logf("Bootstrap: Rust kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// bootstrapKernel returns the loaded library; the failure is kept so the probe runs once per
// process.
func bootstrapKernel() (*bootstrapNativeLib, error) {
	bootstrapNativeOnce.Do(func() {
		bootstrapNativeShared, bootstrapNativeErr = loadBootstrapNative()
		if bootstrapNativeErr != nil {
			logf("Bootstrap: Rust kernel unavailable, bootstrap resolution is disabled: %v",
				bootstrapNativeErr)
		}
	})
	return bootstrapNativeShared, bootstrapNativeErr
}

// nativeBootstrap owns one resolver's kernel handle.
type nativeBootstrap struct {
	lib     *bootstrapNativeLib
	pointer unsafe.Pointer
}

func newNativeBootstrap() (*nativeBootstrap, error) {
	lib, err := bootstrapKernel()
	if err != nil {
		return nil, err
	}
	pointer := C.diting_bootstrap_call_new(lib.new)
	if pointer == nil {
		return nil, errors.New("bootstrap kernel returned a null handle")
	}
	return &nativeBootstrap{lib: lib, pointer: pointer}, nil
}

// bootstrapText hands a Go string to the kernel. The kernel never keeps the pointer. An empty
// string becomes a null pointer with length 0, which the kernel reads as an empty id.
func bootstrapText(value string) (unsafe.Pointer, C.size_t) {
	if value == "" {
		return nil, 0
	}
	return unsafe.Pointer(unsafe.StringData(value)), C.size_t(len(value))
}

func (h *nativeBootstrap) recordResult(id string, success bool, elapsedMs, nowNs int64) {
	if h == nil || h.pointer == nil {
		return
	}
	text, length := bootstrapText(id)
	flag := C.uint32_t(0)
	if success {
		flag = 1
	}
	C.diting_bootstrap_call_record(h.lib.record, h.pointer, (*C.char)(text), length, flag,
		C.int64_t(elapsedMs), C.int64_t(nowNs))
}

// score returns the endpoint's weight, cooldown flag and decayed sample count.
func (h *nativeBootstrap) score(id string, entryWeight float64, nowNs int64) (float64, bool, float64, bool) {
	if h == nil || h.pointer == nil {
		return 0, false, 0, false
	}
	text, length := bootstrapText(id)
	var out [17]byte
	written := C.diting_bootstrap_call_score(h.lib.score, h.pointer, (*C.char)(text), length,
		C.double(entryWeight), C.int64_t(nowNs), unsafe.Pointer(&out[0]), C.size_t(len(out)))
	if written != C.intptr_t(len(out)) {
		return 0, false, 0, false
	}
	weight := math.Float64frombits(binary.LittleEndian.Uint64(out[0:8]))
	cooling := out[8] != 0
	samples := math.Float64frombits(binary.LittleEndian.Uint64(out[9:17]))
	return weight, cooling, samples, true
}

// planResult is the decoded plan payload: indices into the caller's config snapshot.
type planResult struct {
	primary     int
	fallbacks   []int
	exploration bool
}

var errBootstrapPlanPayload = errors.New("bootstrap kernel returned a malformed plan payload")

func (h *nativeBootstrap) plan(ips []bootstrapIPConfig, nowNs int64, exploreRoll, weightRoll float64, indexRoll uint64) (planResult, error) {
	if h == nil || h.pointer == nil {
		return planResult{primary: -1}, errors.New("bootstrap kernel is not available")
	}
	entries := encodeBootstrapEntries(ips)
	capacity := 10 + 4*len(ips)
	out := make([]byte, capacity)
	var entriesPtr unsafe.Pointer
	if len(entries) > 0 {
		entriesPtr = unsafe.Pointer(&entries[0])
	}
	written := C.diting_bootstrap_call_plan(h.lib.plan, h.pointer, C.int64_t(nowNs),
		C.double(exploreRoll), C.double(weightRoll), C.uint64_t(indexRoll), entriesPtr,
		C.size_t(len(entries)), unsafe.Pointer(&out[0]), C.size_t(capacity))
	if written < 0 {
		return planResult{primary: -1}, fmt.Errorf("bootstrap plan failed (status %d)", int64(written))
	}
	payload := out[:int(written)]
	return decodeBootstrapPlan(payload, len(ips))
}

func encodeBootstrapEntries(ips []bootstrapIPConfig) []byte {
	payload := make([]byte, 5, 5+len(ips)*24)
	payload[0] = bootstrapPayloadLayoutVersion
	binary.LittleEndian.PutUint32(payload[1:5], uint32(len(ips)))
	for _, entry := range ips {
		var fixed [4]byte
		binary.LittleEndian.PutUint32(fixed[:], uint32(len(entry.ID)))
		payload = append(payload, fixed[:]...)
		payload = append(payload, entry.ID...)
		var weight [8]byte
		binary.LittleEndian.PutUint64(weight[:], math.Float64bits(entry.Weight))
		payload = append(payload, weight[:]...)
	}
	return payload
}

func decodeBootstrapPlan(payload []byte, count int) (planResult, error) {
	if len(payload) < 10 || payload[0] != bootstrapPayloadLayoutVersion {
		return planResult{primary: -1}, errBootstrapPlanPayload
	}
	primary := int(int32(binary.LittleEndian.Uint32(payload[1:5])))
	exploration := payload[5] != 0
	fallbackCount := int(binary.LittleEndian.Uint32(payload[6:10]))
	if len(payload) != 10+4*fallbackCount {
		return planResult{primary: -1}, errBootstrapPlanPayload
	}
	fallbacks := make([]int, 0, fallbackCount)
	for index := 0; index < fallbackCount; index++ {
		offset := 10 + 4*index
		fallback := int(binary.LittleEndian.Uint32(payload[offset : offset+4]))
		if fallback < 0 || fallback >= count {
			return planResult{primary: -1}, errBootstrapPlanPayload
		}
		fallbacks = append(fallbacks, fallback)
	}
	if primary < -1 || primary >= count {
		return planResult{primary: -1}, errBootstrapPlanPayload
	}
	return planResult{primary: primary, fallbacks: fallbacks, exploration: exploration}, nil
}

func (h *nativeBootstrap) cacheGet(host string, nowNs int64) (string, bool) {
	if h == nil || h.pointer == nil {
		return "", false
	}
	text, length := bootstrapText(host)
	var out [bootstrapMaxAddressBytes]byte
	written := C.diting_bootstrap_call_cache_get(h.lib.cacheGet, h.pointer, (*C.char)(text),
		length, C.int64_t(nowNs), unsafe.Pointer(&out[0]), C.size_t(len(out)))
	if written <= 0 {
		return "", false
	}
	return string(out[:int(written)]), true
}

func (h *nativeBootstrap) cachePut(host, ip string, nowNs int64) {
	if h == nil || h.pointer == nil {
		return
	}
	hostPtr, hostLen := bootstrapText(host)
	ipPtr, ipLen := bootstrapText(ip)
	C.diting_bootstrap_call_cache_put(h.lib.cachePut, h.pointer, (*C.char)(hostPtr), hostLen,
		(*C.char)(ipPtr), ipLen, C.int64_t(nowNs))
}

func (h *nativeBootstrap) clearCache() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_bootstrap_call_status(h.lib.clearCache, h.pointer)
}

func (h *nativeBootstrap) reset() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_bootstrap_call_status(h.lib.reset, h.pointer)
}

func (h *nativeBootstrap) healthCount() int {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int(C.diting_bootstrap_call_count(h.lib.healthCount, h.pointer))
}

func (h *nativeBootstrap) free() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_bootstrap_call_handle(h.lib.free, h.pointer)
	h.pointer = nil
}
