package core

import (
	"encoding/binary"
	"net"
	"os"
	"path/filepath"
	"testing"
)

// hostsInfoPayload builds a payload in the layout src/payload.rs writes, so the decoder can be
// tested without a table.
func hostsInfoPayload(hasError byte, message string, loaded []string) []byte {
	payload := []byte{hostsPayloadLayoutVersion, hasError}
	payload = appendUint32(payload, uint32(len(message)))
	payload = append(payload, message...)
	payload = appendUint32(payload, uint32(len(loaded)))
	for _, path := range loaded {
		payload = appendUint32(payload, uint32(len(path)))
		payload = append(payload, path...)
	}
	return payload
}

func TestDecodeHostsInfoPayload(t *testing.T) {
	loaded, err := decodeHostsInfo(hostsInfoPayload(0, "", []string{"/etc/hosts", "custom.hosts"}))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(loaded) != 2 || loaded[0] != "/etc/hosts" || loaded[1] != "custom.hosts" {
		t.Fatalf("loaded = %v", loaded)
	}

	loaded, err = decodeHostsInfo(hostsInfoPayload(1, "custom.hosts: no such file", []string{"/etc/hosts"}))
	if err == nil || err.Error() != "custom.hosts: no such file" {
		t.Fatalf("err = %v", err)
	}
	if len(loaded) != 1 {
		t.Fatalf("loaded = %v", loaded)
	}
}

func TestDecodeHostsInfoRejectsMismatchedArtifacts(t *testing.T) {
	// A layout mismatch means the shipped .dll/.so and this binary are not the same build.
	payload := hostsInfoPayload(0, "", nil)
	payload[0] = hostsPayloadLayoutVersion + 1
	if _, err := decodeHostsInfo(payload); err == nil {
		t.Fatal("expected a layout mismatch error")
	}
	if _, err := decodeHostsInfo(append(hostsInfoPayload(0, "", nil), 0xEE)); err == nil {
		t.Fatal("expected a trailing-byte error")
	}
	if _, err := decodeHostsInfo(hostsInfoPayload(0, "", nil)[:4]); err == nil {
		t.Fatal("expected a truncated payload error")
	}
}

func hostsLookupPayload(width byte, addresses ...[]byte) []byte {
	payload := []byte{hostsPayloadLayoutVersion, width}
	payload = appendUint32(payload, uint32(len(addresses)))
	for _, address := range addresses {
		payload = append(payload, address...)
	}
	return payload
}

func TestDecodeHostsLookupPayload(t *testing.T) {
	addresses, err := decodeHostsLookup(hostsLookupPayload(4, []byte{192, 168, 1, 1}, []byte{10, 0, 0, 2}))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(addresses) != 2 || !net.IP(addresses[0]).Equal(net.IPv4(192, 168, 1, 1)) {
		t.Fatalf("addresses = %v", addresses)
	}

	addresses, err = decodeHostsLookup(hostsLookupPayload(16, make([]byte, 16)))
	if err != nil || len(addresses) != 1 || len(addresses[0]) != net.IPv6len {
		t.Fatalf("addresses = %v, err = %v", addresses, err)
	}

	// An unknown width is a build mismatch, not an address we can guess at.
	if _, err := decodeHostsLookup(hostsLookupPayload(8, make([]byte, 8))); err == nil {
		t.Fatal("expected a width error")
	}
	if _, err := decodeHostsLookup(hostsLookupPayload(4, []byte{1, 2, 3})); err == nil {
		t.Fatal("expected a truncated address error")
	}
}

func TestDecodeHostsNamesPayload(t *testing.T) {
	payload := []byte{hostsPayloadLayoutVersion}
	payload = appendUint32(payload, 2)
	payload = appendUint32(payload, uint32(len("nas.home")))
	payload = append(payload, "nas.home"...)
	payload = appendUint32(payload, uint32(len("storage.home")))
	payload = append(payload, "storage.home"...)

	names, err := decodeHostsNames(payload)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(names) != 2 || names[0] != "nas.home" || names[1] != "storage.home" {
		t.Fatalf("names = %v", names)
	}
}

