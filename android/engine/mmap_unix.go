//go:build !windows

// mmap_unix.go maps the read-only DTRI rule indexes into memory
// on the targets the app actually ships to.
package tunnel

import (
	"golang.org/x/sys/unix"
)

// mapFileReadOnly maps the already-opened file for read-only access.
func mapFileReadOnly(fd uintptr, size int) ([]byte, error) {
	return unix.Mmap(int(fd), 0, size, unix.PROT_READ, unix.MAP_SHARED)
}

// unmapFile releases a mapping created by mapFileReadOnly.
func unmapFile(data []byte) {
	_ = unix.Munmap(data)
}
