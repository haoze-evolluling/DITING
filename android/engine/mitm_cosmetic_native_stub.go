//go:build !cgo

// mitm_cosmetic_native_stub.go keeps the engine buildable without a C toolchain.
//
// Android builds cgo (the shipped AAR and the .so files); a `!cgo` build can still compile, it just
// cannot rewrite a page: `ensureCosmeticKernel` fails `StartStackMitm`, and a reader built anyway
// reports the error on its first Read rather than serving the page un-injected.

package tunnel

import "errors"

// errCosmeticUnavailable is what a reader reports when the kernel never loaded.
var errCosmeticUnavailable = errors.New("Rust cosmetic injection kernel is not available without cgo")

// cosmeticKernel is never constructed without cgo; it exists so the wrapper type-checks.
type cosmeticKernel struct{}

func ensureCosmeticKernel() error {
	return errCosmeticUnavailable
}

func cosmeticNativeNormalizeHost(string) (string, error) {
	return "", errCosmeticUnavailable
}

func cosmeticNativeLinkTag(string) (string, error) {
	return "", errCosmeticUnavailable
}

func newCosmeticKernel(string) (*cosmeticKernel, error) {
	return nil, errCosmeticUnavailable
}

func (k *cosmeticKernel) pending([]byte) int { return 0 }

func (k *cosmeticKernel) process([]byte, int, error) (int, error) {
	return 0, errCosmeticUnavailable
}

func (k *cosmeticKernel) free() {}
