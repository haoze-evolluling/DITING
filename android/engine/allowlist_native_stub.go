//go:build !cgo

// allowlist_native_stub.go keeps the engine buildable without a C toolchain.
//
// The Rust kernel owns the whole strict-allowlist decision. Without it an engine that configured
// rules fails closed (DNS and connections denied); an engine that configured none is unaffected.
// Android builds cgo (the shipped AAR and the .so files), so this only affects `go build` /
// `go vet` on a machine without a C compiler.

package tunnel

import (
	"errors"
	"net"
	"time"
)

var errAllowlistUnavailable = errors.New("Rust allowlist kernel is not available without cgo")

// nativeAllowlist is the opaque kernel handle of the cgo build; nothing can open one here.
type nativeAllowlist struct{}

func newNativeAllowlist() (*nativeAllowlist, error) {
	return nil, errAllowlistUnavailable
}

func (h *nativeAllowlist) configure(entries []appAllowlistEntry) error {
	return errAllowlistUnavailable
}

func (h *nativeAllowlist) hasUIDs() bool { return false }

func (h *nativeAllowlist) domainAllowed(uid int, domain string) bool { return false }

func (h *nativeAllowlist) connectionAllowed(uid int, ip net.IP, now time.Time) bool { return false }

func (h *nativeAllowlist) remember(uid int, questionName string, records []allowlistRecord, now time.Time) error {
	return errAllowlistUnavailable
}

func (h *nativeAllowlist) grantCount(uid int) int { return 0 }
