//go:build cgo

// mitm_sniffer_native.go loads the Rust flow sniffer kernel (rust/diting-sniffer-core) and drives
// the C ABI in that crate's src/ffi.rs.
//
// Responsibility split: the kernel owns the TLS ClientHello walk (record/handshake/extension
// lengths and the SNI entry) and the plaintext HTTP sniff (method gate, `Host` walk, Go's
// `strings.TrimSpace` and `EqualFold` semantics). Go keeps the single peek `Read`, the replaying
// reader, the timeout, and the dial/relay it feeds.
//
// The kernel is required for MITM: `ensureSnifferKernel` runs when the MITM stack starts, so a
// flow is never classified by a missing parser. The passthrough relay calls the same function for
// its dial-failure hostname hint; there a missing kernel only means "no hostname hint", which is
// what an empty SNI already meant.
package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_sniffer_lib_t;
static diting_sniffer_lib_t diting_sniffer_open(const char* path) { return LoadLibraryA(path); }
static void* diting_sniffer_sym(diting_sniffer_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_sniffer_close(diting_sniffer_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_sniffer_lib_t;
static diting_sniffer_lib_t diting_sniffer_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_sniffer_sym(diting_sniffer_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_sniffer_close(diting_sniffer_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_sniffer_abi_fn)(void);
typedef uint32_t (*diting_sniffer_classify_fn)(const void*, size_t, void**, size_t*);
typedef void (*diting_sniffer_free_bytes_fn)(void*, size_t);

static uint32_t diting_sniffer_call_abi(void* fn) { return ((diting_sniffer_abi_fn)fn)(); }
static uint32_t diting_sniffer_call_classify(void* fn, const void* data, size_t length,
	void** payload, size_t* payload_len) {
	return ((diting_sniffer_classify_fn)fn)(data, length, payload, payload_len);
}
static void diting_sniffer_call_free_bytes(void* fn, void* pointer, size_t length) {
	((diting_sniffer_free_bytes_fn)fn)(pointer, length);
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

// snifferNativeABIVersion must match `ABI_VERSION` in rust/diting-sniffer-core/src/ffi.rs.
const snifferNativeABIVersion = 1

type snifferNativeLib struct {
	lib       C.diting_sniffer_lib_t
	classify  unsafe.Pointer
	freeBytes unsafe.Pointer
}

var (
	snifferNativeOnce   sync.Once
	snifferNativeShared *snifferNativeLib
	snifferNativeErr    error
)

func snifferNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_sniffer_core.dll"
	case "darwin":
		return "libditing_sniffer_core.dylib"
	default:
		return "libditing_sniffer_core.so"
	}
}

// snifferNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func snifferNativeCandidates() []string {
	name := snifferNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func snifferNativeSymbols(lib *snifferNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_sniffer_classify", &lib.classify},
		{"diting_sniffer_free_bytes", &lib.freeBytes},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_sniffer_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadSnifferNative() (*snifferNativeLib, error) {
	abiName := C.CString("diting_sniffer_abi_version")
	defer C.free(unsafe.Pointer(abiName))

	lastErr := fmt.Errorf("library not found in %v", snifferNativeCandidates())
	for _, candidate := range snifferNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_sniffer_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_sniffer_sym(handle, abiName)
		if abi == nil {
			C.diting_sniffer_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_sniffer_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_sniffer_call_abi(abi))
		if version != snifferNativeABIVersion {
			C.diting_sniffer_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version,
				snifferNativeABIVersion)
			continue
		}
		lib := &snifferNativeLib{lib: handle}
		if err := snifferNativeSymbols(lib); err != nil {
			C.diting_sniffer_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		return lib, nil
	}
	return nil, lastErr
}

// snifferLibrary loads the kernel once per process.
func snifferLibrary() (*snifferNativeLib, error) {
	snifferNativeOnce.Do(func() {
		snifferNativeShared, snifferNativeErr = loadSnifferNative()
	})
	return snifferNativeShared, snifferNativeErr
}

// ensureSnifferKernel fails the MITM stack start when the kernel is missing, so no flow is ever
// routed by a parser that did not load.
func ensureSnifferKernel() error {
	_, err := snifferLibrary()
	return err
}

// classifyFlow is the sniff step of the MITM pipeline: one call decides TLS / HTTP / neither and
// returns the hostname the parser found (empty when it found none).
//
// A kernel that failed to load classifies as unknown: the MITM path would have failed its start,
// and the passthrough path treats this exactly like an SNI that did not parse.
func classifyFlow(data []byte) (flowClass, string) {
	lib, err := snifferLibrary()
	if err != nil {
		return classUnknown, ""
	}
	var pointer unsafe.Pointer
	if len(data) > 0 {
		pointer = unsafe.Pointer(&data[0])
	}
	var payload unsafe.Pointer
	var payloadLen C.size_t
	status := C.diting_sniffer_call_classify(
		lib.classify,
		pointer,
		C.size_t(len(data)),
		&payload,
		&payloadLen,
	)
	runtime.KeepAlive(data)
	if status != 0 || payload == nil {
		return classUnknown, ""
	}
	encoded := C.GoBytes(payload, C.int(payloadLen))
	C.diting_sniffer_call_free_bytes(lib.freeBytes, payload, payloadLen)

	kind, host, decodeErr := decodeSnifferPayload(encoded)
	if decodeErr != nil {
		return classUnknown, ""
	}
	switch kind {
	case snifferKindTLS:
		return classTLS, string(host)
	case snifferKindHTTP:
		return classHTTP, string(host)
	default:
		return classUnknown, ""
	}
}
