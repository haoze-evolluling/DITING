//go:build windows

package core

// safebrowsing_native_windows.go opens the Rust Safe Browsing kernel with syscall.LazyDLL, the
// stdlib loader, so the Windows build also stays cgo-free.

import (
	"fmt"
	"syscall"
	"unsafe"
)

// loadSBLibrary opens one candidate path and binds the entry points.
func loadSBLibrary(path string) (*sbNativeLib, error) {
	dll := syscall.NewLazyDLL(path)
	if err := dll.Load(); err != nil {
		return nil, err
	}

	abiVersion := dll.NewProc("diting_sb_abi_version")
	newEngine := dll.NewProc("diting_sb_new")
	free := dll.NewProc("diting_sb_free")
	freeBytes := dll.NewProc("diting_sb_free_bytes")
	configure := dll.NewProc("diting_sb_configure")
	plan := dll.NewProc("diting_sb_plan")
	apply := dll.NewProc("diting_sb_apply")
	for _, proc := range []*syscall.LazyProc{abiVersion, newEngine, free, freeBytes, configure, plan, apply} {
		if err := proc.Find(); err != nil {
			return nil, fmt.Errorf("missing symbol %s", proc.Name)
		}
	}

	version, _, _ := abiVersion.Call()
	if uint32(version) != sbNativeABIVersion {
		return nil, fmt.Errorf("abi %d, expected %d", uint32(version), sbNativeABIVersion)
	}

	return &sbNativeLib{
		newEngine: func(cacheSize int64, cacheTTLMs int64, out *unsafe.Pointer) uint32 {
			status, _, _ := newEngine.Call(
				uintptr(cacheSize),
				uintptr(cacheTTLMs),
				uintptr(unsafe.Pointer(out)),
			)
			return uint32(status)
		},
		free: func(handle unsafe.Pointer) {
			_, _, _ = free.Call(uintptr(handle))
		},
		freeBytes: func(pointer unsafe.Pointer, length uintptr) {
			_, _, _ = freeBytes.Call(uintptr(pointer), length)
		},
		configure: func(handle unsafe.Pointer, cacheSize int64, cacheTTLMs int64) {
			_, _, _ = configure.Call(uintptr(handle), uintptr(cacheSize), uintptr(cacheTTLMs))
		},
		plan: func(handle unsafe.Pointer, service uint32, host unsafe.Pointer, hostLen uintptr,
			nowMs int64, outPtr *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := plan.Call(
				uintptr(handle),
				uintptr(service),
				uintptr(host),
				hostLen,
				uintptr(nowMs),
				uintptr(unsafe.Pointer(outPtr)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		apply: func(handle unsafe.Pointer, request unsafe.Pointer, requestLen uintptr,
			nowMs int64) uint32 {
			status, _, _ := apply.Call(uintptr(handle), uintptr(request), requestLen, uintptr(nowMs))
			return uint32(status)
		},
	}, nil
}
