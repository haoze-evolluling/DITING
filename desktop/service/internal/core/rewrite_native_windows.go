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
	engineBuild := dll.NewProc("diting_rewrite_engine_build")
	engineLookup := dll.NewProc("diting_rewrite_engine_lookup")
	engineLookupPTR := dll.NewProc("diting_rewrite_engine_ptr_lookup")
	engineLookupReverse := dll.NewProc("diting_rewrite_engine_reverse_lookup")
	engineFree := dll.NewProc("diting_rewrite_engine_free")
	freeBytes := dll.NewProc("diting_rewrite_free_bytes")
	for _, proc := range []*syscall.LazyProc{
		abiVersion, buildRecord, recordTypes, engineBuild, engineLookup, engineLookupPTR,
		engineLookupReverse, engineFree, freeBytes,
	} {
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
		engineBuild: func(input unsafe.Pointer, inputLen uintptr, handle *unsafe.Pointer, out *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := engineBuild.Call(
				uintptr(input),
				inputLen,
				uintptr(unsafe.Pointer(handle)),
				uintptr(unsafe.Pointer(out)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		engineLookup: func(handle unsafe.Pointer, name unsafe.Pointer, nameLen uintptr, qtype uint16, out *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := engineLookup.Call(
				uintptr(handle),
				uintptr(name),
				nameLen,
				uintptr(qtype),
				uintptr(unsafe.Pointer(out)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		engineLookupPTR: func(handle unsafe.Pointer, ip unsafe.Pointer, ipLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := engineLookupPTR.Call(
				uintptr(handle),
				uintptr(ip),
				ipLen,
				uintptr(unsafe.Pointer(out)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		engineLookupReverse: func(handle unsafe.Pointer, ip unsafe.Pointer, ipLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := engineLookupReverse.Call(
				uintptr(handle),
				uintptr(ip),
				ipLen,
				uintptr(unsafe.Pointer(out)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		engineFree: func(handle unsafe.Pointer) {
			_, _, _ = engineFree.Call(uintptr(handle))
		},
		freeBytes: func(pointer unsafe.Pointer, length uintptr) {
			_, _, _ = freeBytes.Call(uintptr(pointer), length)
		},
	}, nil
}
