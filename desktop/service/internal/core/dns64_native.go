package core

// dns64_native.go loads the Rust DNS64 kernel (rust/diting-dns64-core) and drives it through the C
// ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust owns RFC 6052 embedding, the RFC 6147 exclusion set, CIDR parsing with
// `net.ParseCIDR`'s accept/reject outcomes, and the `HasValidAAAARecords` decision. Go keeps what
// needs the resolver or `dns.Msg`: querying A records, the minimum-TTL walk over A / CNAME / DNAME
// answers, appending the aliases to the response, and building the `dns.AAAA` records.
//
// The kernel is required. A missing library fails `NewDNS64Synthesizer`, which fails service
// startup. A *bad prefix* stays a warning, exactly as before the move: that is a configuration
// mistake the user has to fix through the UI, and refusing to start would take the UI with it.
//
// Loading is pure Go (syscall.LazyDLL on Windows, purego elsewhere), so the module stays
// CGO_ENABLED=0 and the existing cross-compiles keep working.

import (
	"errors"
	"fmt"
	"net"
	"runtime"
	"strings"
	"sync"
	"unsafe"
)

// dns64NativeABIVersion must match `ABI_VERSION` in rust/diting-dns64-core/src/ffi.rs.
const dns64NativeABIVersion = 1

// Payload layout and status codes of the kernel; keep in sync with src/payload.rs and src/ffi.rs.
const (
	dns64PayloadLayoutVersion = 1
	dns64NativeLibraryTag     = "diting_dns64_core"

	dns64StatusOK           = 0
	dns64StatusBadArgument  = 1
	dns64StatusBadPayload   = 2
	dns64StatusPrefixParse  = 3
	dns64StatusPrefixLength = 4
)

// dns64NativeLib is one loaded kernel: the entry points the Go side needs.
type dns64NativeLib struct {
	newEngine func(enabled uint8, prefixes unsafe.Pointer, prefixesLen uintptr,
		out *unsafe.Pointer, outIndex *uint32) uint32
	free        func(handle unsafe.Pointer)
	freeBytes   func(pointer unsafe.Pointer, length uintptr)
	embed       func(handle unsafe.Pointer, v4 unsafe.Pointer, v4Len uintptr, out unsafe.Pointer) uint32
	embedNet    func(prefix unsafe.Pointer, ones uint8, v4 unsafe.Pointer, v4Len uintptr,
		out unsafe.Pointer) uint32
	synthesize func(handle unsafe.Pointer, v4 unsafe.Pointer, v4Len uintptr,
		outPtr *unsafe.Pointer, outLen *uintptr) uint32
	excluded func(handle unsafe.Pointer, address unsafe.Pointer, addressLen uintptr,
		out *uint8) uint32
	hasValid func(handle unsafe.Pointer, data unsafe.Pointer, dataLen uintptr, out *uint8) uint32
}

var (
	dns64NativeOnce   sync.Once
	dns64NativeShared *dns64NativeLib
	dns64NativeErr    error
)

func loadDNS64NativeLibrary() (*dns64NativeLib, error) {
	return loadNativeLibrary("DITING_DNS64_CORE_LIB", dns64NativeLibraryTag, "dns64 kernel",
		loadDNS64Library)
}

// dns64Kernel returns the loaded library; the failure is kept so every call reports the same
// reason instead of retrying the probe.
func dns64Kernel() (*dns64NativeLib, error) {
	dns64NativeOnce.Do(func() {
		dns64NativeShared, dns64NativeErr = loadDNS64NativeLibrary()
	})
	if dns64NativeErr != nil {
		return nil, dns64NativeErr
	}
	return dns64NativeShared, nil
}

// dns64PrefixConfigError marks a rejected prefix, so the caller can tell a configuration mistake
// (warn, keep serving) from a missing or broken kernel (fail startup).
type dns64PrefixConfigError struct {
	index int
	err   error
}

func (e *dns64PrefixConfigError) Error() string { return e.err.Error() }
func (e *dns64PrefixConfigError) Unwrap() error { return e.err }

// IsDNS64ConfigError reports whether err came from the configured prefixes rather than from a
// missing or mismatched kernel. The caller keeps serving on a config mistake — the user has to fix
// it through the UI, which needs the service running.
func IsDNS64ConfigError(err error) bool {
	var target *dns64PrefixConfigError
	return errors.As(err, &target)
}

