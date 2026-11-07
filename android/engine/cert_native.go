//go:build cgo

// cert_native.go loads the Rust MITM certificate kernel (rust/diting-cert-core) and drives its C
// ABI (that crate's src/ffi.rs).
//
// The kernel owns the root CA (generation, validation, the SEC1 key encoding) and leaf minting; Go
// keeps the file names, the read/write of `ca.crt` / `ca.key`, the minted-certificate LRU (its
// values are `*tls.Certificate`, a Go type), the per-host single-flight and the tls.Config glue.
// Every call passes unix seconds: the kernel never reads a clock.
//
// A missing library is a hard failure for MITM: `NewCertManager` reports it, so the tunnel starts
// without interception instead of asking the OS to trust a root nobody can sign with.

package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_cert_lib_t;
static diting_cert_lib_t diting_cert_open(const char* path) { return LoadLibraryA(path); }
static void* diting_cert_sym(diting_cert_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_cert_close(diting_cert_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_cert_lib_t;
static diting_cert_lib_t diting_cert_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_cert_sym(diting_cert_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_cert_close(diting_cert_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_cert_abi_fn)(void);
typedef uint32_t (*diting_cert_generate_fn)(int64_t, void**, char**, size_t*);
typedef uint32_t (*diting_cert_load_fn)(const char*, size_t, const char*, size_t, int64_t,
	void**, char**, size_t*);
typedef uint32_t (*diting_cert_ca_pem_fn)(const void*, char**, size_t*);
typedef uint32_t (*diting_cert_issue_fn)(const void*, const char*, size_t, int64_t, char**, size_t*);
typedef uint32_t (*diting_cert_is_ev_fn)(const char*, size_t);
typedef void (*diting_cert_free_fn)(void*);
typedef void (*diting_cert_free_bytes_fn)(char*, size_t);

static uint32_t diting_cert_call_abi(void* fn) { return ((diting_cert_abi_fn)fn)(); }
static uint32_t diting_cert_call_generate(void* fn, int64_t now, void** handle, char** out,
	size_t* out_len) {
	return ((diting_cert_generate_fn)fn)(now, handle, out, out_len);
}
static uint32_t diting_cert_call_load(void* fn, const char* cert, size_t cert_len,
	const char* key, size_t key_len, int64_t now, void** handle, char** out, size_t* out_len) {
	return ((diting_cert_load_fn)fn)(cert, cert_len, key, key_len, now, handle, out, out_len);
}
static uint32_t diting_cert_call_ca_pem(void* fn, const void* handle, char** out, size_t* out_len) {
	return ((diting_cert_ca_pem_fn)fn)(handle, out, out_len);
}
static uint32_t diting_cert_call_issue(void* fn, const void* handle, const char* host,
	size_t host_len, int64_t now, char** out, size_t* out_len) {
	return ((diting_cert_issue_fn)fn)(handle, host, host_len, now, out, out_len);
}
static uint32_t diting_cert_call_is_ev(void* fn, const char* csv, size_t csv_len) {
	return ((diting_cert_is_ev_fn)fn)(csv, csv_len);
}
static void diting_cert_call_free(void* fn, void* handle) { ((diting_cert_free_fn)fn)(handle); }
static void diting_cert_call_free_bytes(void* fn, char* pointer, size_t length) {
	((diting_cert_free_bytes_fn)fn)(pointer, length);
}
*/
import "C"

import (
	"encoding/asn1"
	"errors"
	"fmt"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
	"unsafe"
)

// certABIVersion must match `ABI_VERSION` in rust/diting-cert-core/src/ffi.rs.
const certABIVersion = 1

// Certificate kernel status codes (the crate's `ffi` constants).
const (
	certStatusOK        = 0
	certStatusOperation = 3
)

// errCertKernelMissing is reported when the kernel library is absent; MITM cannot run.
var errCertKernelMissing = errors.New("MITM CA: Rust certificate kernel unavailable")

type certNativeLib struct {
	lib      C.diting_cert_lib_t
	generate unsafe.Pointer
	load     unsafe.Pointer
	caPEM    unsafe.Pointer
	issue    unsafe.Pointer
	isEV     unsafe.Pointer
	free     unsafe.Pointer
	freeText unsafe.Pointer
}

var (
	certNativeOnce   sync.Once
	certNativeShared *certNativeLib
	certNativeErr    error
)

func certNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_cert_core.dll"
	case "darwin":
		return "libditing_cert_core.dylib"
	default:
		return "libditing_cert_core.so"
	}
}

// certNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func certNativeCandidates() []string {
	name := certNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func loadCertNative() (*certNativeLib, error) {
	abiSymbol := C.CString("diting_cert_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))

	lastErr := fmt.Errorf("library not found in %v", certNativeCandidates())
	for _, candidate := range certNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_cert_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_cert_sym(handle, abiSymbol)
		if abi == nil {
			C.diting_cert_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_cert_abi_version", candidate)
			continue
		}
		if version := uint32(C.diting_cert_call_abi(abi)); version != certABIVersion {
			C.diting_cert_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, certABIVersion)
			continue
		}
		lib := &certNativeLib{lib: handle}
		slots := []struct {
			name string
			slot *unsafe.Pointer
		}{
			{"diting_cert_generate", &lib.generate},
			{"diting_cert_load", &lib.load},
			{"diting_cert_ca_pem", &lib.caPEM},
			{"diting_cert_issue", &lib.issue},
			{"diting_cert_is_ev", &lib.isEV},
			{"diting_cert_free", &lib.free},
			{"diting_cert_free_bytes", &lib.freeText},
		}
		missing := ""
		for _, entry := range slots {
			name := C.CString(entry.name)
			pointer := C.diting_cert_sym(handle, name)
			C.free(unsafe.Pointer(name))
			if pointer == nil {
				missing = entry.name
				break
			}
			*entry.slot = pointer
		}
		if missing != "" {
			C.diting_cert_close(handle)
			lastErr = fmt.Errorf("%s: missing symbol %s", candidate, missing)
			continue
		}
		logf("MITM CA: Rust certificate kernel loaded from %s (abi=%d)", candidate, certABIVersion)
		return lib, nil
	}
	return nil, lastErr
}

