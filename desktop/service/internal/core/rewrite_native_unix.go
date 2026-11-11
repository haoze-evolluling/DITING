//go:build !windows

package core

// rewrite_native_unix.go opens the Rust rewrite-record kernel with purego, which reaches dlopen
// without cgo, so `CGO_ENABLED=0 GOOS=linux go build` keeps working exactly as before.

import (
	"fmt"

	"github.com/ebitengine/purego"
)

// loadRewriteLibrary opens one candidate path and binds the entry points. A stale ABI is reported
// as an error so the caller moves on to the next candidate.
func loadRewriteLibrary(path string) (*rewriteNativeLib, error) {
	handle, err := purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
	if err != nil {
		return nil, err
	}
	symbols := []string{
		"diting_rewrite_abi_version",
		"diting_rewrite_build_record",
		"diting_rewrite_parse_action",
		"diting_rewrite_action_key",
		"diting_rewrite_record_types",
		"diting_rewrite_engine_build",
		"diting_rewrite_engine_lookup",
		"diting_rewrite_engine_ptr_lookup",
		"diting_rewrite_engine_reverse_lookup",
		"diting_rewrite_engine_free",
		"diting_rewrite_free_bytes",
	}
	for _, name := range symbols {
		// Dlsym first: RegisterLibFunc panics on a missing symbol, and a panic is not an error.
		if _, err := purego.Dlsym(handle, name); err != nil {
			_ = purego.Dlclose(handle)
			return nil, fmt.Errorf("missing symbol %s", name)
		}
	}

	var abiVersion func() uint32
	purego.RegisterLibFunc(&abiVersion, handle, "diting_rewrite_abi_version")
	if version := abiVersion(); version != rewriteNativeABIVersion {
		_ = purego.Dlclose(handle)
		return nil, fmt.Errorf("abi %d, expected %d", version, rewriteNativeABIVersion)
	}

	lib := &rewriteNativeLib{}
	purego.RegisterLibFunc(&lib.buildRecord, handle, "diting_rewrite_build_record")
	purego.RegisterLibFunc(&lib.parseAction, handle, "diting_rewrite_parse_action")
	purego.RegisterLibFunc(&lib.actionKey, handle, "diting_rewrite_action_key")
	purego.RegisterLibFunc(&lib.recordTypes, handle, "diting_rewrite_record_types")
	purego.RegisterLibFunc(&lib.engineBuild, handle, "diting_rewrite_engine_build")
	purego.RegisterLibFunc(&lib.engineLookup, handle, "diting_rewrite_engine_lookup")
	purego.RegisterLibFunc(&lib.engineLookupPTR, handle, "diting_rewrite_engine_ptr_lookup")
	purego.RegisterLibFunc(&lib.engineLookupReverse, handle, "diting_rewrite_engine_reverse_lookup")
	purego.RegisterLibFunc(&lib.engineFree, handle, "diting_rewrite_engine_free")
	purego.RegisterLibFunc(&lib.freeBytes, handle, "diting_rewrite_free_bytes")
	return lib, nil
}
