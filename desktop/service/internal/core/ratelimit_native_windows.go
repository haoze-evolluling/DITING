//go:build windows

package core

// ratelimit_native_windows.go opens the Rust rate-limit kernel with syscall.LazyDLL, the stdlib
// loader, so the Windows build also stays cgo-free.

import (
	"fmt"
	"syscall"
	"unsafe"
)

// loadRateLimitLibrary opens one candidate path and binds the entry points.
func loadRateLimitLibrary(path string) (*rateLimitNativeLib, error) {
	dll := syscall.NewLazyDLL(path)
	if err := dll.Load(); err != nil {
		return nil, err
	}

	abiVersion := dll.NewProc("diting_ratelimit_abi_version")
	newLimiter := dll.NewProc("diting_ratelimit_new")
	configure := dll.NewProc("diting_ratelimit_configure")
	free := dll.NewProc("diting_ratelimit_free")
	freeBytes := dll.NewProc("diting_ratelimit_free_bytes")
	allow := dll.NewProc("diting_ratelimit_allow")
	cleanup := dll.NewProc("diting_ratelimit_cleanup")
	info := dll.NewProc("diting_ratelimit_info")
	for _, proc := range []*syscall.LazyProc{
		abiVersion, newLimiter, configure, free, freeBytes, allow, cleanup, info,
	} {
		if err := proc.Find(); err != nil {
			return nil, fmt.Errorf("missing symbol %s", proc.Name)
		}
	}

	version, _, _ := abiVersion.Call()
	if uint32(version) != rateLimitNativeABIVersion {
		return nil, fmt.Errorf("abi %d, expected %d", uint32(version), rateLimitNativeABIVersion)
	}

	return &rateLimitNativeLib{
		newLimiter: func(config unsafe.Pointer, configLen uintptr, out *unsafe.Pointer) uint32 {
			status, _, _ := newLimiter.Call(
				uintptr(config),
				configLen,
				uintptr(unsafe.Pointer(out)),
			)
			return uint32(status)
		},
		configure: func(handle unsafe.Pointer, config unsafe.Pointer, configLen uintptr) uint32 {
			status, _, _ := configure.Call(uintptr(handle), uintptr(config), configLen)
			return uint32(status)
		},
		free: func(handle unsafe.Pointer) {
			_, _, _ = free.Call(uintptr(handle))
		},
		freeBytes: func(pointer unsafe.Pointer, length uintptr) {
			_, _, _ = freeBytes.Call(uintptr(pointer), length)
		},
		allow: func(handle unsafe.Pointer, address unsafe.Pointer, addressLen uintptr,
			nowNs int64, maxBuckets uint32) int32 {
			status, _, _ := allow.Call(
				uintptr(handle),
				uintptr(address),
				addressLen,
				uintptr(nowNs),
				uintptr(maxBuckets),
			)
			return int32(status)
		},
		cleanup: func(handle unsafe.Pointer, nowNs int64) {
			_, _, _ = cleanup.Call(uintptr(handle), uintptr(nowNs))
		},
		info: func(handle unsafe.Pointer, outPtr *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := info.Call(
				uintptr(handle),
				uintptr(unsafe.Pointer(outPtr)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
	}, nil
}
