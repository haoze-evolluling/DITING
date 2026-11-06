//go:build !windows

package core

// filter_native_unix.go opens the Rust rule filter kernel with purego, which reaches dlopen without
// cgo, so `CGO_ENABLED=0 GOOS=linux go build` keeps working exactly as before.

import (
	"fmt"

	"github.com/ebitengine/purego"
)

// loadFilterLibrary opens one candidate path and binds the entry points. A stale ABI is reported as
// an error so the caller moves on to the next candidate.
func loadFilterLibrary(path string) (*filterNativeLib, error) {
	handle, err := purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
	if err != nil {
		return nil, err
	}
	symbols := []string{
		"diting_filter_abi_version",
		"diting_filter_build",
		"diting_filter_match",
		"diting_filter_free",
		"diting_filter_free_bytes",
	}
	for _, name := range symbols {
		// Dlsym first: RegisterLibFunc panics on a missing symbol, and a panic is not an error.
		if _, err := purego.Dlsym(handle, name); err != nil {
			_ = purego.Dlclose(handle)
			return nil, fmt.Errorf("missing symbol %s", name)
		}
	}

	var abiVersion func() uint32
	purego.RegisterLibFunc(&abiVersion, handle, "diting_filter_abi_version")
	if version := abiVersion(); version != filterNativeABIVersion {
		_ = purego.Dlclose(handle)
		return nil, fmt.Errorf("abi %d, expected %d", version, filterNativeABIVersion)
	}

	lib := &filterNativeLib{}
	purego.RegisterLibFunc(&lib.build, handle, "diting_filter_build")
	purego.RegisterLibFunc(&lib.match, handle, "diting_filter_match")
	purego.RegisterLibFunc(&lib.free, handle, "diting_filter_free")
	purego.RegisterLibFunc(&lib.freeBytes, handle, "diting_filter_free_bytes")
	return lib, nil
}
