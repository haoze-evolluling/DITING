//go:build windows

package core

// stamp_native_windows.go opens the Rust stamp kernel with syscall.LazyDLL, the stdlib loader, so
// the Windows build also stays cgo-free.

import (
	"fmt"
	"syscall"
	"unsafe"
)

// loadStampLibrary opens one candidate path and binds the entry points.
func loadStampLibrary(path string) (*stampNativeLib, error) {
	dll := syscall.NewLazyDLL(path)
	if err := dll.Load(); err != nil {
		return nil, err
	}

	abiVersion := dll.NewProc("diting_stamp_abi_version")
	parse := dll.NewProc("diting_stamp_parse")
	free := dll.NewProc("diting_stamp_free")
	for _, proc := range []*syscall.LazyProc{abiVersion, parse, free} {
		if err := proc.Find(); err != nil {
			return nil, fmt.Errorf("missing symbol %s", proc.Name)
		}
	}

	version, _, _ := abiVersion.Call()
	if uint32(version) != stampNativeABIVersion {
		return nil, fmt.Errorf("abi %d, expected %d", uint32(version), stampNativeABIVersion)
	}

	return &stampNativeLib{
		parse: func(input unsafe.Pointer, inputLen uintptr, outPtr *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := parse.Call(
				uintptr(input),
				inputLen,
				uintptr(unsafe.Pointer(outPtr)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		free: func(pointer unsafe.Pointer, length uintptr) {
			_, _, _ = free.Call(uintptr(pointer), length)
		},
	}, nil
}
