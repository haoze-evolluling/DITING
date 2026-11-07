//go:build !cgo

// mitm_sniffer_native_stub.go keeps the engine buildable without a C toolchain.
//
// Android builds cgo (the shipped AAR and the .so files). Without cgo the MITM stack cannot start
// (`ensureSnifferKernel` fails), and the passthrough relay gets no hostname hint from the peeked
// bytes — the same outcome as an SNI the parser could not read.
package tunnel

import "errors"

// errSnifferUnavailable is what the passthrough path degrades to when the kernel never loaded.
var errSnifferUnavailable = errors.New("Rust flow sniffer kernel is not available without cgo")

func ensureSnifferKernel() error {
	return errSnifferUnavailable
}

func classifyFlow([]byte) (flowClass, string) {
	return classUnknown, ""
}
