//go:build !cgo

// proxy_native_stub.go keeps the engine buildable without a C toolchain.
//
// Without the Rust kernel the proxy feature is unavailable: no config can be validated and no
// handshake can be encoded, so `ConfigureOutboundProxy` reports the missing library and proxied
// dials fail. Direct traffic is unaffected. Android builds cgo (the shipped AAR and the .so
// files), so this only affects `go build` / `go vet` on a machine without a C compiler.

package tunnel

// proxyCall is the cgo build's kernel entry point; there is no kernel to call here.
func proxyCall(request []byte) ([]byte, error) {
	return nil, errProxyUnavailable
}
