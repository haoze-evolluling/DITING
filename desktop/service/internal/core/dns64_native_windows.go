//go:build windows

package core

// dns64_native_windows.go opens the Rust DNS64 kernel with syscall.LazyDLL, the stdlib loader, so
// the Windows build also stays cgo-free.

import (
	"fmt"
	"syscall"
	"unsafe"
)

// loadDNS64Library opens one candidate path and binds the entry points.
func loadDNS64Library(path string) (*dns64NativeLib, error) {
	dll := syscall.NewLazyDLL(path)
	if err := dll.Load(); err != nil {
		return nil, err
	}

	abiVersion := dll.NewProc("diting_dns64_abi_version")
	newEngine := dll.NewProc("diting_dns64_new")
	free := dll.NewProc("diting_dns64_free")
	freeBytes := dll.NewProc("diting_dns64_free_bytes")
	embed := dll.NewProc("diting_dns64_embed")
	embedNet := dll.NewProc("diting_dns64_embed_net")
	synthesize := dll.NewProc("diting_dns64_synthesize")
	excluded := dll.NewProc("diting_dns64_excluded")
	hasValid := dll.NewProc("diting_dns64_has_valid")
	for _, proc := range []*syscall.LazyProc{
		abiVersion, newEngine, free, freeBytes, embed, embedNet, synthesize, excluded, hasValid,
	} {
		if err := proc.Find(); err != nil {
			return nil, fmt.Errorf("missing symbol %s", proc.Name)
		}
	}

	version, _, _ := abiVersion.Call()
	if uint32(version) != dns64NativeABIVersion {
		return nil, fmt.Errorf("abi %d, expected %d", uint32(version), dns64NativeABIVersion)
	}

	return &dns64NativeLib{
		newEngine: func(enabled uint8, prefixes unsafe.Pointer, prefixesLen uintptr,
			out *unsafe.Pointer, outIndex *uint32) uint32 {
			status, _, _ := newEngine.Call(
				uintptr(enabled),
				uintptr(prefixes),
				prefixesLen,
				uintptr(unsafe.Pointer(out)),
				uintptr(unsafe.Pointer(outIndex)),
			)
			return uint32(status)
		},
		free: func(handle unsafe.Pointer) {
			_, _, _ = free.Call(uintptr(handle))
		},
		freeBytes: func(pointer unsafe.Pointer, length uintptr) {
			_, _, _ = freeBytes.Call(uintptr(pointer), length)
		},
		embed: func(handle unsafe.Pointer, v4 unsafe.Pointer, v4Len uintptr, out unsafe.Pointer) uint32 {
			status, _, _ := embed.Call(uintptr(handle), uintptr(v4), v4Len, uintptr(out))
			return uint32(status)
		},
		embedNet: func(prefix unsafe.Pointer, ones uint8, v4 unsafe.Pointer, v4Len uintptr,
			out unsafe.Pointer) uint32 {
			status, _, _ := embedNet.Call(
				uintptr(prefix),
				uintptr(ones),
				uintptr(v4),
				v4Len,
				uintptr(out),
			)
			return uint32(status)
		},
		synthesize: func(handle unsafe.Pointer, v4 unsafe.Pointer, v4Len uintptr,
			outPtr *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := synthesize.Call(
				uintptr(handle),
				uintptr(v4),
				v4Len,
				uintptr(unsafe.Pointer(outPtr)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		excluded: func(handle unsafe.Pointer, address unsafe.Pointer, addressLen uintptr,
			out *uint8) uint32 {
			status, _, _ := excluded.Call(
				uintptr(handle),
				uintptr(address),
				addressLen,
				uintptr(unsafe.Pointer(out)),
			)
			return uint32(status)
		},
		hasValid: func(handle unsafe.Pointer, data unsafe.Pointer, dataLen uintptr, out *uint8) uint32 {
			status, _, _ := hasValid.Call(
				uintptr(handle),
				uintptr(data),
				dataLen,
				uintptr(unsafe.Pointer(out)),
			)
			return uint32(status)
		},
	}, nil
}
