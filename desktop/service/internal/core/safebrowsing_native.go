package core

// safebrowsing_native.go loads the Rust Safe Browsing kernel (rust/diting-safebrowsing-core) and
// drives it through the C ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust owns host canonicalization and validation, the SHA-256 set of the
// host and its parents, the query name built from the 2-byte prefixes, the parsing of the 64-hex
// TXT answers and the prefix-keyed LRU with its TTL. Go keeps what needs a Go callback or a
// `dns.Msg`: the resolver call, the timeout, the fail-open policy, the counters and the log lines.
//
// The kernel is required: a missing library fails `NewSafeBrowsingEngine`, which fails service
// startup. There is no second implementation in Go — a silent one would turn the protection off
// while the UI still showed it as enabled.
//
// Loading is pure Go (syscall.LazyDLL on Windows, purego elsewhere), so the module stays
// CGO_ENABLED=0 and the existing cross-compiles keep working. The library ships next to the
// service binary (Windows installer) or in /usr/lib/diting (deb), and `cargo build --release` in
// rust/ is enough for `go test`.

import (
	"fmt"
	"log"
	"runtime"
	"sync"
	"time"
	"unsafe"
)

// sbNativeABIVersion must match `ABI_VERSION` in rust/diting-safebrowsing-core/src/ffi.rs.
const sbNativeABIVersion = 1

// Payload layout and status codes of the kernel; keep in sync with src/{payload,ffi}.rs.
const (
	sbPayloadLayoutVersion = 1
	sbHashSize             = 32

	sbPlanFlagEmpty   = 1 << 0
	sbPlanFlagFound   = 1 << 1
	sbPlanFlagBlocked = 1 << 2

	sbPlanSkip          = 0
	sbPlanOK            = 1
	sbApplyBlock        = 1
	sbApplyBadRequest   = 2
	sbServiceIDMalware  = 0
	sbServiceIDParental = 1
	sbNativeLibraryTag  = "diting_safebrowsing_core"
)

// sbNativeLib is one loaded kernel: the entry points the Go side needs.
type sbNativeLib struct {
	newEngine func(cacheSize int64, cacheTTLMs int64, out *unsafe.Pointer) uint32
	free      func(handle unsafe.Pointer)
	freeBytes func(pointer unsafe.Pointer, length uintptr)
	configure func(handle unsafe.Pointer, cacheSize int64, cacheTTLMs int64)
	plan      func(handle unsafe.Pointer, service uint32, host unsafe.Pointer, hostLen uintptr,
		nowMs int64, outPtr *unsafe.Pointer, outLen *uintptr) uint32
	apply func(handle unsafe.Pointer, request unsafe.Pointer, requestLen uintptr,
		nowMs int64) uint32
}

var (
	sbNativeOnce   sync.Once
	sbNativeShared *sbNativeLib
	sbNativeErr    error
)

// sbNativeLibraryName is the file name the loader looks for on this platform.
func sbNativeLibraryName() string {
	return nativeLibraryFile(sbNativeLibraryTag)
}

// sbNativeLibraryCandidates probes the packaged locations first, then a local `cargo build` output
// so `go test` works without installing anything.
func sbNativeLibraryCandidates() []string {
	return nativeLibraryCandidates("DITING_SAFEBROWSING_CORE_LIB", sbNativeLibraryTag)
}

func loadSBNativeLibrary() (*sbNativeLib, error) {
	return loadNativeLibrary("DITING_SAFEBROWSING_CORE_LIB", sbNativeLibraryTag, "safebrowsing kernel",
		loadSBLibrary)
}

// sbKernel returns the loaded library; the failure is kept so every engine reports the same reason
// instead of retrying the probe.
func sbKernel() (*sbNativeLib, error) {
	sbNativeOnce.Do(func() {
		sbNativeShared, sbNativeErr = loadSBNativeLibrary()
	})
	if sbNativeErr != nil {
		return nil, sbNativeErr
	}
	return sbNativeShared, nil
}

// sbNativeHandle owns one Rust engine: both services' caches.
type sbNativeHandle struct {
	lib     *sbNativeLib
	pointer unsafe.Pointer
}

func newSBNativeHandle(cacheSize int, cacheTTLSeconds int) (*sbNativeHandle, error) {
	lib, err := sbKernel()
	if err != nil {
		return nil, err
	}
	var pointer unsafe.Pointer
	if status := lib.newEngine(int64(cacheSize), int64(cacheTTLSeconds)*1000, &pointer); status != 1 || pointer == nil {
		return nil, fmt.Errorf("safebrowsing kernel could not create a handle (status %d)", status)
	}
	return &sbNativeHandle{lib: lib, pointer: pointer}, nil
}

func (h *sbNativeHandle) configure(cacheSize int, cacheTTLSeconds int) {
	if h == nil || h.pointer == nil {
		return
	}
	h.lib.configure(h.pointer, int64(cacheSize), int64(cacheTTLSeconds)*1000)
}

