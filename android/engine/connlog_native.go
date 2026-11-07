//go:build cgo

// connlog_native.go loads the Rust connection-log dedupe kernel (rust/diting-connlog-core) and
// drives its C ABI (that crate's src/ffi.rs).
//
// Responsibility split: the kernel owns the bounded `seen` set, the overflow reset, the overflow
// counter and the key builder (`connLogKey`), so Go no longer allocates the concatenated key for
// every flow, including the duplicates it then drops. Go keeps the flow → app/dest derivation, the
// log text and the callback dispatch.
//
// If the library is missing or has a stale ABI, deduplication is disabled: every connection log is
// emitted. That only costs repeated lines; there is no second key builder or set to drift.

package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_connlog_lib_t;
static diting_connlog_lib_t diting_connlog_open(const char* path) { return LoadLibraryA(path); }
static void* diting_connlog_sym(diting_connlog_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_connlog_close(diting_connlog_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_connlog_lib_t;
static diting_connlog_lib_t diting_connlog_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_connlog_sym(diting_connlog_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_connlog_close(diting_connlog_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_connlog_abi_fn)(void);
typedef void* (*diting_connlog_new_fn)(void);
typedef void (*diting_connlog_handle_fn)(void*);
typedef int32_t (*diting_connlog_mark_fn)(void*, const void*, size_t);
typedef uint32_t (*diting_connlog_reset_fn)(void*);
typedef uint32_t (*diting_connlog_size_fn)(void*);
typedef uint64_t (*diting_connlog_cleared_fn)(void*);

static uint32_t diting_connlog_call_abi(void* fn) { return ((diting_connlog_abi_fn)fn)(); }
static void* diting_connlog_call_new(void* fn) { return ((diting_connlog_new_fn)fn)(); }
static void diting_connlog_call_handle(void* fn, void* handle) {
	((diting_connlog_handle_fn)fn)(handle);
}
static int32_t diting_connlog_call_mark(void* fn, void* handle, const void* payload,
	size_t length) {
	return ((diting_connlog_mark_fn)fn)(handle, payload, length);
}
static uint32_t diting_connlog_call_status(void* fn, void* handle) {
	return ((diting_connlog_reset_fn)fn)(handle);
}
static uint32_t diting_connlog_call_size(void* fn, void* handle) {
	return ((diting_connlog_size_fn)fn)(handle);
}
static uint64_t diting_connlog_call_cleared(void* fn, void* handle) {
	return ((diting_connlog_cleared_fn)fn)(handle);
}
*/
import "C"

import (
	"encoding/binary"
	"errors"
	"fmt"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"
)

// connLogABIVersion must match `ABI_VERSION` in rust/diting-connlog-core/src/ffi.rs.
const connLogABIVersion = 1

// connLogPayloadLayoutVersion must match `LAYOUT_VERSION` in the kernel's payload.rs.
const connLogPayloadLayoutVersion = 1

type connLogNativeLib struct {
	lib C.diting_connlog_lib_t

	new     unsafe.Pointer
	free    unsafe.Pointer
	mark    unsafe.Pointer
	reset   unsafe.Pointer
	size    unsafe.Pointer
	cleared unsafe.Pointer
}

var (
	connLogNativeOnce   sync.Once
	connLogNativeShared *connLogNativeLib
	connLogNativeErr    error
)

func connLogNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_connlog_core.dll"
	case "darwin":
		return "libditing_connlog_core.dylib"
	default:
		return "libditing_connlog_core.so"
	}
}

// connLogNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func connLogNativeCandidates() []string {
	name := connLogNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func connLogNativeSymbols(lib *connLogNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_connlog_new", &lib.new},
		{"diting_connlog_free", &lib.free},
		{"diting_connlog_mark", &lib.mark},
		{"diting_connlog_reset", &lib.reset},
		{"diting_connlog_size", &lib.size},
		{"diting_connlog_cleared", &lib.cleared},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_connlog_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadConnLogNative() (*connLogNativeLib, error) {
	abiSymbol := C.CString("diting_connlog_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", connLogNativeCandidates())
	for _, candidate := range connLogNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_connlog_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_connlog_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_connlog_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_connlog_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_connlog_call_abi(abi))
		if version != connLogABIVersion {
			C.diting_connlog_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, connLogABIVersion)
			continue
		}
		lib := &connLogNativeLib{lib: handle}
		if err := connLogNativeSymbols(lib); err != nil {
			C.diting_connlog_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		logf("ConnLog: Rust kernel loaded from %s (abi=%d)", candidate, version)
		return lib, nil
	}
	return nil, lastErr
}

// connLogKernel returns the loaded library; the failure is kept so the probe runs once per process.
func connLogKernel() (*connLogNativeLib, error) {
	connLogNativeOnce.Do(func() {
		connLogNativeShared, connLogNativeErr = loadConnLogNative()
		if connLogNativeErr != nil {
			logf("ConnLog: Rust kernel unavailable, deduplication is disabled: %v",
				connLogNativeErr)
		}
	})
	return connLogNativeShared, connLogNativeErr
}

// nativeConnLog owns the dedupe set handle.
type nativeConnLog struct {
	lib     *connLogNativeLib
	pointer unsafe.Pointer
}

func newNativeConnLog() (*nativeConnLog, error) {
	lib, err := connLogKernel()
	if err != nil {
		return nil, err
	}
	pointer := C.diting_connlog_call_new(lib.new)
	if pointer == nil {
		return nil, errors.New("connlog kernel returned a null handle")
	}
	return &nativeConnLog{lib: lib, pointer: pointer}, nil
}

func encodeConnLogMark(prefix, app, dest string, port, protocol int, reason string) []byte {
	payload := make([]byte, 9)
	payload[0] = connLogPayloadLayoutVersion
	binary.LittleEndian.PutUint32(payload[1:5], uint32(int32(port)))
	binary.LittleEndian.PutUint32(payload[5:9], uint32(int32(protocol)))
	for _, text := range []string{prefix, app, dest, reason} {
		var length [4]byte
		binary.LittleEndian.PutUint32(length[:], uint32(len(text)))
		payload = append(payload, length[:]...)
		payload = append(payload, text...)
	}
	return payload
}

func (h *nativeConnLog) mark(prefix, app, dest string, port, protocol int, reason string) bool {
	if h == nil || h.pointer == nil {
		return false
	}
	payload := encodeConnLogMark(prefix, app, dest, port, protocol, reason)
	status := C.diting_connlog_call_mark(h.lib.mark, h.pointer,
		unsafe.Pointer(&payload[0]), C.size_t(len(payload)))
	return status == 1
}

func (h *nativeConnLog) reset() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_connlog_call_status(h.lib.reset, h.pointer)
}

func (h *nativeConnLog) size() int {
	if h == nil || h.pointer == nil {
		return 0
	}
	return int(C.diting_connlog_call_size(h.lib.size, h.pointer))
}

func (h *nativeConnLog) cleared() uint64 {
	if h == nil || h.pointer == nil {
		return 0
	}
	return uint64(C.diting_connlog_call_cleared(h.lib.cleared, h.pointer))
}
