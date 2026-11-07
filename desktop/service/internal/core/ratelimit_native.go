package core

// ratelimit_native.go loads the Rust rate-limit kernel (rust/diting-ratelimit-core) and drives it
// through the C ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust owns the token bucket, the configuration normalisation, exemption
// parsing (`net.ParseCIDR` / `net.ParseIP` acceptance), the prefix aggregation that maps a client to
// a bucket and the capacity eviction. Go keeps what needs the Go runtime: the janitor goroutine, the
// clock (passed as `now_ns` on every call), `net.IP` bytes, the `IsEnabled` fast path the middleware
// reads, and the JSON config shape the IPC layer persists.
//
// The kernel is required. A missing library fails `NewRateLimiter`, which fails service startup:
// a limiter that silently allows everything would leave a protection the user switched on doing
// nothing.
//
// Loading is pure Go (syscall.LazyDLL on Windows, purego elsewhere), so the module stays
// CGO_ENABLED=0 and the existing cross-compiles keep working.

import (
	"encoding/binary"
	"fmt"
	"math"
	"runtime"
	"sync"
	"unsafe"
)

// rateLimitNativeABIVersion must match `ABI_VERSION` in rust/diting-ratelimit-core/src/ffi.rs.
const rateLimitNativeABIVersion = 1

// Payload layout and status codes of the kernel; keep in sync with src/payload.rs and src/ffi.rs.
const (
	rateLimitPayloadLayoutVersion = 1
	rateLimitNativeLibraryTag     = "diting_ratelimit_core"

	rateLimitStatusOK          = 1
	rateLimitStatusBadArgument = 0

	// rateLimitAllow / rateLimitDeny / rateLimitBadArgument are `diting_ratelimit_allow`'s results.
	rateLimitAllow       = 1
	rateLimitDeny        = 0
	rateLimitBadArgument = -1
)

// rateLimitNativeLib is one loaded kernel: the entry points the Go side needs.
type rateLimitNativeLib struct {
	newLimiter func(config unsafe.Pointer, configLen uintptr, out *unsafe.Pointer) uint32
	configure  func(handle unsafe.Pointer, config unsafe.Pointer, configLen uintptr) uint32
	free       func(handle unsafe.Pointer)
	freeBytes  func(pointer unsafe.Pointer, length uintptr)
	allow      func(handle unsafe.Pointer, address unsafe.Pointer, addressLen uintptr,
		nowNs int64, maxBuckets uint32) int32
	cleanup func(handle unsafe.Pointer, nowNs int64)
	info    func(handle unsafe.Pointer, outPtr *unsafe.Pointer, outLen *uintptr) uint32
}

var (
	rateLimitNativeOnce   sync.Once
	rateLimitNativeShared *rateLimitNativeLib
	rateLimitNativeErr    error
)

func loadRateLimitNativeLibrary() (*rateLimitNativeLib, error) {
	return loadNativeLibrary("DITING_RATELIMIT_CORE_LIB", rateLimitNativeLibraryTag,
		"ratelimit kernel", loadRateLimitLibrary)
}

// rateLimitKernel returns the loaded library; the failure is kept so every limiter reports the same
// reason instead of retrying the probe.
func rateLimitKernel() (*rateLimitNativeLib, error) {
	rateLimitNativeOnce.Do(func() {
		rateLimitNativeShared, rateLimitNativeErr = loadRateLimitNativeLibrary()
	})
	if rateLimitNativeErr != nil {
		return nil, rateLimitNativeErr
	}
	return rateLimitNativeShared, nil
}

// rateLimitInfo is the normalised config and the table sizes the kernel reports back.
type rateLimitInfo struct {
	Enabled    bool
	Rate       float64
	Burst      int
	IPv4Prefix int
	IPv6Prefix int
	Buckets    uint32
	ExemptIPs  uint32
	ExemptNets uint32
}

// rateLimitNativeLimiter owns one Rust limiter. `UpdateConfig` mutates it in place, which is what
// the Go implementation did with its maps; the handle lives until `Close`.
type rateLimitNativeLimiter struct {
	lib     *rateLimitNativeLib
	pointer unsafe.Pointer
}

func buildRateLimitNativeLimiter(cfg RateLimitConfig) (*rateLimitNativeLimiter, error) {
	lib, err := rateLimitKernel()
	if err != nil {
		return nil, err
	}
	payload := encodeRateLimitConfig(cfg)
	var pointer unsafe.Pointer
	status := lib.newLimiter(unsafe.Pointer(&payload[0]), uintptr(len(payload)), &pointer)
	if status != rateLimitStatusOK || pointer == nil {
		return nil, fmt.Errorf("ratelimit kernel could not build a limiter (status %d)", status)
	}
	return &rateLimitNativeLimiter{lib: lib, pointer: pointer}, nil
}

// configure applies a new configuration; the buckets and their tokens survive.
func (l *rateLimitNativeLimiter) configure(cfg RateLimitConfig) error {
	if l == nil || l.pointer == nil {
		return fmt.Errorf("ratelimit kernel is not available")
	}
	payload := encodeRateLimitConfig(cfg)
	status := l.lib.configure(l.pointer, unsafe.Pointer(&payload[0]), uintptr(len(payload)))
	if status != rateLimitStatusOK {
		return fmt.Errorf("ratelimit kernel rejected the configuration (status %d)", status)
	}
	return nil
}

