//go:build !windows

package core

// safebrowsing_native_unix.go opens the Rust Safe Browsing kernel with purego, which reaches
// dlopen without cgo, so `CGO_ENABLED=0 GOOS=linux go build` keeps working exactly as before.

import (
	"fmt"

	"github.com/ebitengine/purego"
)

// loadSBLibrary opens one candidate path and binds the entry points. A stale ABI is reported as an
// error so the caller moves on to the next candidate.
func loadSBLibrary(path string) (*sbNativeLib, error) {
	handle, err := purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
	if err != nil {
		return nil, err
	}
	symbols := []string{
		"diting_sb_abi_version",
		"diting_sb_new",
		"diting_sb_free",
		"diting_sb_free_bytes",
		"diting_sb_configure",
		"diting_sb_plan",
		"diting_sb_apply",
	}
	for _, name := range symbols {
		// Dlsym first: RegisterLibFunc panics on a missing symbol, and a panic is not an error.
		if _, err := purego.Dlsym(handle, name); err != nil {
			_ = purego.Dlclose(handle)
			return nil, fmt.Errorf("missing symbol %s", name)
		}
	}

	var abiVersion func() uint32
	purego.RegisterLibFunc(&abiVersion, handle, "diting_sb_abi_version")
	if version := abiVersion(); version != sbNativeABIVersion {
		_ = purego.Dlclose(handle)
		return nil, fmt.Errorf("abi %d, expected %d", version, sbNativeABIVersion)
	}

	lib := &sbNativeLib{}
	purego.RegisterLibFunc(&lib.newEngine, handle, "diting_sb_new")
	purego.RegisterLibFunc(&lib.free, handle, "diting_sb_free")
	purego.RegisterLibFunc(&lib.freeBytes, handle, "diting_sb_free_bytes")
	purego.RegisterLibFunc(&lib.configure, handle, "diting_sb_configure")
	purego.RegisterLibFunc(&lib.plan, handle, "diting_sb_plan")
	purego.RegisterLibFunc(&lib.apply, handle, "diting_sb_apply")
	return lib, nil
}
