//go:build windows

// mmap_windows.go keeps `go test ./...` runnable on a Windows developer machine.
//
// The shipped Android builds are Linux/arm64 and use the mmap path; Windows only
// needs the loading, magic/version and layout checks to behave the same, so the
// file is read into memory instead of being mapped.
package tunnel

import (
	"io"
	"os"
)

func mapFileReadOnly(fd uintptr, size int) ([]byte, error) {
	f := os.NewFile(fd, "mmap_window")
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	data := make([]byte, size)
	if _, err := io.ReadFull(f, data); err != nil {
		return nil, err
	}
	return data, nil
}

func unmapFile(data []byte) {
	// Nothing to release: the bytes are owned by the Go heap.
}
