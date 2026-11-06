//go:build !windows

package core

// stamp_native_unix.go opens the Rust stamp kernel with purego, which reaches dlopen without
// cgo, so `CGO_ENABLED=0 GOOS=linux go build` keeps working exactly as before.

import (
	"fmt"

	"github.com/ebitengine/purego"
)

// loadStampLibrary opens one candidate path and binds the entry points. A stale ABI is reported
// as an error so the caller moves on to the next candidate.
func loadStampLibrary(path string) (*stampNativeLib, error) {
	handle, err := purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
	if err != nil {
		return nil, err
	}
	symbols := []string{
		"diting_stamp_abi_version",
		"diting_stamp_parse",
		"diting_stamp_free",
	}
	for _, name := range symbols {
		// Dlsym first: RegisterLibFunc panics on a missing symbol, and a panic is not an error.
		if _, err := purego.Dlsym(handle, name); err != nil {
			_ = purego.Dlclose(handle)
			return nil, fmt.Errorf("missing symbol %s", name)
		}
	}

	var abiVersion func() uint32
	purego.RegisterLibFunc(&abiVersion, handle, "diting_stamp_abi_version")
	if version := abiVersion(); version != stampNativeABIVersion {
		_ = purego.Dlclose(handle)
		return nil, fmt.Errorf("abi %d, expected %d", version, stampNativeABIVersion)
	}

	lib := &stampNativeLib{}
	purego.RegisterLibFunc(&lib.parse, handle, "diting_stamp_parse")
	purego.RegisterLibFunc(&lib.free, handle, "diting_stamp_free")
	return lib, nil
}
