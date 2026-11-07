package core

// hosts_native.go loads the Rust hosts kernel (rust/diting-hosts-core) and drives it through the C
// ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust owns the hosts parser (line comments, Unicode field splitting, the
// interface-zone cut, the address forms `net.ParseIP` accepts), the IPv4 / IPv6 / reverse maps, the
// lookups that answer from them, and the `.in-addr.arpa` / `.ip6.arpa` parsing that the rewrite
// engine shares. Go keeps what needs `dns.RR` or the platform: the system hosts path, the records
// built from the returned addresses, the TTL, and the config fields `UpdateConfig` swaps.
//
// File reading happens inside the kernel (the table is built from a source list of paths and
// inline text), so `Reload` re-reads exactly the paths that were readable last time — the same
// list the Go implementation carried.
//
// The kernel is required: a missing library fails `NewHostsResolver`, which fails service startup.
// There is no second parser in Go — a silent one would drift.
//
// Loading is pure Go (syscall.LazyDLL on Windows, purego elsewhere), so the module stays
// CGO_ENABLED=0 and the existing cross-compiles keep working.

import (
	"errors"
	"fmt"
	"log"
	"net"
	"runtime"
	"sync"
	"unsafe"
)

// hostsNativeABIVersion must match `ABI_VERSION` in rust/diting-hosts-core/src/ffi.rs.
const hostsNativeABIVersion = 1

// Payload layout and status codes of the kernel; keep in sync with src/payload.rs and src/ffi.rs.
const (
	hostsPayloadLayoutVersion = 1
	hostsSourceKindFile       = 0
	hostsSourceKindText       = 1
	hostsNativeLibraryTag     = "diting_hosts_core"
)

// hostsNativeLib is one loaded kernel: the entry points the Go side needs.
type hostsNativeLib struct {
	newTable  func(sources unsafe.Pointer, sourcesLen uintptr, out *unsafe.Pointer) uint32
	free      func(handle unsafe.Pointer)
	freeBytes func(pointer unsafe.Pointer, length uintptr)
	info      func(handle unsafe.Pointer, outPtr *unsafe.Pointer, outLen *uintptr) uint32
	lookup    func(handle unsafe.Pointer, host unsafe.Pointer, hostLen uintptr, qtype uint16,
		outPtr *unsafe.Pointer, outLen *uintptr) uint32
	contains func(handle unsafe.Pointer, host unsafe.Pointer, hostLen uintptr) uint32
	ptr      func(handle unsafe.Pointer, arpa unsafe.Pointer, arpaLen uintptr,
		outPtr *unsafe.Pointer, outLen *uintptr) uint32
	reverse func(handle unsafe.Pointer, address unsafe.Pointer, addressLen uintptr,
		outPtr *unsafe.Pointer, outLen *uintptr) uint32
	parseArpa func(name unsafe.Pointer, nameLen uintptr, outPtr *unsafe.Pointer,
		outLen *uintptr) uint32
}

var (
	hostsNativeOnce   sync.Once
	hostsNativeShared *hostsNativeLib
	hostsNativeErr    error
)

// hostsNativeLibraryName is the file name the loader looks for on this platform.
func hostsNativeLibraryName() string {
	return nativeLibraryFile(hostsNativeLibraryTag)
}

// hostsNativeLibraryCandidates probes the packaged locations first, then a local `cargo build`
// output so `go test` works without installing anything.
func hostsNativeLibraryCandidates() []string {
	return nativeLibraryCandidates("DITING_HOSTS_CORE_LIB", hostsNativeLibraryTag)
}

func loadHostsNativeLibrary() (*hostsNativeLib, error) {
	return loadNativeLibrary("DITING_HOSTS_CORE_LIB", hostsNativeLibraryTag, "hosts kernel",
		loadHostsLibrary)
}

// hostsKernel returns the loaded library; the failure is kept so every resolver reports the same
// reason instead of retrying the probe.
func hostsKernel() (*hostsNativeLib, error) {
	hostsNativeOnce.Do(func() {
		hostsNativeShared, hostsNativeErr = loadHostsNativeLibrary()
	})
	if hostsNativeErr != nil {
		return nil, hostsNativeErr
	}
	return hostsNativeShared, nil
}

// hostsSource is one input the table is built from: a file the kernel reads, or text Go already
// holds (`LoadReader`).
type hostsSource struct {
	path string
	text string
}

func hostsSourceFile(path string) hostsSource { return hostsSource{path: path} }
func hostsSourceText(text string) hostsSource { return hostsSource{text: text} }

func (s hostsSource) isFile() bool { return s.path != "" }

// hostsNativeTable owns one Rust table: the three maps for one configuration generation.
type hostsNativeTable struct {
	lib     *hostsNativeLib
	pointer unsafe.Pointer
}

func buildHostsNativeTable(sources []hostsSource) (*hostsNativeTable, error) {
	lib, err := hostsKernel()
	if err != nil {
		return nil, err
	}
	payload := encodeHostsSources(sources)
	var pointer unsafe.Pointer
	if status := lib.newTable(unsafe.Pointer(&payload[0]), uintptr(len(payload)), &pointer); status != 1 || pointer == nil {
		return nil, fmt.Errorf("hosts kernel could not build a table (status %d)", status)
	}
	return &hostsNativeTable{lib: lib, pointer: pointer}, nil
}

