//go:build windows

package core

// hosts_native_windows.go opens the Rust hosts kernel with syscall.LazyDLL, the stdlib loader, so
// the Windows build also stays cgo-free.

import (
	"fmt"
	"syscall"
	"unsafe"
)

// loadHostsLibrary opens one candidate path and binds the entry points.
func loadHostsLibrary(path string) (*hostsNativeLib, error) {
	dll := syscall.NewLazyDLL(path)
	if err := dll.Load(); err != nil {
		return nil, err
	}

	abiVersion := dll.NewProc("diting_hosts_abi_version")
	newTable := dll.NewProc("diting_hosts_new")
	free := dll.NewProc("diting_hosts_free")
	freeBytes := dll.NewProc("diting_hosts_free_bytes")
	info := dll.NewProc("diting_hosts_info")
	lookup := dll.NewProc("diting_hosts_lookup")
	contains := dll.NewProc("diting_hosts_contains")
	ptr := dll.NewProc("diting_hosts_ptr")
	reverse := dll.NewProc("diting_hosts_reverse")
	parseArpa := dll.NewProc("diting_hosts_parse_arpa")
	for _, proc := range []*syscall.LazyProc{
		abiVersion, newTable, free, freeBytes, info, lookup, contains, ptr, reverse, parseArpa,
	} {
		if err := proc.Find(); err != nil {
			return nil, fmt.Errorf("missing symbol %s", proc.Name)
		}
	}

	version, _, _ := abiVersion.Call()
	if uint32(version) != hostsNativeABIVersion {
		return nil, fmt.Errorf("abi %d, expected %d", uint32(version), hostsNativeABIVersion)
	}

	return &hostsNativeLib{
		newTable: func(sources unsafe.Pointer, sourcesLen uintptr, out *unsafe.Pointer) uint32 {
			status, _, _ := newTable.Call(uintptr(sources), sourcesLen, uintptr(unsafe.Pointer(out)))
			return uint32(status)
		},
		free: func(handle unsafe.Pointer) {
			_, _, _ = free.Call(uintptr(handle))
		},
		freeBytes: func(pointer unsafe.Pointer, length uintptr) {
			_, _, _ = freeBytes.Call(uintptr(pointer), length)
		},
		info: func(handle unsafe.Pointer, outPtr *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := info.Call(
				uintptr(handle),
				uintptr(unsafe.Pointer(outPtr)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		lookup: func(handle unsafe.Pointer, host unsafe.Pointer, hostLen uintptr, qtype uint16,
			outPtr *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := lookup.Call(
				uintptr(handle),
				uintptr(host),
				hostLen,
				uintptr(qtype),
				uintptr(unsafe.Pointer(outPtr)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		contains: func(handle unsafe.Pointer, host unsafe.Pointer, hostLen uintptr) uint32 {
			status, _, _ := contains.Call(uintptr(handle), uintptr(host), hostLen)
			return uint32(status)
		},
		ptr: func(handle unsafe.Pointer, arpa unsafe.Pointer, arpaLen uintptr,
			outPtr *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := ptr.Call(
				uintptr(handle),
				uintptr(arpa),
				arpaLen,
				uintptr(unsafe.Pointer(outPtr)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		reverse: func(handle unsafe.Pointer, address unsafe.Pointer, addressLen uintptr,
			outPtr *unsafe.Pointer, outLen *uintptr) uint32 {
			status, _, _ := reverse.Call(
				uintptr(handle),
				uintptr(address),
				addressLen,
				uintptr(unsafe.Pointer(outPtr)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
		parseArpa: func(name unsafe.Pointer, nameLen uintptr, outPtr *unsafe.Pointer,
			outLen *uintptr) uint32 {
			status, _, _ := parseArpa.Call(
				uintptr(name),
				nameLen,
				uintptr(unsafe.Pointer(outPtr)),
				uintptr(unsafe.Pointer(outLen)),
			)
			return uint32(status)
		},
	}, nil
}
