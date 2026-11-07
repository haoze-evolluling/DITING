//go:build cgo

// config_native.go loads the Rust configuration kernel (rust/diting-config-core) and drives its C
// ABI (that crate's src/ffi.rs).
//
// The kernel owns the settings semantics: the DNS mode aliases, the dynamic-block defaults, the
// provider endpoint rules (PLAIN / DOT host:port, DoH and DoQ URLs), the protocol and block-response
// name tables, the rewrite-target classification and the `TrimSuffix(ToLower(TrimSpace(d)), ".")`
// key fold. Go keeps `encoding/json` (the payload shape and its decode errors are the standard
// library's), the `Engine` state, the resolver / cache hand-off and every log line.
//
// A missing library means no config can be validated, so `ApplyDNSConfig` reports it instead of
// applying an unvalidated snapshot; the value tables degrade to their defaults (PLAIN upstreams,
// CUSTOM_IP blocks, no DoQ endpoint).

package tunnel

/*
#cgo android LDFLAGS: -ldl
#cgo linux LDFLAGS: -ldl
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef HMODULE diting_config_lib_t;
static diting_config_lib_t diting_config_open(const char* path) { return LoadLibraryA(path); }
static void* diting_config_sym(diting_config_lib_t lib, const char* name) {
	return (void*)(uintptr_t)GetProcAddress(lib, name);
}
static void diting_config_close(diting_config_lib_t lib) { FreeLibrary(lib); }
#else
#include <dlfcn.h>
typedef void* diting_config_lib_t;
static diting_config_lib_t diting_config_open(const char* path) {
	return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}
static void* diting_config_sym(diting_config_lib_t lib, const char* name) {
	return dlsym(lib, name);
}
static void diting_config_close(diting_config_lib_t lib) { dlclose(lib); }
#endif

typedef uint32_t (*diting_config_abi_fn)(void);
typedef uint32_t (*diting_config_call_fn)(const uint8_t*, size_t, uint8_t**, size_t*);
typedef void (*diting_config_free_fn)(uint8_t*, size_t);

static uint32_t diting_config_call_abi(void* fn) { return ((diting_config_abi_fn)fn)(); }
static uint32_t diting_config_call_run(void* fn, const uint8_t* request, size_t request_len,
	uint8_t** out, size_t* out_len) {
	return ((diting_config_call_fn)fn)(request, request_len, out, out_len);
}
static void diting_config_call_free(void* fn, uint8_t* pointer, size_t length) {
	((diting_config_free_fn)fn)(pointer, length);
}
*/
import "C"

import (
	"errors"
	"fmt"
	"net"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"
)

// configABIVersion must match `ABI_VERSION` in rust/diting-config-core/src/ffi.rs.
const configABIVersion = 1

// errConfigKernelMissing is reported when the kernel library is absent.
var errConfigKernelMissing = errors.New("Rust config kernel is unavailable")

type configNativeLib struct {
	lib  C.diting_config_lib_t
	call unsafe.Pointer
	free unsafe.Pointer
}

var (
	configNativeOnce   sync.Once
	configNativeShared *configNativeLib
	configNativeErr    error
)

func configNativeName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_config_core.dll"
	case "darwin":
		return "libditing_config_core.dylib"
	default:
		return "libditing_config_core.so"
	}
}

// configNativeCandidates probes the packaged name first, then a local `cargo build` output so
// `go test` works without installing anything.
func configNativeCandidates() []string {
	name := configNativeName()
	candidates := []string{name}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "rust", "target", profile, name))
	}
	return candidates
}

func loadConfigNative() (*configNativeLib, error) {
	abiSymbol := C.CString("diting_config_abi_version")
	defer C.free(unsafe.Pointer(abiSymbol))
	callSymbol := C.CString("diting_config_call")
	defer C.free(unsafe.Pointer(callSymbol))
	freeSymbol := C.CString("diting_config_free_bytes")
	defer C.free(unsafe.Pointer(freeSymbol))

	lastErr := fmt.Errorf("library not found in %v", configNativeCandidates())
	for _, candidate := range configNativeCandidates() {
		path := C.CString(candidate)
		handle := C.diting_config_open(path)
		C.free(unsafe.Pointer(path))
		if handle == nil {
			continue
		}
		abi := C.diting_config_sym(handle, abiSymbol)
		call := C.diting_config_sym(handle, callSymbol)
		free := C.diting_config_sym(handle, freeSymbol)
		if abi == nil || call == nil || free == nil {
			C.diting_config_close(handle)
			lastErr = fmt.Errorf("%s: missing diting_config symbols", candidate)
			continue
		}
		if version := uint32(C.diting_config_call_abi(abi)); version != configABIVersion {
			C.diting_config_close(handle)
			lastErr = fmt.Errorf("%s: abi %d, expected %d", candidate, version, configABIVersion)
			continue
		}
		logf("DNSConfig: Rust kernel loaded from %s (abi=%d)", candidate, configABIVersion)
		return &configNativeLib{lib: handle, call: call, free: free}, nil
	}
	return nil, lastErr
}

