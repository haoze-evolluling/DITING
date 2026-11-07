//go:build cgo

// mitm_cosmetic_native.go loads the Rust cosmetic injection kernel (rust/diting-cosmetic-core) and
// drives the C ABI in that crate's src/ffi.rs.
//
// Responsibility split: the kernel owns the streaming `<head>` scanner (carry, pending, the 16 KiB
// scan limit and the splice), the hostname normalization and the `<link>` tag itself. Go keeps the
// rule payload, the `io.ReadCloser` the relay hands to net/http, the log lines and the zlib
// plumbing that produces the reader's upstream.
//
// The kernel is required: `ensureCosmeticKernel` runs when the MITM stack starts, and a reader built
// without it reports the loading error on its first Read instead of serving the page un-injected.
package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_cosmetic_lib_t;
static diting_cosmetic_lib_t diting_cosmetic_open(const char* path) { return LoadLibraryA(path); }
static void* diting_cosmetic_sym(diting_cosmetic_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_cosmetic_close(diting_cosmetic_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_cosmetic_lib_t;
static diting_cosmetic_lib_t diting_cosmetic_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_cosmetic_sym(diting_cosmetic_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_cosmetic_close(diting_cosmetic_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_cosmetic_abi_fn)(void);
typedef uint32_t (*diting_cosmetic_link_fn)(const void*, size_t, const void*, size_t, void**,
	size_t*);
typedef uint32_t (*diting_cosmetic_normalize_fn)(const void*, size_t, void**, size_t*);
typedef void (*diting_cosmetic_free_bytes_fn)(void*, size_t);
typedef uint32_t (*diting_cosmetic_new_fn)(const void*, size_t, void**);
typedef void (*diting_cosmetic_free_fn)(void*);
typedef uint32_t (*diting_cosmetic_pending_fn)(void*, void*, size_t);
typedef uint32_t (*diting_cosmetic_process_fn)(void*, void*, size_t, size_t, uint32_t, uint32_t*,
	uint8_t*);

static uint32_t diting_cosmetic_call_abi(void* fn) { return ((diting_cosmetic_abi_fn)fn)(); }
static uint32_t diting_cosmetic_call_link(void* fn, const void* host, size_t host_len,
	const void* asset_host, size_t asset_host_len, void** payload, size_t* payload_len) {
	return ((diting_cosmetic_link_fn)fn)(host, host_len, asset_host, asset_host_len, payload,
		payload_len);
}
static uint32_t diting_cosmetic_call_normalize(void* fn, const void* host, size_t host_len,
	void** payload, size_t* payload_len) {
	return ((diting_cosmetic_normalize_fn)fn)(host, host_len, payload, payload_len);
}
static void diting_cosmetic_call_free_bytes(void* fn, void* pointer, size_t length) {
	((diting_cosmetic_free_bytes_fn)fn)(pointer, length);
}
static uint32_t diting_cosmetic_call_new(void* fn, const void* payload, size_t payload_len,
	void** handle) {
	return ((diting_cosmetic_new_fn)fn)(payload, payload_len, handle);
}
static void diting_cosmetic_call_free(void* fn, void* handle) {
	((diting_cosmetic_free_fn)fn)(handle);
}
static uint32_t diting_cosmetic_call_pending(void* fn, void* handle, void* buffer,
	size_t capacity) {
	return ((diting_cosmetic_pending_fn)fn)(handle, buffer, capacity);
}
static uint32_t diting_cosmetic_call_process(void* fn, void* handle, void* buffer, size_t capacity,
	size_t n, uint32_t flags, uint32_t* out_len, uint8_t* out_keep_error) {
	return ((diting_cosmetic_process_fn)fn)(handle, buffer, capacity, n, flags, out_len,
		out_keep_error);
}
*/
import "C"

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"
)

// cosmeticNativeABIVersion must match `ABI_VERSION` in rust/diting-cosmetic-core/src/ffi.rs.
const cosmeticNativeABIVersion = 1

// cosmeticPayloadLayoutVersion must match `payload::LAYOUT_VERSION`.
const cosmeticPayloadLayoutVersion = 1

// Upstream flags; see rust/diting-cosmetic-core/src/inject.rs.
const (
	cosmeticUpstreamErrored = 1 << 0
	cosmeticUpstreamEOF     = 1 << 1
)

// errCosmeticUnavailable is what a reader reports when the kernel never loaded.
var errCosmeticUnavailable = errors.New("Rust cosmetic injection kernel is not available")

type cosmeticNativeLib struct {
	lib C.diting_cosmetic_lib_t

	normalize unsafe.Pointer
	linkTag   unsafe.Pointer
	freeBytes unsafe.Pointer
	newReader unsafe.Pointer
	free      unsafe.Pointer
	pending   unsafe.Pointer
	process   unsafe.Pointer
}

var (
	cosmeticNativeOnce   sync.Once
	cosmeticNativeShared *cosmeticNativeLib
	cosmeticNativeErr    error
)

func cosmeticNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_cosmetic_core.dll"
	case "darwin":
		return "libditing_cosmetic_core.dylib"
	default:
		return "libditing_cosmetic_core.so"
	}
}

// cosmeticNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func cosmeticNativeCandidates() []string {
	name := cosmeticNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func cosmeticNativeSymbols(lib *cosmeticNativeLib) error {
	type symbol struct {
		name string
		slot *unsafe.Pointer
	}
	symbols := []symbol{
		{"diting_cosmetic_normalize_host", &lib.normalize},
		{"diting_cosmetic_link_tag", &lib.linkTag},
		{"diting_cosmetic_free_bytes", &lib.freeBytes},
		{"diting_cosmetic_new", &lib.newReader},
		{"diting_cosmetic_free", &lib.free},
		{"diting_cosmetic_pending", &lib.pending},
		{"diting_cosmetic_process", &lib.process},
	}
	for _, entry := range symbols {
		name := C.CString(entry.name)
		pointer := C.diting_cosmetic_sym(lib.lib, name)
		C.free(unsafe.Pointer(name))
		if pointer == nil {
			return fmt.Errorf("missing symbol %s", entry.name)
		}
		*entry.slot = pointer
	}
	return nil
}

func loadCosmeticNative() (*cosmeticNativeLib, error) {
	abiName := C.CString("diting_cosmetic_abi_version")
	defer C.free(unsafe.Pointer(abiName))

	lastErr := fmt.Errorf("library not found in %v", cosmeticNativeCandidates())
	for _, candidate := range cosmeticNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_cosmetic_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_cosmetic_sym(handle, abiName)
		if abi == nil {
			C.diting_cosmetic_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_cosmetic_abi_version", candidate)
			continue
		}
		version := uint32(C.diting_cosmetic_call_abi(abi))
		if version != cosmeticNativeABIVersion {
			C.diting_cosmetic_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version,
				cosmeticNativeABIVersion)
			continue
		}
		lib := &cosmeticNativeLib{lib: handle}
		if err := cosmeticNativeSymbols(lib); err != nil {
			C.diting_cosmetic_close(handle)
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		return lib, nil
	}
	return nil, lastErr
}

// cosmeticLibrary loads the kernel once per process.
func cosmeticLibrary() (*cosmeticNativeLib, error) {
	cosmeticNativeOnce.Do(func() {
		cosmeticNativeShared, cosmeticNativeErr = loadCosmeticNative()
	})
	return cosmeticNativeShared, cosmeticNativeErr
}

// ensureCosmeticKernel fails the MITM stack start when the kernel is missing, so no response is
// ever rewritten by half a pipeline.
func ensureCosmeticKernel() error {
	_, err := cosmeticLibrary()
	return err
}

// cosmeticText hands a Go string to the C ABI as pointer plus length.
func cosmeticText(value string) (unsafe.Pointer, C.size_t) {
	return unsafe.Pointer(unsafe.StringData(value)), C.size_t(len(value))
}

// copyCosmeticPayload copies a payload the kernel returned and frees it.
func copyCosmeticPayload(lib *cosmeticNativeLib, pointer unsafe.Pointer, length C.size_t) []byte {
	encoded := C.GoBytes(pointer, C.int(length))
	C.diting_cosmetic_call_free_bytes(lib.freeBytes, pointer, length)
	return encoded
}