// allow asks for one decision. `address` is a 4- or 16-byte `net.IP` (nil is passed through by the
// caller). An unusable width comes back as `-1` and is allowed: a broken address must never lock a
// client out.
func (l *rateLimitNativeLimiter) allow(address []byte, nowNs int64, maxBuckets int) bool {
	if l == nil || l.pointer == nil || len(address) == 0 {
		return true
	}
	status := l.lib.allow(
		l.pointer,
		unsafe.Pointer(&address[0]),
		uintptr(len(address)),
		nowNs,
		uint32(maxBuckets),
	)
	runtime.KeepAlive(address)
	return status != rateLimitDeny
}

// cleanup runs the kernel's idle sweep.
func (l *rateLimitNativeLimiter) cleanup(nowNs int64) {
	if l == nil || l.pointer == nil {
		return
	}
	l.lib.cleanup(l.pointer, nowNs)
}

// info reports the normalised config and the table sizes (diagnostics and tests).
func (l *rateLimitNativeLimiter) info() (rateLimitInfo, error) {
	if l == nil || l.pointer == nil {
		return rateLimitInfo{}, fmt.Errorf("ratelimit kernel is not available")
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := l.lib.info(l.pointer, &out, &outLen)
	if status != rateLimitStatusOK {
		return rateLimitInfo{}, fmt.Errorf("ratelimit kernel could not describe the limiter (status %d)", status)
	}
	payload := copyNativePayload(l.lib.freeBytes, out, outLen)
	return decodeRateLimitInfo(payload)
}

func (l *rateLimitNativeLimiter) free() {
	if l == nil || l.pointer == nil {
		return
	}
	l.lib.free(l.pointer)
	l.pointer = nil
}

// encodeRateLimitConfig writes the layout described in rust/diting-ratelimit-core/src/payload.rs.
//
// `Rate` travels as its IEEE bits, so a zero/negative/NaN value reaches the kernel exactly as Go
// held it; normalisation is the kernel's job, not the encoder's.
func encodeRateLimitConfig(cfg RateLimitConfig) []byte {
	payload := make([]byte, 0, 33)
	payload = append(payload, rateLimitPayloadLayoutVersion)
	if cfg.Enabled {
		payload = append(payload, 1)
	} else {
		payload = append(payload, 0)
	}
	payload = binary.LittleEndian.AppendUint64(payload, math.Float64bits(cfg.Rate))
	payload = binary.LittleEndian.AppendUint64(payload, uint64(int64(cfg.Burst)))
	payload = binary.LittleEndian.AppendUint64(payload, uint64(int64(cfg.IPv4Prefix)))
	payload = binary.LittleEndian.AppendUint64(payload, uint64(int64(cfg.IPv6Prefix)))
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len(cfg.ExemptIPs)))
	for _, entry := range cfg.ExemptIPs {
		payload = binary.LittleEndian.AppendUint32(payload, uint32(len(entry)))
		payload = append(payload, entry...)
	}
	return payload
}

// decodeRateLimitInfo reads the normalised config and the table sizes (see payload.rs).
func decodeRateLimitInfo(payload []byte) (rateLimitInfo, error) {
	reader := &payloadReader{data: payload}
	if err := expectRateLimitLayout(reader, "info"); err != nil {
		return rateLimitInfo{}, err
	}
	enabled, err := reader.u8()
	if err != nil {
		return rateLimitInfo{}, err
	}
	buckets, err := reader.u32()
	if err != nil {
		return rateLimitInfo{}, err
	}
	exemptIPs, err := reader.u32()
	if err != nil {
		return rateLimitInfo{}, err
	}
	exemptNets, err := reader.u32()
	if err != nil {
		return rateLimitInfo{}, err
	}
	rateBits, err := reader.u64()
	if err != nil {
		return rateLimitInfo{}, err
	}
	burst, err := reader.u64()
	if err != nil {
		return rateLimitInfo{}, err
	}
	ipv4Prefix, err := reader.u8()
	if err != nil {
		return rateLimitInfo{}, err
	}
	ipv6Prefix, err := reader.u8()
	if err != nil {
		return rateLimitInfo{}, err
	}
	if err := expectPayloadEnd(reader, "info"); err != nil {
		return rateLimitInfo{}, err
	}
	return rateLimitInfo{
		Enabled:    enabled == 1,
		Rate:       math.Float64frombits(rateBits),
		Burst:      int(int64(burst)),
		IPv4Prefix: int(ipv4Prefix),
		IPv6Prefix: int(ipv6Prefix),
		Buckets:    buckets,
		ExemptIPs:  exemptIPs,
		ExemptNets: exemptNets,
	}, nil
}

// expectRateLimitLayout rejects a payload written by a different build.
func expectRateLimitLayout(reader *payloadReader, what string) error {
	layout, err := reader.u8()
	if err != nil {
		return err
	}
	if layout != rateLimitPayloadLayoutVersion {
		return fmt.Errorf("%s layout %d, expected %d", what, layout, rateLimitPayloadLayoutVersion)
	}
	return nil
}
