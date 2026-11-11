//go:build !windows

package core

// dns64_native_unix.go opens the Rust DNS64 kernel with purego, which reaches dlopen without cgo,
// so `CGO_ENABLED=0 GOOS=linux go build` keeps working exactly as before.

import (
	"fmt"

	"github.com/ebitengine/purego"
)

// loadDNS64Library opens one candidate path and binds the entry points. A stale ABI is reported as
// an error so the caller moves on to the next candidate.
func loadDNS64Library(path string) (*dns64NativeLib, error) {
	handle, err := purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
	if err != nil {
		return nil, err
	}
	symbols := []string{
		"diting_dns64_abi_version",
		"diting_dns64_new",
		"diting_dns64_free",
		"diting_dns64_free_bytes",
		"diting_dns64_embed",
		"diting_dns64_embed_net",
		"diting_dns64_synthesize",
		"diting_dns64_excluded",
		"diting_dns64_has_valid",
	}
	for _, name := range symbols {
		// Dlsym first: RegisterLibFunc panics on a missing symbol, and a panic is not an error.
		if _, err := purego.Dlsym(handle, name); err != nil {
			_ = purego.Dlclose(handle)
			return nil, fmt.Errorf("missing symbol %s", name)
		}
	}

	var abiVersion func() uint32
	purego.RegisterLibFunc(&abiVersion, handle, "diting_dns64_abi_version")
	if version := abiVersion(); version != dns64NativeABIVersion {
		_ = purego.Dlclose(handle)
		return nil, fmt.Errorf("abi %d, expected %d", version, dns64NativeABIVersion)
	}

	lib := &dns64NativeLib{}
	purego.RegisterLibFunc(&lib.newEngine, handle, "diting_dns64_new")
	purego.RegisterLibFunc(&lib.free, handle, "diting_dns64_free")
	purego.RegisterLibFunc(&lib.freeBytes, handle, "diting_dns64_free_bytes")
	purego.RegisterLibFunc(&lib.embed, handle, "diting_dns64_embed")
	purego.RegisterLibFunc(&lib.embedNet, handle, "diting_dns64_embed_net")
	purego.RegisterLibFunc(&lib.synthesize, handle, "diting_dns64_synthesize")
	purego.RegisterLibFunc(&lib.excluded, handle, "diting_dns64_excluded")
	purego.RegisterLibFunc(&lib.hasValid, handle, "diting_dns64_has_valid")
	return lib, nil
}