// configKernel returns the loaded library; the failure is kept so the probe runs once per process.
func configKernel() (*configNativeLib, error) {
	configNativeOnce.Do(func() {
		configNativeShared, configNativeErr = loadConfigNative()
		if configNativeErr != nil {
			logf("DNSConfig: Rust kernel unavailable, DNS configs cannot be validated: %v",
				configNativeErr)
		}
	})
	if configNativeErr != nil {
		return nil, fmt.Errorf("%w: %v", errConfigKernelMissing, configNativeErr)
	}
	return configNativeShared, nil
}

// configCall runs one request payload and returns the response body with its status byte.
func configCall(request []byte) (byte, []byte, error) {
	lib, err := configKernel()
	if err != nil {
		return configStatusError, nil, err
	}
	var requestPointer *C.uint8_t
	if len(request) > 0 {
		requestPointer = (*C.uint8_t)(unsafe.Pointer(&request[0]))
	}
	var out *C.uint8_t
	var outLen C.size_t
	status := C.diting_config_call_run(lib.call, requestPointer, C.size_t(len(request)), &out, &outLen)
	if status != 0 {
		return configStatusError, nil, fmt.Errorf("config kernel rejected the call (status %d)", status)
	}
	if out == nil || outLen == 0 {
		return configStatusError, nil, errors.New("config kernel returned an empty response")
	}
	response := C.GoBytes(unsafe.Pointer(out), C.int(outLen))
	C.diting_config_call_free(lib.free, out, outLen)
	if len(response) == 0 {
		return configStatusError, nil, errors.New("config kernel returned an empty response")
	}
	return response[0], response[1:], nil
}

// configErrorMessage reads the error body (one `str` message).
func configErrorMessage(body []byte) error {
	reader := configPayloadReader{payload: body}
	message, ok := reader.text()
	if !ok {
		return errors.New("config kernel returned a malformed error")
	}
	return errors.New(message)
}

// normalizedDNSConfig is what the kernel returns for a whole config.
type normalizedDNSConfig struct {
	mode          string
	blockResponse ResponseType
	dynamic       dynamicBlockConfig
	providers     []dnsProviderConfig
}

// normalizeDNSConfig validates and normalizes one DNS config, or reports the error the UI shows.
func normalizeDNSConfig(
	mode string,
	blockResponse string,
	dynamic dynamicBlockConfig,
	providers []dnsProviderConfig,
) (normalizedDNSConfig, error) {
	var result normalizedDNSConfig
	payload := newConfigPayload(configOpDNSConfig).
		text(mode).
		text(blockResponse).
		bool(dynamic.Enabled).
		int64(int64(dynamic.RequestThreshold)).
		int64(int64(dynamic.WindowSeconds)).
		int64(int64(dynamic.NXDomainSeconds)).
		int64(int64(len(providers)))
	for _, provider := range providers {
		payload.text(provider.ID).
			text(provider.Protocol).
			text(provider.Server).
			text(provider.URL).
			int64(int64(provider.Weight))
	}

	status, body, err := configCall(payload.body)
	if err != nil {
		return result, err
	}
	if status != configStatusOK {
		return result, configErrorMessage(body)
	}

	reader := configPayloadReader{payload: body}
	if result.mode, err = configRequiredText(reader.text()); err != nil {
		return normalizedDNSConfig{}, err
	}
	blockCode, err := configRequiredInt(reader.int64())
	if err != nil {
		return normalizedDNSConfig{}, err
	}
	result.blockResponse = ResponseType(blockCode)
	enabled, err := configRequiredInt(reader.int64())
	if err != nil {
		return normalizedDNSConfig{}, err
	}
	result.dynamic.Enabled = enabled == 1
	threshold, err := configRequiredInt(reader.int64())
	if err != nil {
		return normalizedDNSConfig{}, err
	}
	result.dynamic.RequestThreshold = int(threshold)
	window, err := configRequiredInt(reader.int64())
	if err != nil {
		return normalizedDNSConfig{}, err
	}
	result.dynamic.WindowSeconds = int(window)
	nxdomain, err := configRequiredInt(reader.int64())
	if err != nil {
		return normalizedDNSConfig{}, err
	}
	result.dynamic.NXDomainSeconds = int(nxdomain)
	count, err := configRequiredInt(reader.int64())
	if err != nil {
		return normalizedDNSConfig{}, err
	}
	if count < 0 || count > int64(len(body)) {
		return normalizedDNSConfig{}, errors.New("config kernel returned a malformed provider count")
	}
	result.providers = make([]dnsProviderConfig, 0, count)
	for index := int64(0); index < count; index++ {
		provider := dnsProviderConfig{}
		if provider.ID, err = configRequiredText(reader.text()); err != nil {
			return normalizedDNSConfig{}, err
		}
		// The upper-cased name is what `statsKey` and the log lines use.
		if provider.Protocol, err = configRequiredText(reader.text()); err != nil {
			return normalizedDNSConfig{}, err
		}
		if provider.Server, err = configRequiredText(reader.text()); err != nil {
			return normalizedDNSConfig{}, err
		}
		if provider.URL, err = configRequiredText(reader.text()); err != nil {
			return normalizedDNSConfig{}, err
		}
		weight, err := configRequiredInt(reader.int64())
		if err != nil {
			return normalizedDNSConfig{}, err
		}
		provider.Weight = int(weight)
		result.providers = append(result.providers, provider)
	}
	if !reader.atEnd() {
		return normalizedDNSConfig{}, errors.New("config kernel returned trailing bytes")
	}
	return result, nil
}

