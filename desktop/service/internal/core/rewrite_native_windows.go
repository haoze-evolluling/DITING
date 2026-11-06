//go:build windows

package core

// rewrite_native_windows.go opens the Rust rewrite-record kernel with syscall.LazyDLL, the stdlib
// loader, so the Windows build also stays cgo-free.

import (
	"fmt"
	"syscall"
	"unsafe"
)

// loadRewriteLibrary opens one candidate path and binds the entry points.
func loadRewriteLibrary(path string) (*rewriteNativeLib, error) {
	dll := syscall.NewLazyDLL(path)
	if err := dll.Load(); err != nil {
		return nil, err
	}

	abiVersion := dll.NewProc("diting_rewrite_abi_version")
	buildRecord := dll.NewProc("diting_rewrite_build_record")
	recordTypes := dll.NewProc("diting_rewrite_record_types")
	freeBytes := dll.NewProc("diting_rewrite_free_bytes")
	for _, proc := range []*syscall.LazyProc{abiVersion, buildRecord, recordTypes, freeBytes} {
		if err := proc.Find(); err != nil {
			return nil, fmt.Errorf("missing symbol %s", proc.Name)
		}
	}

	version, _, _ := abiVersion.Call()
	if uint32(version) != rewriteNativeABIVersion {
		return nil, fmt.Errorf("abi %d, expected %d", uint32(version), rewriteNativeABIVersion)
	}

	return &rewriteNativeLib{
		buildRecord: func(input unsafe.Pointer, inputLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := buildRecord.Call(
				uintptr(input),
				inputLen,
				uintptr(unsafe.Pointer(out)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		recordTypes: func(out *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := recordTypes.Call(
				uintptr(unsafe.Pointer(out)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		freeBytes: func(pointer unsafe.Pointer, length uintptr) {
			_, _, _ = freeBytes.Call(uintptr(pointer), length)
		},
	}, nil
}