func TestDecodeHostsReverseAndArpa(t *testing.T) {
	reverse := []byte{hostsPayloadLayoutVersion, 1}
	reverse = appendUint32(reverse, uint32(len("nas.home")))
	reverse = append(reverse, "nas.home"...)
	name, ok, err := decodeHostsReverse(reverse)
	if err != nil || !ok || name != "nas.home" {
		t.Fatalf("reverse = %q, %v, %v", name, ok, err)
	}

	miss := []byte{hostsPayloadLayoutVersion, 0, 0, 0, 0, 0}
	if name, ok, err := decodeHostsReverse(miss); err != nil || ok || name != "" {
		t.Fatalf("miss = %q, %v, %v", name, ok, err)
	}

	// The mapped IPv4 form collapses, so a 4-byte answer is what comes back.
	arpa := []byte{hostsPayloadLayoutVersion, 4, 192, 168, 1, 1}
	address, err := decodeHostsArpa(arpa)
	if err != nil || !net.IP(address).Equal(net.IPv4(192, 168, 1, 1)) {
		t.Fatalf("arpa = %v, %v", address, err)
	}

	address, err = decodeHostsArpa([]byte{hostsPayloadLayoutVersion, 0})
	if err != nil || address != nil {
		t.Fatalf("arpa miss = %v, %v", address, err)
	}
	if _, err := decodeHostsArpa([]byte{hostsPayloadLayoutVersion, 5, 1, 2, 3, 4, 5}); err == nil {
		t.Fatal("expected a width error")
	}
}

func TestEncodeHostsSourcesLayout(t *testing.T) {
	payload := encodeHostsSources([]hostsSource{
		hostsSourceFile("/etc/hosts"),
		hostsSourceText("127.0.0.1 localhost\n"),
	})

	if payload[0] != hostsPayloadLayoutVersion {
		t.Fatalf("layout = %d", payload[0])
	}
	if count := binary.LittleEndian.Uint32(payload[1:]); count != 2 {
		t.Fatalf("count = %d", count)
	}
	if payload[5] != hostsSourceKindFile {
		t.Fatalf("first kind = %d", payload[5])
	}
	if length := binary.LittleEndian.Uint32(payload[6:]); length != uint32(len("/etc/hosts")) {
		t.Fatalf("first length = %d", length)
	}
	if got := string(payload[10 : 10+len("/etc/hosts")]); got != "/etc/hosts" {
		t.Fatalf("first path = %q", got)
	}
	offset := 10 + len("/etc/hosts")
	if payload[offset] != hostsSourceKindText {
		t.Fatalf("second kind = %d", payload[offset])
	}
	text := "127.0.0.1 localhost\n"
	if length := binary.LittleEndian.Uint32(payload[offset+1:]); length != uint32(len(text)) {
		t.Fatalf("second length = %d", length)
	}
	if got := string(payload[offset+5:]); got != text {
		t.Fatalf("second text = %q", got)
	}

	if empty := encodeHostsSources(nil); len(empty) != 5 {
		t.Fatalf("empty payload length = %d", len(empty))
	}
}

func TestHostsNativeLibraryCandidatesHonourExplicitPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "custom-lib.so")
	t.Setenv("DITING_HOSTS_CORE_LIB", path)
	candidates := hostsNativeLibraryCandidates()
	if len(candidates) != 1 || candidates[0] != path {
		t.Fatalf("candidates = %v, want only %q", candidates, path)
	}
}

func TestHostsNativeLibraryLookupFollowsTheExecutable(t *testing.T) {
	t.Setenv("DITING_HOSTS_CORE_LIB", "")
	candidates := hostsNativeLibraryCandidates()
	executable, err := os.Executable()
	if err != nil {
		t.Skipf("os.Executable unavailable: %v", err)
	}
	for _, want := range []string{
		filepath.Join(filepath.Dir(executable), hostsNativeLibraryName()),
		filepath.Join("..", "..", "..", "..", "rust", "target", "release", hostsNativeLibraryName()),
	} {
		found := false
		for _, candidate := range candidates {
			if candidate == want {
				found = true
			}
		}
		if !found {
			t.Fatalf("candidates = %v, want %q among them", candidates, want)
		}
	}
}
