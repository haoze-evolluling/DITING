//go:build !windows

package core

// ratelimit_native_unix.go opens the Rust rate-limit kernel with purego, which reaches dlopen
// without cgo, so `CGO_ENABLED=0 GOOS=linux go build` keeps working exactly as before.

import (
	"fmt"

	"github.com/ebitengine/purego"
)

// loadRateLimitLibrary opens one candidate path and binds the entry points. A stale ABI is reported
// as an error so the caller moves on to the next candidate.
func loadRateLimitLibrary(path string) (*rateLimitNativeLib, error) {
	handle, err := purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
	if err != nil {
		return nil, err
	}
	symbols := []string{
		"diting_ratelimit_abi_version",
		"diting_ratelimit_new",
		"diting_ratelimit_configure",
		"diting_ratelimit_free",
		"diting_ratelimit_free_bytes",
		"diting_ratelimit_allow",
		"diting_ratelimit_cleanup",
		"diting_ratelimit_info",
	}
	for _, name := range symbols {
		// Dlsym first: RegisterLibFunc panics on a missing symbol, and a panic is not an error.
		if _, err := purego.Dlsym(handle, name); err != nil {
			_ = purego.Dlclose(handle)
			return nil, fmt.Errorf("missing symbol %s", name)
		}
	}

	var abiVersion func() uint32
	purego.RegisterLibFunc(&abiVersion, handle, "diting_ratelimit_abi_version")
	if version := abiVersion(); version != rateLimitNativeABIVersion {
		_ = purego.Dlclose(handle)
		return nil, fmt.Errorf("abi %d, expected %d", version, rateLimitNativeABIVersion)
	}

	lib := &rateLimitNativeLib{}
	purego.RegisterLibFunc(&lib.newLimiter, handle, "diting_ratelimit_new")
	purego.RegisterLibFunc(&lib.configure, handle, "diting_ratelimit_configure")
	purego.RegisterLibFunc(&lib.free, handle, "diting_ratelimit_free")
	purego.RegisterLibFunc(&lib.freeBytes, handle, "diting_ratelimit_free_bytes")
	purego.RegisterLibFunc(&lib.allow, handle, "diting_ratelimit_allow")
	purego.RegisterLibFunc(&lib.cleanup, handle, "diting_ratelimit_cleanup")
	purego.RegisterLibFunc(&lib.info, handle, "diting_ratelimit_info")
	return lib, nil
}
