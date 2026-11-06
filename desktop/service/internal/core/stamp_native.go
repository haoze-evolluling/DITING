package core

// stamp_native.go loads the Rust DNS-stamp kernel (rust/diting-stamp-core) and drives it through
// the C ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust owns the byte-exact stamp parser, the address/hostname validation and
// the strings derived from a stamp (URL() / Server()). Go keeps the value type the IPC layer and
// the provider builder consume, plus the pin adapter.
//
// The kernel is required. A missing library, a stale ABI or a rejected payload fails
// ParseServerStamp, which fails provider configuration: there is no second parser left, and a
// silent one would only hide the difference until it changed an upstream address.
//
// Loading is pure Go (syscall.LazyDLL on Windows, purego elsewhere), so the module stays
// CGO_ENABLED=0 and the existing cross-compiles keep working. The library ships next to the service binary (Windows
// installer) or in /usr/lib/diting (deb), and `cargo build --release` in rust/ is enough for
// `go test`.

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"
)

// stampNativeABIVersion must match `ABI_VERSION` in rust/diting-stamp-core/src/ffi.rs.
const stampNativeABIVersion = 1

// Payload layout and status codes of `diting_stamp_parse`; keep in sync with src/ffi.rs.
const (
	stampPayloadLayoutVersion = 1
	stampPayloadHashLen       = 32

	stampStatusOK       = 0
	stampStatusRejected = 1
)

// stampNativeLib is one loaded kernel: the two entry points the Go side needs.
type stampNativeLib struct {
	parse func(input unsafe.Pointer, inputLen uintptr, outPtr *unsafe.Pointer, outLen *uintptr) uint32
	free  func(pointer unsafe.Pointer, length uintptr)
}

var (
	stampNativeOnce   sync.Once
	stampNativeShared *stampNativeLib
	stampNativeErr    error
)

func stampNativeLibraryName() string {
	switch runtime.GOOS {
	case "windows":
		return "diting_stamp_core.dll"
	case "darwin":
		return "libditing_stamp_core.dylib"
	default:
		return "libditing_stamp_core.so"
	}
}

