//go:build windows

// fd_windows.go keeps `go test ./...` runnable on Windows. The TUN data plane
// never runs there, so descriptor duplication is a deliberate no-op.
package tunnel

// dupFd returns the descriptor unchanged on Windows.
func dupFd(fd int) (int, error) {
	return fd, nil
}
