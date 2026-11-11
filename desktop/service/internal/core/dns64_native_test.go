package core

import (
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDecodeDNS64Result(t *testing.T) {
	payload := []byte{dns64PayloadLayoutVersion, 2}
	first := make([]byte, net.IPv6len)
	first[0], first[15] = 0x64, 1
	second := make([]byte, net.IPv6len)
	second[0], second[15] = 0x20, 2
	payload = append(payload, first...)
	payload = append(payload, second...)

	addresses, err := decodeDNS64Result(payload)
	if err != nil {
		t.Fatalf("decodeDNS64Result: %v", err)
	}
	if len(addresses) != 2 {
		t.Fatalf("addresses = %d, want 2", len(addresses))
	}
	for index, want := range [][]byte{first, second} {
		if len(addresses[index]) != net.IPv6len {
			t.Fatalf("address %d width = %d", index, len(addresses[index]))
		}
		for offset := range want {
			if addresses[index][offset] != want[offset] {
				t.Fatalf("address %d byte %d = %#x, want %#x",
					index, offset, addresses[index][offset], want[offset])
			}
		}
	}
}

func TestDecodeDNS64ResultRejectsMismatchedArtifacts(t *testing.T) {
	cases := map[string][]byte{
		"empty":         nil,
		"stale layout":  {dns64PayloadLayoutVersion + 1, 0},
		"truncated":     {dns64PayloadLayoutVersion, 1, 0, 0},
		"trailing junk": {dns64PayloadLayoutVersion, 0, 0x7f},
	}
	for name, payload := range cases {
		if _, err := decodeDNS64Result(payload); err == nil {
			t.Fatalf("%s: expected an error", name)
		}
	}
}

func TestEncodeDNS64PrefixesLayout(t *testing.T) {
	payload := encodeDNS64Prefixes([]string{"64:ff9b::/96", "2001:db8::/32"})
	if payload[0] != dns64PayloadLayoutVersion {
		t.Fatalf("layout = %d, want %d", payload[0], dns64PayloadLayoutVersion)
	}
	if count := int(payload[1]) | int(payload[2])<<8; count != 2 {
		t.Fatalf("count = %d, want 2", count)
	}
	offset := 3
	for _, prefix := range []string{"64:ff9b::/96", "2001:db8::/32"} {
		length := int(payload[offset]) | int(payload[offset+1])<<8 |
			int(payload[offset+2])<<16 | int(payload[offset+3])<<24
		if length != len(prefix) {
			t.Fatalf("prefix length = %d, want %d", length, len(prefix))
		}
		offset += 4
		if text := string(payload[offset : offset+length]); text != prefix {
			t.Fatalf("prefix = %q, want %q", text, prefix)
		}
		offset += length
	}
	if offset != len(payload) {
		t.Fatalf("payload has %d trailing bytes", len(payload)-offset)
	}
}

func TestEncodeDNS64AddressesCarriesTheWidth(t *testing.T) {
	payload := encodeDNS64Addresses([][]byte{{1, 2, 3, 4}, make([]byte, net.IPv6len)})
	if count := int(payload[1]) | int(payload[2])<<8; count != 2 {
		t.Fatalf("count = %d, want 2", count)
	}
	if payload[3] != net.IPv4len {
		t.Fatalf("first width = %d, want %d", payload[3], net.IPv4len)
	}
	if payload[8] != net.IPv6len {
		t.Fatalf("second width = %d, want %d", payload[8], net.IPv6len)
	}
}

func TestNewDNS64SynthesizerReportsBadPrefixesAsConfigErrors(t *testing.T) {
	synth, err := NewDNS64Synthesizer(DNS64Config{
		Enabled:  true,
		Prefixes: []string{"64:ff9b::/96", " 2001:db8::/28 "},
	})
	if err == nil {
		t.Fatal("expected an error for an RFC 6052 length outside the allowed set")
	}
	if synth != nil {
		t.Fatal("expected no synthesizer")
	}
	if !IsDNS64ConfigError(err) {
		t.Fatalf("IsDNS64ConfigError(%v) = false", err)
	}
	message := err.Error()
	if !strings.Contains(message, "RFC 6052") || !strings.Contains(message, "2001:db8::/28") {
		t.Fatalf("message = %q", message)
	}
	if strings.Contains(message, " 2001:db8::/28 ") {
		t.Fatalf("message should quote the trimmed prefix: %q", message)
	}

	_, err = NewDNS64Synthesizer(DNS64Config{Enabled: true, Prefixes: []string{"nonsense"}})
	if err == nil {
		t.Fatal("expected an error for a malformed CIDR")
	}
	if !IsDNS64ConfigError(err) {
		t.Fatalf("IsDNS64ConfigError(%v) = false", err)
	}
	if want := `解析 DNS64 前缀 "nonsense" 失败: invalid CIDR address: nonsense`; err.Error() != want {
		t.Fatalf("message = %q, want %q", err.Error(), want)
	}
}

func TestNewDNS64SynthesizerAcceptsBlankPrefixes(t *testing.T) {
	synth, err := NewDNS64Synthesizer(DNS64Config{Enabled: true, Prefixes: []string{"  "}})
	if err != nil {
		t.Fatalf("blank prefixes should fall back to the well-known one: %v", err)
	}
	if got := synth.MapIPv4ToIPv6(net.ParseIP("192.0.2.1")); got.String() != "64:ff9b::c000:201" {
		t.Fatalf("MapIPv4ToIPv6 = %v", got)
	}
}

func TestEmbedIPv4InIPv6KeepsCollapsedPrefixes(t *testing.T) {
	// `::ffff:0:0/96` 的 `IPNet.String()` 是 `0.0.0.0/0`，前缀一旦走文本往返就丢了 IPv6 形态。
	_, mapped, err := net.ParseCIDR("::ffff:0:0/96")
	if err != nil {
		t.Fatalf("ParseCIDR: %v", err)
	}
	got := EmbedIPv4InIPv6(net.ParseIP("192.0.2.1"), mapped)
	if len(got) != net.IPv6len {
		t.Fatalf("got %v (%d bytes), want a 16-byte address", got, len(got))
	}
	want := [16]byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 192, 0, 2, 1}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("byte %d = %#x, want %#x", index, got[index], want[index])
		}
	}

	_, v4Net, err := net.ParseCIDR("10.0.0.0/8")
	if err != nil {
		t.Fatalf("ParseCIDR: %v", err)
	}
	if got := EmbedIPv4InIPv6(net.ParseIP("192.0.2.1"), v4Net); got != nil {
		t.Fatalf("IPv4 prefix should not embed, got %v", got)
	}

	_, oddLength, err := net.ParseCIDR("2001:db8::/36")
	if err != nil {
		t.Fatalf("ParseCIDR: %v", err)
	}
	if got := EmbedIPv4InIPv6(net.ParseIP("192.0.2.1"), oddLength); got != nil {
		t.Fatalf("non-RFC 6052 length should not embed, got %v", got)
	}
}