// certKernel returns the loaded library; the failure is kept so the probe runs once per process.
func certKernel() (*certNativeLib, error) {
	certNativeOnce.Do(func() {
		certNativeShared, certNativeErr = loadCertNative()
	})
	if certNativeErr != nil {
		return nil, fmt.Errorf("%w: %v", errCertKernelMissing, certNativeErr)
	}
	return certNativeShared, nil
}

// nativeCertAuthority owns one engine's CA handle.
type nativeCertAuthority struct {
	lib     *certNativeLib
	pointer unsafe.Pointer
}

// certTakePayload copies a payload out of the kernel and frees the kernel copy.
func certTakePayload(lib *certNativeLib, pointer *C.char, length C.size_t) []byte {
	if pointer == nil {
		return nil
	}
	payload := C.GoBytes(unsafe.Pointer(pointer), C.int(length))
	C.diting_cert_call_free_bytes(lib.freeText, pointer, length)
	return payload
}

// certStatusError turns a non-zero status plus its payload into an error.
func certStatusError(lib *certNativeLib, status uint32, payload []byte) error {
	if status == certStatusOperation {
		reader := certPayloadReader{payload: payload}
		if message, ok := reader.text(); ok {
			return errors.New(message)
		}
		return errors.New("certificate kernel returned a malformed error payload")
	}
	return fmt.Errorf("certificate kernel rejected the call (status %d)", status)
}

// generateCertAuthority mints a new root and returns the handle plus the SEC1 key PEM to persist.
func generateCertAuthority(now time.Time) (*nativeCertAuthority, string, error) {
	lib, err := certKernel()
	if err != nil {
		return nil, "", err
	}
	var handle unsafe.Pointer
	var out *C.char
	var outLen C.size_t
	status := uint32(C.diting_cert_call_generate(lib.generate, C.int64_t(now.Unix()), &handle,
		&out, &outLen))
	payload := certTakePayload(lib, out, outLen)
	if status != certStatusOK {
		return nil, "", certStatusError(lib, status, payload)
	}
	if handle == nil {
		return nil, "", errors.New("certificate kernel returned a null CA handle")
	}
	reader := certPayloadReader{payload: payload}
	_, certOK := reader.text() // the CA PEM is fetched by the caller through `ca_pem`
	keyPEM, keyOK := reader.text()
	if !certOK || !keyOK || !reader.atEnd() {
		C.diting_cert_call_free(lib.free, handle)
		return nil, "", errors.New("certificate kernel returned a malformed CA payload")
	}
	return &nativeCertAuthority{lib: lib, pointer: handle}, keyPEM, nil
}

