//go:build !cgo

// config_native_stub.go keeps the engine buildable without a C toolchain.
//
// Without the Rust kernel no config can be validated or normalized, so `ApplyDNSConfig` reports the
// missing library and keeps the previous snapshot; the value tables degrade to their defaults
// (PLAIN upstreams, CUSTOM_IP blocks, no DoQ endpoint) and rewrite targets are dropped. Android
// builds cgo (the shipped AAR and the .so files), so this only affects `go build` / `go vet` on a
// machine without a C compiler.

package tunnel

import "errors"

// errConfigKernelMissing mirrors the cgo build's sentinel.
var errConfigKernelMissing = errors.New("Rust config kernel is unavailable")

type normalizedDNSConfig struct {
	mode          string
	blockResponse ResponseType
	dynamic       dynamicBlockConfig
	providers     []dnsProviderConfig
}

func normalizeDNSConfig(
	mode string,
	blockResponse string,
	dynamic dynamicBlockConfig,
	providers []dnsProviderConfig,
) (normalizedDNSConfig, error) {
	return normalizedDNSConfig{}, errConfigKernelMissing
}

func parseProtocolNative(text string) DNSProtocol { return ProtocolPlain }

func parseResponseTypeNative(text string) ResponseType { return ResponseCustomIP }

func parseDoQURLNative(url string) (string, string) { return "", "" }

// normalizeDomainNative returns the input unchanged: without the kernel there is no fold, and a
// rewrite table cannot be built anyway (every target is dropped).
func normalizeDomainNative(domain string) string { return domain }

func classifyRewriteTargetsNative(targets []string) *rewriteEntry { return nil }