func TestMapIPv4ToIPv6UnderAMappedPrefix(t *testing.T) {
	synth, err := NewDNS64Synthesizer(DNS64Config{
		Enabled:  true,
		Prefixes: []string{"::ffff:0:0/96"},
	})
	if err != nil {
		t.Fatalf("NewDNS64Synthesizer: %v", err)
	}
	got := synth.MapIPv4ToIPv6(net.ParseIP("192.0.2.1")).To16()
	want := [16]byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 192, 0, 2, 1}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("byte %d = %#x, want %#x", index, got[index], want[index])
		}
	}
}

func TestDNS64NativeLibraryCandidatesHonourExplicitPath(t *testing.T) {
	explicit := filepath.Join("tmp", nativeLibraryFile(dns64NativeLibraryTag))
	t.Setenv("DITING_DNS64_CORE_LIB", explicit)
	candidates := nativeLibraryCandidates("DITING_DNS64_CORE_LIB", dns64NativeLibraryTag)
	if len(candidates) != 1 || candidates[0] != explicit {
		t.Fatalf("candidates = %v, want [%s]", candidates, explicit)
	}
}

func TestDNS64NativeLibraryLookupFollowsTheExecutable(t *testing.T) {
	t.Setenv("DITING_DNS64_CORE_LIB", "")
	executable, err := os.Executable()
	if err != nil {
		t.Skipf("no executable path: %v", err)
	}
	candidates := nativeLibraryCandidates("DITING_DNS64_CORE_LIB", dns64NativeLibraryTag)
	if len(candidates) == 0 {
		t.Fatal("expected candidates")
	}
	want := filepath.Join(filepath.Dir(executable), nativeLibraryFile(dns64NativeLibraryTag))
	if candidates[0] != want {
		t.Fatalf("first candidate = %s, want %s", candidates[0], want)
	}
}
