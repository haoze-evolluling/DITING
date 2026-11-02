//go:build !windows

// fd_unix.go duplicates the TUN file descriptor with the platform syscall.
package tunnel

import "syscall"

// dupFd returns a new descriptor referring to the same open file.
func dupFd(fd int) (int, error) {
	return syscall.Dup(fd)
}