// loadCertAuthority validates and adopts a persisted root.
func loadCertAuthority(certPEM, keyPEM []byte, now time.Time) (*nativeCertAuthority, error) {
	lib, err := certKernel()
	if err != nil {
		return nil, err
	}
	certPointer, certLength := certBytes(certPEM)
	keyPointer, keyLength := certBytes(keyPEM)
	var handle unsafe.Pointer
	var out *C.char
	var outLen C.size_t
	status := uint32(C.diting_cert_call_load(lib.load, certPointer, certLength, keyPointer,
		keyLength, C.int64_t(now.Unix()), &handle, &out, &outLen))
	payload := certTakePayload(lib, out, outLen)
	if status != certStatusOK {
		return nil, certStatusError(lib, status, payload)
	}
	if handle == nil {
		return nil, errors.New("certificate kernel returned a null CA handle")
	}
	return &nativeCertAuthority{lib: lib, pointer: handle}, nil
}

// caPEM returns the CA certificate PEM the kernel holds.
func (h *nativeCertAuthority) caPEM() (string, error) {
	if h == nil || h.pointer == nil {
		return "", errCertKernelMissing
	}
	var out *C.char
	var outLen C.size_t
	status := uint32(C.diting_cert_call_ca_pem(h.lib.caPEM, h.pointer, &out, &outLen))
	payload := certTakePayload(h.lib, out, outLen)
	if status != certStatusOK {
		return "", certStatusError(h.lib, status, payload)
	}
	reader := certPayloadReader{payload: payload}
	text, ok := reader.text()
	if !ok || !reader.atEnd() {
		return "", errors.New("certificate kernel returned a malformed CA payload")
	}
	return text, nil
}

// issue mints one leaf: the certificate chain PEM, the shared key PEM and the leaf's NotAfter.
func (h *nativeCertAuthority) issue(host string, now time.Time) (string, string, time.Time, error) {
	if h == nil || h.pointer == nil {
		return "", "", time.Time{}, errCertKernelMissing
	}
	hostPointer, hostLength := certBytes([]byte(host))
	var out *C.char
	var outLen C.size_t
	status := uint32(C.diting_cert_call_issue(h.lib.issue, h.pointer, hostPointer, hostLength,
		C.int64_t(now.Unix()), &out, &outLen))
	payload := certTakePayload(h.lib, out, outLen)
	if status != certStatusOK {
		return "", "", time.Time{}, certStatusError(h.lib, status, payload)
	}
	reader := certPayloadReader{payload: payload}
	chainPEM, chainOK := reader.text()
	keyPEM, keyOK := reader.text()
	notAfter, timeOK := reader.int64()
	if !chainOK || !keyOK || !timeOK || !reader.atEnd() {
		return "", "", time.Time{}, errors.New("certificate kernel returned a malformed leaf payload")
	}
	return chainPEM, keyPEM, time.Unix(notAfter, 0), nil
}

func (h *nativeCertAuthority) release() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_cert_call_free(h.lib.free, h.pointer)
	h.pointer = nil
}

// certIsExtendedValidationNative answers `isExtendedValidation` for one certificate's policies.
func certIsExtendedValidationNative(oids []asn1.ObjectIdentifier) bool {
	if len(oids) == 0 {
		return false
	}
	lib, err := certKernel()
	if err != nil {
		return false
	}
	text := make([]string, 0, len(oids))
	for _, oid := range oids {
		text = append(text, oid.String())
	}
	csvPointer, csvLength := certBytes([]byte(strings.Join(text, ",")))
	return uint32(C.diting_cert_call_is_ev(lib.isEV, csvPointer, csvLength)) != 0
}

// certBytes hands a byte slice to the kernel. The kernel copies; the pointer never outlives a call.
func certBytes(value []byte) (*C.char, C.size_t) {
	if len(value) == 0 {
		return nil, 0
	}
	return (*C.char)(unsafe.Pointer(&value[0])), C.size_t(len(value))
}