// newDNS64ConfigError rebuilds the message the old constructor produced, quoting the trimmed
// prefix the user actually typed.
func newDNS64ConfigError(prefixes []string, index int, status uint32) error {
	text := ""
	if index >= 0 && index < len(prefixes) {
		text = strings.TrimSpace(prefixes[index])
	}
	if status == dns64StatusPrefixParse {
		parseErr := &net.ParseError{Type: "CIDR address", Text: text}
		return &dns64PrefixConfigError{
			index: index,
			err:   fmt.Errorf("解析 DNS64 前缀 %q 失败: %w", text, parseErr),
		}
	}
	return &dns64PrefixConfigError{
		index: index,
		err: fmt.Errorf("RFC 6052 规范仅支持 /32, /40, /48, /56, /64, /96 前缀长度，不支持 %s",
			text),
	}
}

// dns64NativeEngine owns one synthesizer: the prefixes and exclusion set for one configuration
// generation. `UpdateConfig` builds a new one and swaps it, like the other kernels.
type dns64NativeEngine struct {
	lib     *dns64NativeLib
	pointer unsafe.Pointer
}

func buildDNS64NativeEngine(enabled bool, prefixes []string) (*dns64NativeEngine, error) {
	lib, err := dns64Kernel()
	if err != nil {
		return nil, err
	}
	payload := encodeDNS64Prefixes(prefixes)
	var pointer unsafe.Pointer
	var index uint32
	status := lib.newEngine(
		boolByte(enabled),
		unsafe.Pointer(&payload[0]),
		uintptr(len(payload)),
		&pointer,
		&index,
	)
	switch status {
	case dns64StatusOK:
	case dns64StatusPrefixParse, dns64StatusPrefixLength:
		return nil, newDNS64ConfigError(prefixes, int(index), status)
	default:
		return nil, fmt.Errorf("dns64 kernel could not build a synthesizer (status %d)", status)
	}
	if pointer == nil {
		return nil, errors.New("dns64 kernel returned an empty handle")
	}
	return &dns64NativeEngine{lib: lib, pointer: pointer}, nil
}

// embed is `MapIPv4ToIPv6` behind the first configured prefix.
func (e *dns64NativeEngine) embed(v4 []byte) ([]byte, bool) {
	if e == nil || e.pointer == nil || len(v4) != net.IPv4len {
		return nil, false
	}
	out := make([]byte, net.IPv6len)
	status := e.lib.embed(e.pointer, unsafe.Pointer(&v4[0]), uintptr(len(v4)), unsafe.Pointer(&out[0]))
	runtime.KeepAlive(v4)
	if status != dns64StatusOK {
		return nil, false
	}
	return out, true
}

