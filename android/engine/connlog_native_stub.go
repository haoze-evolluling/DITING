//go:build !cgo

// connlog_native_stub.go keeps the engine buildable without a C toolchain.
//
// Without the Rust kernel deduplication is disabled (every connection log is emitted), which only
// costs repeated lines. Android builds cgo (the shipped AAR and the .so files), so this only
// affects `go build` / `go vet` on a machine without a C compiler.

package tunnel

import "errors"

var errConnLogUnavailable = errors.New("Rust connlog kernel is not available without cgo")

// nativeConnLog is the opaque kernel handle of the cgo build; nothing can open one here.
type nativeConnLog struct{}

func newNativeConnLog() (*nativeConnLog, error) {
	return nil, errConnLogUnavailable
}

func (h *nativeConnLog) mark(prefix, app, dest string, port, protocol int, reason string) bool {
	return false
}

func (h *nativeConnLog) reset() {}

func (h *nativeConnLog) size() int { return 0 }

func (h *nativeConnLog) cleared() uint64 { return 0 }