// parseProtocolNative answers `ParseProtocol`; every unknown spelling is PLAIN.
func parseProtocolNative(text string) DNSProtocol {
	status, body, err := configCall(newConfigPayload(configOpProtocol).text(text).body)
	if err != nil || status != configStatusOK {
		return ProtocolPlain
	}
	reader := configPayloadReader{payload: body}
	code, ok := reader.int64()
	if !ok {
		return ProtocolPlain
	}
	return DNSProtocol(code)
}

// parseResponseTypeNative answers `ParseResponseType` (case-sensitive, unknown means CUSTOM_IP).
func parseResponseTypeNative(text string) ResponseType {
	status, body, err := configCall(newConfigPayload(configOpResponseType).text(text).body)
	if err != nil || status != configStatusOK {
		return ResponseCustomIP
	}
	reader := configPayloadReader{payload: body}
	code, ok := reader.int64()
	if !ok {
		return ResponseCustomIP
	}
	return ResponseType(code)
}

// parseDoQURLNative answers `parseDoQURL`; without the kernel the pair is empty and the caller
// reports an invalid DoQ endpoint instead of dialing a guessed host.
func parseDoQURLNative(url string) (string, string) {
	status, body, err := configCall(newConfigPayload(configOpDoQURL).text(url).body)
	if err != nil || status != configStatusOK {
		return "", ""
	}
	reader := configPayloadReader{payload: body}
	host, ok := reader.text()
	if !ok {
		return "", ""
	}
	port, ok := reader.text()
	if !ok {
		return "", ""
	}
	return host, port
}

// normalizeDomainNative is the `TrimSuffix(ToLower(TrimSpace(domain)), ".")` key fold.
func normalizeDomainNative(domain string) string {
	status, body, err := configCall(newConfigPayload(configOpDomain).text(domain).body)
	if err != nil || status != configStatusOK {
		return domain
	}
	reader := configPayloadReader{payload: body}
	normalized, ok := reader.text()
	if !ok {
		return domain
	}
	return normalized
}

// classifyRewriteTargetsNative turns one value's target list into an entry, or nil when nothing
// survived (the old code dropped such a value).
func classifyRewriteTargetsNative(targets []string) *rewriteEntry {
	payload := newConfigPayload(configOpRewrite).int64(int64(len(targets)))
	for _, target := range targets {
		payload.text(target)
	}
	status, body, err := configCall(payload.body)
	if err != nil || status != configStatusOK {
		return nil
	}
	reader := configPayloadReader{payload: body}
	cname, ok := reader.text()
	if !ok {
		return nil
	}
	ip4, ok := reader.text()
	if !ok {
		return nil
	}
	ip6, ok := reader.text()
	if !ok {
		return nil
	}
	entry := &rewriteEntry{cname: cname}
	if ip4 != "" {
		entry.ip4 = net.ParseIP(ip4)
	}
	if ip6 != "" {
		entry.ip6 = net.ParseIP(ip6)
	}
	if entry.cname == "" && entry.ip4 == nil && entry.ip6 == nil {
		return nil
	}
	return entry
}

func configRequiredText(text string, ok bool) (string, error) {
	if !ok {
		return "", errors.New("config kernel returned a truncated payload")
	}
	return text, nil
}

func configRequiredInt(value int64, ok bool) (int64, error) {
	if !ok {
		return 0, errors.New("config kernel returned a truncated payload")
	}
	return value, nil
}
