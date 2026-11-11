package core

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// stampPayload builds a payload in the layout src/ffi.rs writes, so the decoder can be tested
// without the library.
func stampPayload(layout byte, mutate func(*[]byte)) []byte {
	payload := []byte{layout, 0x02}
	payload = binary.LittleEndian.AppendUint64(payload, 0)
	for _, text := range []string{"DOH", "1.1.1.1:443", "cloudflare-dns.com", "/dns-query", "https://cloudflare-dns.com/dns-query", "cloudflare-dns.com"} {
		payload = binary.LittleEndian.AppendUint16(payload, uint16(len(text)))
		payload = append(payload, text...)
	}
	payload = binary.LittleEndian.AppendUint16(payload, 0) // no pins
	payload = binary.LittleEndian.AppendUint16(payload, 0) // no bootstrap IPs
	if mutate != nil {
		mutate(&payload)
	}
	return payload
}

func TestDecodeStampPayload(t *testing.T) {
	stamp, err := decodeStampPayload(stampPayload(stampPayloadLayoutVersion, nil))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if stamp.Proto != StampProtoDoH {
		t.Fatalf("proto = %v", stamp.Proto)
	}
	if stamp.URL() != "https://cloudflare-dns.com/dns-query" {
		t.Fatalf("url = %q", stamp.URL())
	}
	if stamp.Server() != "cloudflare-dns.com" {
		t.Fatalf("server = %q", stamp.Server())
	}
	if proto, err := stamp.Protocol(); err != nil || proto != ProtocolDoH {
		t.Fatalf("Protocol() = %v, %v", proto, err)
	}
}

func TestDecodeStampPayloadRejectsMismatchedArtifacts(t *testing.T) {
	// A layout mismatch means the shipped .so/.dll and this binary are not the same build.
	if _, err := decodeStampPayload(stampPayload(stampPayloadLayoutVersion+1, nil)); err == nil {
		t.Fatal("expected a layout mismatch error")
	}
	// Trailing bytes mean the payload is longer than this decoder understands.
	trailing := stampPayload(stampPayloadLayoutVersion, func(payload *[]byte) {
		*payload = append(*payload, 0xEE)
	})
	if _, err := decodeStampPayload(trailing); err == nil {
		t.Fatal("expected a trailing-byte error")
	}
	if _, err := decodeStampPayload(stampPayload(stampPayloadLayoutVersion, nil)[:12]); err == nil {
		t.Fatal("expected a truncated payload error")
	}
}

func TestStampLibraryCandidatesHonourExplicitPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "custom-lib.so")
	t.Setenv("DITING_STAMP_CORE_LIB", path)
	candidates := stampNativeLibraryCandidates()
	if len(candidates) != 1 || candidates[0] != path {
		t.Fatalf("candidates = %v, want only %q", candidates, path)
	}
}

func TestStampLibraryLookupFollowsTheExecutable(t *testing.T) {
	t.Setenv("DITING_STAMP_CORE_LIB", "")
	candidates := stampNativeLibraryCandidates()
	executable, err := os.Executable()
	if err != nil {
		t.Skipf("os.Executable unavailable: %v", err)
	}
	want := filepath.Join(filepath.Dir(executable), stampNativeLibraryName())
	if len(candidates) == 0 || candidates[0] != want {
		t.Fatalf("first candidate = %v, want %q", candidates, want)
	}
	if !strings.Contains(strings.Join(candidates, string(os.PathSeparator)), "rust") {
		t.Fatalf("candidates = %v, want a rust cwd fallback for go test", candidates)
	}
}
