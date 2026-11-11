//go:build !windows

package core

// hosts_native_unix.go opens the Rust hosts kernel with purego, which reaches dlopen without cgo,
// so `CGO_ENABLED=0 GOOS=linux go build` keeps working exactly as before.

import (
	"fmt"

	"github.com/ebitengine/purego"
)

// loadHostsLibrary opens one candidate path and binds the entry points. A stale ABI is reported as
// an error so the caller moves on to the next candidate.
func loadHostsLibrary(path string) (*hostsNativeLib, error) {
	handle, err := purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
	if err != nil {
		return nil, err
	}
	symbols := []string{
		"diting_hosts_abi_version",
		"diting_hosts_new",
		"diting_hosts_free",
		"diting_hosts_free_bytes",
		"diting_hosts_info",
		"diting_hosts_lookup",
		"diting_hosts_contains",
		"diting_hosts_ptr",
		"diting_hosts_reverse",
		"diting_hosts_parse_arpa",
	}
	for _, name := range symbols {
		// Dlsym first: RegisterLibFunc panics on a missing symbol, and a panic is not an error.
		if _, err := purego.Dlsym(handle, name); err != nil {
			_ = purego.Dlclose(handle)
			return nil, fmt.Errorf("missing symbol %s", name)
		}
	}

	var abiVersion func() uint32
	purego.RegisterLibFunc(&abiVersion, handle, "diting_hosts_abi_version")
	if version := abiVersion(); version != hostsNativeABIVersion {
		_ = purego.Dlclose(handle)
		return nil, fmt.Errorf("abi %d, expected %d", version, hostsNativeABIVersion)
	}

	lib := &hostsNativeLib{}
	purego.RegisterLibFunc(&lib.newTable, handle, "diting_hosts_new")
	purego.RegisterLibFunc(&lib.free, handle, "diting_hosts_free")
	purego.RegisterLibFunc(&lib.freeBytes, handle, "diting_hosts_free_bytes")
	purego.RegisterLibFunc(&lib.info, handle, "diting_hosts_info")
	purego.RegisterLibFunc(&lib.lookup, handle, "diting_hosts_lookup")
	purego.RegisterLibFunc(&lib.contains, handle, "diting_hosts_contains")
	purego.RegisterLibFunc(&lib.ptr, handle, "diting_hosts_ptr")
	purego.RegisterLibFunc(&lib.reverse, handle, "diting_hosts_reverse")
	purego.RegisterLibFunc(&lib.parseArpa, handle, "diting_hosts_parse_arpa")
	return lib, nil
}
