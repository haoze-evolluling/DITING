//go:build !cgo

// cert_native_stub.go keeps the engine buildable without a C toolchain.
//
// Without the Rust kernel no CA can be generated, validated or used to mint a leaf, so
// `NewCertManager` reports the missing library and MITM does not start; the tunnel itself is
// unaffected. Android builds cgo (the shipped AAR and the .so files), so this only affects
// `go build` / `go vet` on a machine without a C compiler.

package tunnel

import (
	"encoding/asn1"
	"errors"
	"time"
)

// errCertKernelMissing mirrors the cgo build's sentinel.
var errCertKernelMissing = errors.New("MITM CA: Rust certificate kernel unavailable")

// nativeCertAuthority is the cgo build's CA handle; there is no kernel to hold one here.
type nativeCertAuthority struct{}

func generateCertAuthority(now time.Time) (*nativeCertAuthority, string, error) {
	return nil, "", errCertKernelMissing
}

func loadCertAuthority(certPEM, keyPEM []byte, now time.Time) (*nativeCertAuthority, error) {
	return nil, errCertKernelMissing
}

func (h *nativeCertAuthority) caPEM() (string, error) {
	return "", errCertKernelMissing
}

func (h *nativeCertAuthority) issue(host string, now time.Time) (string, string, time.Time, error) {
	return "", "", time.Time{}, errCertKernelMissing
}

func (h *nativeCertAuthority) release() {}

func certIsExtendedValidationNative(oids []asn1.ObjectIdentifier) bool { return false }