// synthesize returns the AAAA addresses for one A record: one per configured prefix, in order.
func (e *dns64NativeEngine) synthesize(v4 []byte) ([][]byte, error) {
	if e == nil || e.pointer == nil {
		return nil, errors.New("dns64 kernel handle is not available")
	}
	var v4Ptr unsafe.Pointer
	if len(v4) > 0 {
		v4Ptr = unsafe.Pointer(&v4[0])
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := e.lib.synthesize(e.pointer, v4Ptr, uintptr(len(v4)), &out, &outLen)
	runtime.KeepAlive(v4)
	if status != dns64StatusOK {
		return nil, fmt.Errorf("dns64 kernel could not synthesize (status %d)", status)
	}
	return decodeDNS64Result(copyNativePayload(e.lib.freeBytes, out, outLen))
}

// excluded is `IsExcluded` for one address of any `net.IP` width.
func (e *dns64NativeEngine) excluded(address []byte) (bool, error) {
	if e == nil || e.pointer == nil {
		return false, errors.New("dns64 kernel handle is not available")
	}
	var pointer unsafe.Pointer
	if len(address) > 0 {
		pointer = unsafe.Pointer(&address[0])
	}
	var out uint8
	status := e.lib.excluded(e.pointer, pointer, uintptr(len(address)), &out)
	runtime.KeepAlive(address)
	if status != dns64StatusOK {
		return false, fmt.Errorf("dns64 kernel could not check the address (status %d)", status)
	}
	return out == 1, nil
}

// hasValid is `HasValidAAAARecords` over the addresses Go already extracted.
func (e *dns64NativeEngine) hasValid(addresses [][]byte) (bool, error) {
	if e == nil || e.pointer == nil {
		return false, errors.New("dns64 kernel handle is not available")
	}
	payload := encodeDNS64Addresses(addresses)
	var out uint8
	status := e.lib.hasValid(e.pointer, unsafe.Pointer(&payload[0]), uintptr(len(payload)), &out)
	if status != dns64StatusOK {
		return false, fmt.Errorf("dns64 kernel could not check the answer (status %d)", status)
	}
	return out == 1, nil
}

func (e *dns64NativeEngine) free() {
	if e == nil || e.pointer == nil {
		return
	}
	e.lib.free(e.pointer)
	e.pointer = nil
}

// embedIPv4InPrefix is `EmbedIPv4InIPv6` for the package-level helper: the prefix bytes Go already
// holds plus its mask length, so a collapsed `*net.IPNet` (`::ffff:0:0/96`) embeds exactly as it
// did before the move.
func embedIPv4InPrefix(prefix net.IP, ones int, v4 []byte) ([]byte, bool) {
	lib, err := dns64Kernel()
	if err != nil {
		return nil, false
	}
	if len(prefix) != net.IPv6len || len(v4) != net.IPv4len {
		return nil, false
	}
	out := make([]byte, net.IPv6len)
	status := lib.embedNet(
		unsafe.Pointer(&prefix[0]),
		uint8(ones),
		unsafe.Pointer(&v4[0]),
		uintptr(len(v4)),
		unsafe.Pointer(&out[0]),
	)
	runtime.KeepAlive(prefix)
	runtime.KeepAlive(v4)
	if status != dns64StatusOK {
		return nil, false
	}
	return out, true
}

// encodeDNS64Prefixes writes the layout described in rust/diting-dns64-core/src/payload.rs.
func encodeDNS64Prefixes(prefixes []string) []byte {
	size := 3
	for _, prefix := range prefixes {
		size += 4 + len(prefix)
	}
	payload := make([]byte, 0, size)
	payload = append(payload, dns64PayloadLayoutVersion)
	payload = append(payload, byte(len(prefixes)), byte(len(prefixes)>>8))
	for _, prefix := range prefixes {
		payload = appendUint32(payload, uint32(len(prefix)))
		payload = append(payload, prefix...)
	}
	return payload
}

// encodeDNS64Addresses writes the address list `has_valid` reads: width byte plus bytes.
func encodeDNS64Addresses(addresses [][]byte) []byte {
	size := 3
	for _, address := range addresses {
		size += 1 + len(address)
	}
	payload := make([]byte, 0, size)
	payload = append(payload, dns64PayloadLayoutVersion)
	payload = append(payload, byte(len(addresses)), byte(len(addresses)>>8))
	for _, address := range addresses {
		payload = append(payload, byte(len(address)))
		payload = append(payload, address...)
	}
	return payload
}

// decodeDNS64Result reads the synthesized 16-byte addresses (see payload.rs).
func decodeDNS64Result(payload []byte) ([][]byte, error) {
	reader := &payloadReader{data: payload}
	if err := expectDNS64Layout(reader, "result"); err != nil {
		return nil, err
	}
	count, err := reader.u8()
	if err != nil {
		return nil, err
	}
	addresses := make([][]byte, 0, count)
	for index := uint8(0); index < count; index++ {
		raw, err := reader.bytes(net.IPv6len)
		if err != nil {
			return nil, err
		}
		address := make([]byte, len(raw))
		copy(address, raw)
		addresses = append(addresses, address)
	}
	if err := expectPayloadEnd(reader, "result"); err != nil {
		return nil, err
	}
	return addresses, nil
}

// expectDNS64Layout rejects a payload written by a different build.
func expectDNS64Layout(reader *payloadReader, what string) error {
	layout, err := reader.u8()
	if err != nil {
		return err
	}
	if layout != dns64PayloadLayoutVersion {
		return fmt.Errorf("%s layout %d, expected %d", what, layout, dns64PayloadLayoutVersion)
	}
	return nil
}

func boolByte(value bool) uint8 {
	if value {
		return 1
	}
	return 0
}
