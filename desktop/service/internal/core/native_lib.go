package core

// native_lib.go holds what every Rust kernel needs before its entry points can be called: the
// platform file name, the probe order and the "first loadable candidate wins" loop.
//
// The kernels (rust/diting-stamp-core, diting-filter-core, diting-rewrite-core,
// diting-safebrowsing-core, diting-hosts-core) are shipped next to the service
// binary by the Windows installer and into /usr/lib/diting by the deb, and both are loaded with
// pure Go so the module stays CGO_ENABLED=0. The last probe is the local `cargo build` output, which
// is what makes `go test` work without installing anything.
//
// Each kernel keeps its own environment variable (DITING_STAMP_CORE_LIB, DITING_FILTER_CORE_LIB,
// DITING_REWRITE_CORE_LIB, DITING_SAFEBROWSING_CORE_LIB, DITING_HOSTS_CORE_LIB).
// When one is set it is the *only* candidate: a typo must fail loudly instead of silently falling
// back to another copy.

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

// nativeLibraryFile maps a kernel base name to the platform file name.
func nativeLibraryFile(base string) string {
	switch runtime.GOOS {
	case "windows":
		return base + ".dll"
	case "darwin":
		return "lib" + base + ".dylib"
	default:
		return "lib" + base + ".so"
	}
}

// nativeLibraryCandidates lists the paths to probe, most packaged first.
func nativeLibraryCandidates(envVar, base string) []string {
	if explicit := os.Getenv(envVar); explicit != "" {
		return []string{explicit}
	}

	name := nativeLibraryFile(base)
	candidates := make([]string, 0, 6)
	// Packaged layout: next to the service binary (installed by project.nsi / dpkg).
	if executable, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Join(filepath.Dir(executable), name))
	}
	for _, dir := range []string{"/usr/lib/diting", "/usr/local/lib/diting"} {
		candidates = append(candidates, filepath.Join(dir, name))
	}
	for _, profile := range []string{"release", "debug"} {
		candidates = append(candidates, filepath.Join("..", "..", "..", "..", "rust", "target", profile, name))
	}
	return candidates
}

// loadNativeLibrary opens the first candidate that loads and passes its ABI check.
//
// The last error is kept so a missing library reports the paths it tried and the reason each one
// failed, which is the difference between a five-second fix and an afternoon of guessing.
func loadNativeLibrary[T any](envVar, base, label string, open func(string) (*T, error)) (*T, error) {
	candidates := nativeLibraryCandidates(envVar, base)
	lastErr := fmt.Errorf("%s not found in %v", label, candidates)
	for _, candidate := range candidates {
		lib, err := open(candidate)
		if err != nil {
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		return lib, nil
	}
	return nil, lastErr
}

// payloadReader walks a payload in the layout the Rust kernels write (see the payload modules
// in rust/diting-stamp-core and rust/diting-filter-core).
type payloadReader struct {
	data []byte
	pos  int
}

func (r *payloadReader) remaining() int { return len(r.data) - r.pos }

func (r *payloadReader) u8() (uint8, error) {
	if r.remaining() < 1 {
		return 0, errors.New("payload is truncated (byte)")
	}
	value := r.data[r.pos]
	r.pos++
	return value, nil
}

func (r *payloadReader) u16() (int, error) {
	if r.remaining() < 2 {
		return 0, errors.New("payload is truncated (u16)")
	}
	value := int(r.data[r.pos]) | int(r.data[r.pos+1])<<8
	r.pos += 2
	return value, nil
}

func (r *payloadReader) u32() (uint32, error) {
	if r.remaining() < 4 {
		return 0, errors.New("payload is truncated (u32)")
	}
	var value uint32
	for shift := 0; shift < 32; shift += 8 {
		byteValue, err := r.u8()
		if err != nil {
			return 0, err
		}
		value |= uint32(byteValue) << uint(shift)
	}
	return value, nil
}

func (r *payloadReader) u64() (uint64, error) {
	if r.remaining() < 8 {
		return 0, errors.New("payload is truncated (u64)")
	}
	var value uint64
	for shift := 0; shift < 64; shift += 8 {
		value |= uint64(r.data[r.pos]) << uint(shift)
		r.pos++
	}
	return value, nil
}

func (r *payloadReader) text() (string, error) {
	length, err := r.u16()
	if err != nil {
		return "", err
	}
	if r.remaining() < length {
		return "", errors.New("payload is truncated (string)")
	}
	value := string(r.data[r.pos : r.pos+length])
	r.pos += length
	return value, nil
}

// text32 reads a `u32`-length string, the shape the parser payload uses for whole documents.
func (r *payloadReader) text32() (string, error) {
	length, err := r.u32()
	if err != nil {
		return "", err
	}
	if r.remaining() < int(length) {
		return "", errors.New("payload is truncated (long string)")
	}
	value := string(r.data[r.pos : r.pos+int(length)])
	r.pos += int(length)
	return value, nil
}

// texts32 reads a `u16`-counted list of `u32`-length strings.
func (r *payloadReader) texts32() ([]string, error) {
	count, err := r.u16()
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, count)
	for i := 0; i < count; i++ {
		value, err := r.text32()
		if err != nil {
			return nil, err
		}
		out = append(out, value)
	}
	return out, nil
}

func (r *payloadReader) bytes(length int) ([]byte, error) {
	if r.remaining() < length {
		return nil, errors.New("payload is truncated (bytes)")
	}
	value := r.data[r.pos : r.pos+length]
	r.pos += length
	return value, nil
}