// sbPlan is what one service still needs, or already answered (see src/engine.rs).
type sbPlan struct {
	empty    bool
	found    bool
	blocked  bool
	hashes   [][sbHashSize]byte
	question string
}

// plan normalizes the host inside the kernel; ok=false means "no verdict for this host".
func (h *sbNativeHandle) plan(service uint8, host string) (sbPlan, bool) {
	if h == nil || h.pointer == nil {
		return sbPlan{}, false
	}
	var hostPtr unsafe.Pointer
	if len(host) > 0 {
		hostPtr = unsafe.Pointer(unsafe.StringData(host))
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := h.lib.plan(
		h.pointer,
		uint32(service),
		hostPtr,
		uintptr(len(host)),
		time.Now().UnixMilli(),
		&out,
		&outLen,
	)
	runtime.KeepAlive(host)
	if status == sbPlanSkip {
		return sbPlan{}, false
	}
	if status != sbPlanOK {
		log.Printf("[SafeBrowsing] 内核返回未知状态 %d，本次查询按放行处理", status)
		return sbPlan{}, false
	}
	payload := copyNativePayload(h.lib.freeBytes, out, outLen)
	decoded, err := decodeSBPlan(payload)
	if err != nil {
		log.Printf("[SafeBrowsing] 内核计划载荷无法解析: %v（本次查询按放行处理）", err)
		return sbPlan{}, false
	}
	return decoded, true
}

// apply stores the answer for the queried digests and reports whether any of them is listed.
func (h *sbNativeHandle) apply(service uint8, queried [][sbHashSize]byte, received []string) bool {
	if h == nil || h.pointer == nil {
		return false
	}
	request := encodeSBApplyRequest(service, queried, received)
	var requestPtr unsafe.Pointer
	if len(request) > 0 {
		requestPtr = unsafe.Pointer(&request[0])
	}
	status := h.lib.apply(h.pointer, requestPtr, uintptr(len(request)), time.Now().UnixMilli())
	runtime.KeepAlive(request)
	switch status {
	case sbApplyBlock:
		return true
	case sbApplyBadRequest:
		log.Printf("[SafeBrowsing] 内核拒绝了本次应答载荷，按未命中处理")
		return false
	default:
		return false
	}
}

func (h *sbNativeHandle) free() {
	if h == nil || h.pointer == nil {
		return
	}
	h.lib.free(h.pointer)
	h.pointer = nil
}

// copyNativePayload copies a payload out of a kernel and frees it.
func copyNativePayload(free func(pointer unsafe.Pointer, length uintptr), pointer unsafe.Pointer,
	length uintptr) []byte {
	if pointer == nil {
		return nil
	}
	defer free(pointer, length)
	if length == 0 {
		return nil
	}
	payload := make([]byte, int(length))
	copy(payload, unsafe.Slice((*byte)(pointer), int(length)))
	return payload
}

// encodeSBApplyRequest writes the layout described in rust/diting-safebrowsing-core/src/payload.rs.
func encodeSBApplyRequest(service uint8, queried [][sbHashSize]byte, received []string) []byte {
	size := 3 + len(queried)*sbHashSize + 2
	for _, text := range received {
		size += 2 + len(text)
	}
	request := make([]byte, 0, size)
	request = append(request, sbPayloadLayoutVersion, service, byte(len(queried)))
	for _, hash := range queried {
		request = append(request, hash[:]...)
	}
	request = appendUint16(request, uint16(len(received)))
	for _, text := range received {
		request = appendUint16(request, uint16(len(text)))
		request = append(request, text...)
	}
	return request
}

func appendUint16(buffer []byte, value uint16) []byte {
	return append(buffer, byte(value), byte(value>>8))
}

// decodeSBPlan reads the plan payload (see payload.rs).
func decodeSBPlan(payload []byte) (sbPlan, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return sbPlan{}, err
	}
	if layout != sbPayloadLayoutVersion {
		return sbPlan{}, fmt.Errorf("plan layout %d, expected %d", layout, sbPayloadLayoutVersion)
	}
	flags, err := reader.u8()
	if err != nil {
		return sbPlan{}, err
	}
	count, err := reader.u8()
	if err != nil {
		return sbPlan{}, err
	}
	hashes := make([][sbHashSize]byte, 0, int(count))
	for i := 0; i < int(count); i++ {
		raw, err := reader.bytes(sbHashSize)
		if err != nil {
			return sbPlan{}, err
		}
		var hash [sbHashSize]byte
		copy(hash[:], raw)
		hashes = append(hashes, hash)
	}
	question, err := reader.text()
	if err != nil {
		return sbPlan{}, err
	}
	if remaining := reader.remaining(); remaining != 0 {
		return sbPlan{}, fmt.Errorf("plan payload has %d trailing bytes", remaining)
	}
	return sbPlan{
		empty:    flags&sbPlanFlagEmpty != 0,
		found:    flags&sbPlanFlagFound != 0,
		blocked:  flags&sbPlanFlagBlocked != 0,
		hashes:   hashes,
		question: question,
	}, nil
}