// stampNativeLibraryCandidates probes the packaged locations first, then a local `cargo build`
// output so `go test` works without installing anything.
func stampNativeLibraryCandidates() []string {
	if explicit := os.Getenv("DITING_STAMP_CORE_LIB"); explicit != "" {
		// An explicit path is the only candidate: a typo must fail loudly, not fall through.
		return []string{explicit}
	}
	name := stampNativeLibraryName()
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

func loadStampNativeLibrary() (*stampNativeLib, error) {
	candidates := stampNativeLibraryCandidates()
	lastErr := fmt.Errorf("stamp kernel not found in %v", candidates)
	for _, candidate := range candidates {
		lib, err := loadStampLibrary(candidate)
		if err != nil {
			lastErr = fmt.Errorf("%s: %w", candidate, err)
			continue
		}
		return lib, nil
	}
	return nil, lastErr
}

// stampKernel returns the loaded library; the failure is kept so every stamp reports the same
// reason instead of retrying the probe.
func stampKernel() (*stampNativeLib, error) {
	stampNativeOnce.Do(func() {
		stampNativeShared, stampNativeErr = loadStampNativeLibrary()
	})
	if stampNativeErr != nil {
		return nil, stampNativeErr
	}
	return stampNativeShared, nil
}

// parseStampNative parses one stamp inside the kernel and returns the payload of a successful
// parse; a rejected stamp comes back as its original message.
func parseStampNative(text string) ([]byte, error) {
	lib, err := stampKernel()
	if err != nil {
		return nil, err
	}

	var input unsafe.Pointer
	if len(text) > 0 {
		input = unsafe.Pointer(unsafe.StringData(text))
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := lib.parse(input, uintptr(len(text)), &out, &outLen)
	runtime.KeepAlive(text)

	payload := make([]byte, 0)
	if out != nil && outLen > 0 {
		payload = make([]byte, int(outLen))
		copy(payload, unsafe.Slice((*byte)(out), int(outLen)))
	}
	if out != nil {
		lib.free(out, outLen)
	}

	switch status {
	case stampStatusOK:
		return payload, nil
	case stampStatusRejected:
		if len(payload) == 0 {
			return nil, errors.New("stamp rejected by the native kernel")
		}
		return nil, errors.New(string(payload))
	default:
		return nil, fmt.Errorf("stamp kernel returned status %d", status)
	}
}

// stampPayloadReader walks the payload in the order src/ffi.rs writes it.
type stampPayloadReader struct {
	data []byte
	pos  int
}

func (r *stampPayloadReader) remaining() int { return len(r.data) - r.pos }

func (r *stampPayloadReader) u8() (uint8, error) {
	if r.remaining() < 1 {
		return 0, errors.New("stamp payload is truncated (byte)")
	}
	value := r.data[r.pos]
	r.pos++
	return value, nil
}

func (r *stampPayloadReader) u16() (int, error) {
	if r.remaining() < 2 {
		return 0, errors.New("stamp payload is truncated (u16)")
	}
	value := int(r.data[r.pos]) | int(r.data[r.pos+1])<<8
	r.pos += 2
	return value, nil
}

func (r *stampPayloadReader) u64() (uint64, error) {
	if r.remaining() < 8 {
		return 0, errors.New("stamp payload is truncated (u64)")
	}
	var value uint64
	for shift := 0; shift < 64; shift += 8 {
		value |= uint64(r.data[r.pos]) << uint(shift)
		r.pos++
	}
	return value, nil
}

func (r *stampPayloadReader) text() (string, error) {
	length, err := r.u16()
	if err != nil {
		return "", err
	}
	if r.remaining() < length {
		return "", errors.New("stamp payload is truncated (string)")
	}
	value := string(r.data[r.pos : r.pos+length])
	r.pos += length
	return value, nil
}

func (r *stampPayloadReader) bytes(length int) ([]byte, error) {
	if r.remaining() < length {
		return nil, errors.New("stamp payload is truncated (bytes)")
	}
	value := r.data[r.pos : r.pos+length]
	r.pos += length
	return value, nil
}

// decodeStampPayload turns the kernel payload into the value type the rest of the service uses.
func decodeStampPayload(payload []byte) (*ServerStamp, error) {
	reader := &stampPayloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return nil, err
	}
	if layout != stampPayloadLayoutVersion {
		return nil, fmt.Errorf("stamp payload layout %d, expected %d", layout, stampPayloadLayoutVersion)
	}
	proto, err := reader.u8()
	if err != nil {
		return nil, err
	}
	props, err := reader.u64()
	if err != nil {
		return nil, err
	}

	fields := make([]string, 0, 6)
	for i := 0; i < 6; i++ {
		value, err := reader.text()
		if err != nil {
			return nil, err
		}
		fields = append(fields, value)
	}

	pinCount, err := reader.u16()
	if err != nil {
		return nil, err
	}
	hashes := make([][]byte, 0, pinCount)
	for i := 0; i < pinCount; i++ {
		hash, err := reader.bytes(stampPayloadHashLen)
		if err != nil {
			return nil, err
		}
		hashes = append(hashes, hash)
	}

	bootstrapCount, err := reader.u16()
	if err != nil {
		return nil, err
	}
	bootstrapIPs := make([]string, 0, bootstrapCount)
	for i := 0; i < bootstrapCount; i++ {
		value, err := reader.text()
		if err != nil {
			return nil, err
		}
		bootstrapIPs = append(bootstrapIPs, value)
	}

	if remaining := reader.remaining(); remaining != 0 {
		return nil, fmt.Errorf("stamp payload has %d trailing bytes", remaining)
	}

	return &ServerStamp{
		Proto:         StampProtoType(proto),
		Props:         StampProperties(props),
		ServerAddrStr: fields[1],
		Hashes:        hashes,
		ProviderName:  fields[2],
		Path:          fields[3],
		BootstrapIPs:  bootstrapIPs,
		derivedURL:    fields[4],
		derivedServer: fields[5],
		protocol:      DNSProtocol(fields[0]),
	}, nil
}
