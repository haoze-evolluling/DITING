//go:build windows

package core

// filter_native_windows.go opens the Rust rule filter kernel with syscall.LazyDLL, the stdlib
// loader, so the Windows build also stays cgo-free.

import (
	"fmt"
	"syscall"
	"unsafe"
)

// loadFilterLibrary opens one candidate path and binds the entry points.
func loadFilterLibrary(path string) (*filterNativeLib, error) {
	dll := syscall.NewLazyDLL(path)
	if err := dll.Load(); err != nil {
		return nil, err
	}

	abiVersion := dll.NewProc("diting_filter_abi_version")
	build := dll.NewProc("diting_filter_build")
	match := dll.NewProc("diting_filter_match")
	free := dll.NewProc("diting_filter_free")
	freeBytes := dll.NewProc("diting_filter_free_bytes")
	for _, proc := range []*syscall.LazyProc{abiVersion, build, match, free, freeBytes} {
		if err := proc.Find(); err != nil {
			return nil, fmt.Errorf("missing symbol %s", proc.Name)
		}
	}

	version, _, _ := abiVersion.Call()
	if uint32(version) != filterNativeABIVersion {
		return nil, fmt.Errorf("abi %d, expected %d", uint32(version), filterNativeABIVersion)
	}

	return &filterNativeLib{
		build: func(input unsafe.Pointer, inputLen uintptr, handleOut *unsafe.Pointer, out *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := build.Call(
				uintptr(input),
				inputLen,
				uintptr(unsafe.Pointer(handleOut)),
				uintptr(unsafe.Pointer(out)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		match: func(handle unsafe.Pointer, domain unsafe.Pointer, domainLen uintptr, qtype uint16, out *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := match.Call(
				uintptr(handle),
				uintptr(domain),
				domainLen,
				uintptr(qtype),
				uintptr(unsafe.Pointer(out)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		free: func(handle unsafe.Pointer) {
			_, _, _ = free.Call(uintptr(handle))
		},
		freeBytes: func(pointer unsafe.Pointer, length uintptr) {
			_, _, _ = freeBytes.Call(uintptr(pointer), length)
		},
	}, nil
}