// cosmeticNativeNormalizeHost is `normalizeCosmeticHost` in the kernel: the local asset server and
// the injected link must spell the page host the same way, so neither keeps a copy of the rules.
func cosmeticNativeNormalizeHost(host string) (string, error) {
	lib, err := cosmeticLibrary()
	if err != nil {
		return "", err
	}
	var payload unsafe.Pointer
	var payloadLen C.size_t
	hostPtr, hostLen := cosmeticText(host)
	status := C.diting_cosmetic_call_normalize(lib.normalize, hostPtr, hostLen, &payload, &payloadLen)
	runtime.KeepAlive(host)
	if status != 0 || payload == nil {
		return "", fmt.Errorf("normalize host call failed with status %d", status)
	}
	return decodeCosmeticText(copyCosmeticPayload(lib, payload, payloadLen), "normalized host")
}

// cosmeticNativeLinkTag builds the `<link>` tag in the kernel and copies the payload back.
func cosmeticNativeLinkTag(host string) (string, error) {
	lib, err := cosmeticLibrary()
	if err != nil {
		return "", err
	}
	asset := LocalAssetHost
	var payload unsafe.Pointer
	var payloadLen C.size_t
	hostPtr, hostLen := cosmeticText(host)
	assetPtr, assetLen := cosmeticText(asset)
	status := C.diting_cosmetic_call_link(
		lib.linkTag,
		hostPtr,
		hostLen,
		assetPtr,
		assetLen,
		&payload,
		&payloadLen,
	)
	runtime.KeepAlive(host)
	runtime.KeepAlive(asset)
	if status != 0 || payload == nil {
		return "", fmt.Errorf("link tag call failed with status %d", status)
	}
	return decodeCosmeticText(copyCosmeticPayload(lib, payload, payloadLen), "link tag")
}

// cosmeticKernel is one scanner: one response body's worth of state.
type cosmeticKernel struct {
	lib    *cosmeticNativeLib
	handle unsafe.Pointer
}

func newCosmeticKernel(linkTag string) (*cosmeticKernel, error) {
	lib, err := cosmeticLibrary()
	if err != nil {
		return nil, err
	}
	payload := encodeCosmeticLinkTag(linkTag)
	var handle unsafe.Pointer
	status := C.diting_cosmetic_call_new(
		lib.newReader,
		unsafe.Pointer(&payload[0]),
		C.size_t(len(payload)),
		&handle,
	)
	runtime.KeepAlive(payload)
	if status != 0 || handle == nil {
		return nil, fmt.Errorf("cosmetic reader rejected the link tag (status %d)", status)
	}
	return &cosmeticKernel{lib: lib, handle: handle}, nil
}

// pending serves the bytes queued by a previous splice.
func (k *cosmeticKernel) pending(buffer []byte) int {
	if k == nil || k.handle == nil || len(buffer) == 0 {
		return 0
	}
	written := C.diting_cosmetic_call_pending(
		k.lib.pending,
		k.handle,
		unsafe.Pointer(&buffer[0]),
		C.size_t(len(buffer)),
	)
	runtime.KeepAlive(buffer)
	return int(written)
}

// process rewrites the n bytes a Read just put into buffer.
func (k *cosmeticKernel) process(buffer []byte, n int, err error) (int, error) {
	if k == nil || k.handle == nil {
		return 0, errCosmeticUnavailable
	}
	var flags uint32
	if err != nil {
		flags |= cosmeticUpstreamErrored
		if errors.Is(err, io.EOF) {
			flags |= cosmeticUpstreamEOF
		}
	}
	var outLen C.uint32_t
	var keepError C.uint8_t
	var pointer unsafe.Pointer
	if len(buffer) > 0 {
		pointer = unsafe.Pointer(&buffer[0])
	}
	status := C.diting_cosmetic_call_process(
		k.lib.process,
		k.handle,
		pointer,
		C.size_t(len(buffer)),
		C.size_t(n),
		C.uint32_t(flags),
		&outLen,
		&keepError,
	)
	runtime.KeepAlive(buffer)
	if status != 0 {
		return 0, fmt.Errorf("cosmetic scanner rejected the chunk (status %d)", status)
	}
	if keepError == 0 {
		return int(outLen), nil
	}
	return int(outLen), err
}

func (k *cosmeticKernel) free() {
	if k == nil || k.handle == nil {
		return
	}
	C.diting_cosmetic_call_free(k.lib.free, k.handle)
	k.handle = nil
}