// info reports the paths that were read and the last read failure, which is what `UpdateConfig`
// returns and what `Reload` re-reads.
func (t *hostsNativeTable) info() ([]string, error) {
	if t == nil || t.pointer == nil {
		return nil, nil
	}
	var out unsafe.Pointer
	var outLen uintptr
	if status := t.lib.info(t.pointer, &out, &outLen); status != 1 {
		return nil, fmt.Errorf("hosts kernel could not describe the table (status %d)", status)
	}
	payload := copyNativePayload(t.lib.freeBytes, out, outLen)
	return decodeHostsInfo(payload)
}

// lookup answers one qtype; the addresses come back as raw 4- or 16-byte values.
func (t *hostsNativeTable) lookup(host string, qtype uint16) ([][]byte, error) {
	if t == nil || t.pointer == nil {
		return nil, nil
	}
	var hostPtr unsafe.Pointer
	if len(host) > 0 {
		hostPtr = unsafe.Pointer(unsafe.StringData(host))
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := t.lib.lookup(t.pointer, hostPtr, uintptr(len(host)), qtype, &out, &outLen)
	runtime.KeepAlive(host)
	if status != 1 {
		return nil, fmt.Errorf("hosts kernel lookup failed (status %d)", status)
	}
	payload := copyNativePayload(t.lib.freeBytes, out, outLen)
	return decodeHostsLookup(payload)
}

// contains is `HasDomain`: does any map hold this host.
func (t *hostsNativeTable) contains(host string) bool {
	if t == nil || t.pointer == nil {
		return false
	}
	var hostPtr unsafe.Pointer
	if len(host) > 0 {
		hostPtr = unsafe.Pointer(unsafe.StringData(host))
	}
	status := t.lib.contains(t.pointer, hostPtr, uintptr(len(host)))
	runtime.KeepAlive(host)
	return status == 1
}

// ptr resolves a reverse name to every alias, in file order.
func (t *hostsNativeTable) ptr(arpa string) []string {
	if t == nil || t.pointer == nil {
		return nil
	}
	var arpaPtr unsafe.Pointer
	if len(arpa) > 0 {
		arpaPtr = unsafe.Pointer(unsafe.StringData(arpa))
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := t.lib.ptr(t.pointer, arpaPtr, uintptr(len(arpa)), &out, &outLen)
	runtime.KeepAlive(arpa)
	if status != 1 {
		log.Printf("[Hosts] 内核反查失败（status %d），本次按未命中处理\n", status)
		return nil
	}
	payload := copyNativePayload(t.lib.freeBytes, out, outLen)
	names, err := decodeHostsNames(payload)
	if err != nil {
		log.Printf("[Hosts] 内核反查载荷无法解析: %v（本次按未命中处理）\n", err)
		return nil
	}
	return names
}

// reverse maps an address (4 or 16 bytes) to the first name registered for it.
func (t *hostsNativeTable) reverse(address []byte) string {
	if t == nil || t.pointer == nil || len(address) == 0 {
		return ""
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := t.lib.reverse(t.pointer, unsafe.Pointer(&address[0]), uintptr(len(address)), &out, &outLen)
	runtime.KeepAlive(address)
	if status != 1 {
		return ""
	}
	payload := copyNativePayload(t.lib.freeBytes, out, outLen)
	name, ok, err := decodeHostsReverse(payload)
	if err != nil || !ok {
		return ""
	}
	return name
}

func (t *hostsNativeTable) free() {
	if t == nil || t.pointer == nil {
		return
	}
	t.lib.free(t.pointer)
	t.pointer = nil
}

// hostsParseArpa calls the stateless reverse-name parser the rewrite engine also uses.
func hostsParseArpa(name string) ([]byte, bool) {
	lib, err := hostsKernel()
	if err != nil {
		log.Printf("[Hosts] 内核未就绪: %v\n", err)
		return nil, false
	}
	var namePtr unsafe.Pointer
	if len(name) > 0 {
		namePtr = unsafe.Pointer(unsafe.StringData(name))
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := lib.parseArpa(namePtr, uintptr(len(name)), &out, &outLen)
	runtime.KeepAlive(name)
	if status != 1 {
		return nil, false
	}
	payload := copyNativePayload(lib.freeBytes, out, outLen)
	address, err := decodeHostsArpa(payload)
	if err != nil {
		log.Printf("[Hosts] 内核反查名载荷无法解析: %v\n", err)
		return nil, false
	}
	return address, address != nil
}

// encodeHostsSources writes the layout described in rust/diting-hosts-core/src/payload.rs.
func encodeHostsSources(sources []hostsSource) []byte {
	size := 5
	for _, source := range sources {
		if source.isFile() {
			size += 5 + len(source.path)
			continue
		}
		size += 5 + len(source.text)
	}
	payload := make([]byte, 0, size)
	payload = append(payload, hostsPayloadLayoutVersion)
	payload = appendUint32(payload, uint32(len(sources)))
	for _, source := range sources {
		if source.isFile() {
			payload = append(payload, hostsSourceKindFile)
			payload = appendUint32(payload, uint32(len(source.path)))
			payload = append(payload, source.path...)
			continue
		}
		payload = append(payload, hostsSourceKindText)
		payload = appendUint32(payload, uint32(len(source.text)))
		payload = append(payload, source.text...)
	}
	return payload
}

func appendUint32(buffer []byte, value uint32) []byte {
	return append(buffer, byte(value), byte(value>>8), byte(value>>16), byte(value>>24))
}

// decodeHostsInfo reads the loaded paths and the last read error (see payload.rs).
func decodeHostsInfo(payload []byte) ([]string, error) {
	reader := &payloadReader{data: payload}
	if err := expectHostsLayout(reader, "info"); err != nil {
		return nil, err
	}
	hasError, err := reader.u8()
	if err != nil {
		return nil, err
	}
	message, err := reader.text32()
	if err != nil {
		return nil, err
	}
	count, err := reader.u32()
	if err != nil {
		return nil, err
	}
	loaded := make([]string, 0, count)
	for index := uint32(0); index < count; index++ {
		path, err := reader.text32()
		if err != nil {
			return nil, err
		}
		loaded = append(loaded, path)
	}
	if err := expectPayloadEnd(reader, "info"); err != nil {
		return nil, err
	}
	if hasError == 1 {
		return loaded, errors.New(message)
	}
	return loaded, nil
}

// decodeHostsLookup reads the address list (see payload.rs).
func decodeHostsLookup(payload []byte) ([][]byte, error) {
	reader := &payloadReader{data: payload}
	if err := expectHostsLayout(reader, "lookup"); err != nil {
		return nil, err
	}
	width, err := reader.u8()
	if err != nil {
		return nil, err
	}
	if width != net.IPv4len && width != net.IPv6len {
		return nil, fmt.Errorf("lookup width %d", width)
	}
	count, err := reader.u32()
	if err != nil {
		return nil, err
	}
	addresses := make([][]byte, 0, count)
	for index := uint32(0); index < count; index++ {
		raw, err := reader.bytes(int(width))
		if err != nil {
			return nil, err
		}
		address := make([]byte, len(raw))
		copy(address, raw)
		addresses = append(addresses, address)
	}
	if err := expectPayloadEnd(reader, "lookup"); err != nil {
		return nil, err
	}
	return addresses, nil
}

// decodeHostsNames reads the alias list (see payload.rs).
func decodeHostsNames(payload []byte) ([]string, error) {
	reader := &payloadReader{data: payload}
	if err := expectHostsLayout(reader, "names"); err != nil {
		return nil, err
	}
	count, err := reader.u32()
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, count)
	for index := uint32(0); index < count; index++ {
		name, err := reader.text32()
		if err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	if err := expectPayloadEnd(reader, "names"); err != nil {
		return nil, err
	}
	return names, nil
}

// decodeHostsReverse reads the preferred name (see payload.rs).
func decodeHostsReverse(payload []byte) (string, bool, error) {
	reader := &payloadReader{data: payload}
	if err := expectHostsLayout(reader, "reverse"); err != nil {
		return "", false, err
	}
	found, err := reader.u8()
	if err != nil {
		return "", false, err
	}
	name, err := reader.text32()
	if err != nil {
		return "", false, err
	}
	if err := expectPayloadEnd(reader, "reverse"); err != nil {
		return "", false, err
	}
	return name, found == 1, nil
}

// decodeHostsArpa reads a parsed reverse name: `nil` when the name has no address behind it.
func decodeHostsArpa(payload []byte) ([]byte, error) {
	reader := &payloadReader{data: payload}
	if err := expectHostsLayout(reader, "arpa"); err != nil {
		return nil, err
	}
	width, err := reader.u8()
	if err != nil {
		return nil, err
	}
	switch width {
	case 0:
		if err := expectPayloadEnd(reader, "arpa"); err != nil {
			return nil, err
		}
		return nil, nil
	case net.IPv4len, net.IPv6len:
	default:
		return nil, fmt.Errorf("arpa width %d", width)
	}
	raw, err := reader.bytes(int(width))
	if err != nil {
		return nil, err
	}
	address := make([]byte, len(raw))
	copy(address, raw)
	if err := expectPayloadEnd(reader, "arpa"); err != nil {
		return nil, err
	}
	return address, nil
}

// expectHostsLayout rejects a payload written by a different build.
func expectHostsLayout(reader *payloadReader, what string) error {
	layout, err := reader.u8()
	if err != nil {
		return err
	}
	if layout != hostsPayloadLayoutVersion {
		return fmt.Errorf("%s layout %d, expected %d", what, layout, hostsPayloadLayoutVersion)
	}
	return nil
}

func expectPayloadEnd(reader *payloadReader, what string) error {
	if remaining := reader.remaining(); remaining != 0 {
		return fmt.Errorf("%s payload has %d trailing bytes", what, remaining)
	}
	return nil
}
