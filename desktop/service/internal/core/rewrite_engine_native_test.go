package core

import (
	"encoding/binary"
	"testing"

	"github.com/miekg/dns"
)

// rewriteEngineRecord starts one engine answer: rrtype, owner and TTL (no layout byte).
func rewriteEngineRecord(rrtype uint16, owner string, ttl uint32) []byte {
	payload := binary.LittleEndian.AppendUint16(nil, rrtype)
	payload = rewriteText(payload, owner)
	return binary.LittleEndian.AppendUint32(payload, ttl)
}

func TestEncodeRewriteEngineConfig(t *testing.T) {
	payload := encodeRewriteEngineConfig(RewriteConfig{
		Enabled: true,
		TTL:     90,
		Rules: []RewriteRule{{
			Domain:  "nas.lan",
			IPs:     []string{"10.0.0.1"},
			CNAME:   "target.lan",
			TXT:     []string{"v=spf1 ~all"},
			TTL:     120,
			Records: []RewriteRecord{{Type: "MX", Value: "32 mail.lan"}},
			RCode:   "NXDOMAIN",
		}},
	})

	want := []byte{rewritePayloadLayoutVersion, 1}
	want = binary.LittleEndian.AppendUint32(want, 90)
	want = binary.LittleEndian.AppendUint32(want, 1)
	want = rewriteText(want, "nas.lan")
	want = binary.LittleEndian.AppendUint32(want, 120)
	want = binary.LittleEndian.AppendUint32(want, 1)
	want = rewriteText(want, "10.0.0.1")
	want = rewriteText(want, "target.lan")
	want = binary.LittleEndian.AppendUint32(want, 1)
	want = rewriteText(want, "v=spf1 ~all")
	want = binary.LittleEndian.AppendUint32(want, 1)
	want = rewriteText(want, "MX")
	want = rewriteText(want, "32 mail.lan")
	want = rewriteText(want, "NXDOMAIN")
	if string(payload) != string(want) {
		t.Fatalf("引擎配置载荷 = %v, want %v", payload, want)
	}

	// TTL 0 由 Go 侧补齐默认值，内核永远读到明确的值。
	payload = encodeRewriteEngineConfig(RewriteConfig{})
	if got := binary.LittleEndian.Uint32(payload[2:6]); got != DefaultRewriteTTL {
		t.Fatalf("默认 TTL = %d, want %d", got, DefaultRewriteTTL)
	}
}

func TestDecodeRewriteEngineWarnings(t *testing.T) {
	payload := []byte{rewritePayloadLayoutVersion}
	payload = binary.LittleEndian.AppendUint32(payload, 2)
	payload = rewriteText(payload, "规则 a 的记录类型 \"BAD\" 不受支持，已忽略")
	payload = rewriteText(payload, "规则 b 的应答码 \"NOPE\" 无法识别，按 NOERROR 处理")
	warnings, err := decodeRewriteEngineWarnings(payload)
	if err != nil {
		t.Fatalf("decode warnings: %v", err)
	}
	if len(warnings) != 2 || warnings[1] != "规则 b 的应答码 \"NOPE\" 无法识别，按 NOERROR 处理" {
		t.Fatalf("warnings = %v", warnings)
	}

	if _, err := decodeRewriteEngineWarnings([]byte{rewritePayloadLayoutVersion + 1}); err == nil {
		t.Fatal("expected a layout mismatch error")
	}
	truncated := []byte{rewritePayloadLayoutVersion}
	truncated = binary.LittleEndian.AppendUint32(truncated, 1)
	if _, err := decodeRewriteEngineWarnings(truncated); err == nil {
		t.Fatal("expected a truncated payload error")
	}
}

func TestDecodeRewriteEngineLookup(t *testing.T) {
	payload := []byte{rewritePayloadLayoutVersion, 1}
	payload = binary.LittleEndian.AppendUint16(payload, dns.RcodeNameError)
	payload = binary.LittleEndian.AppendUint32(payload, 2)

	payload = append(payload, rewriteEngineRecord(dns.TypeA, "nas.lan.", 60)...)
	payload = append(payload, 10, 0, 0, 1)

	payload = append(payload, rewriteEngineRecord(dns.TypeTXT, "nas.lan.", 60)...)
	payload = binary.LittleEndian.AppendUint32(payload, 2)
	payload = rewriteText(payload, "v=spf1 ~all")
	payload = rewriteText(payload, "status=ok")

	answers, rcode, matched, err := decodeRewriteEngineLookup(payload)
	if err != nil {
		t.Fatalf("decode lookup: %v", err)
	}
	if !matched || rcode != dns.RcodeNameError || len(answers) != 2 {
		t.Fatalf("matched=%v rcode=%d answers=%v", matched, rcode, answers)
	}
	a, ok := answers[0].(*dns.A)
	if !ok || !a.A.Equal([]byte{10, 0, 0, 1}) || a.Hdr.Ttl != 60 {
		t.Fatalf("A 记录 = %v", answers[0])
	}
	txt, ok := answers[1].(*dns.TXT)
	if !ok || len(txt.Txt) != 2 || txt.Txt[1] != "status=ok" {
		t.Fatalf("TXT 记录 = %v", answers[1])
	}
}

func TestDecodeRewriteEngineLookupRejectsMismatchedArtifacts(t *testing.T) {
	if _, _, _, err := decodeRewriteEngineLookup([]byte{rewritePayloadLayoutVersion + 1}); err == nil {
		t.Fatal("expected a layout mismatch error")
	}
	unknownFlag := []byte{rewritePayloadLayoutVersion, 9}
	if _, _, _, err := decodeRewriteEngineLookup(unknownFlag); err == nil {
		t.Fatal("expected an unknown matched flag error")
	}

	truncated := []byte{rewritePayloadLayoutVersion, 1}
	truncated = binary.LittleEndian.AppendUint16(truncated, 0)
	truncated = binary.LittleEndian.AppendUint32(truncated, 1)
	truncated = append(truncated, rewriteEngineRecord(dns.TypeA, "nas.lan.", 60)...)
	if _, _, _, err := decodeRewriteEngineLookup(truncated); err == nil {
		t.Fatal("expected a truncated record error")
	}

	trailing := []byte{rewritePayloadLayoutVersion, 0}
	trailing = binary.LittleEndian.AppendUint16(trailing, 0)
	trailing = binary.LittleEndian.AppendUint32(trailing, 0)
	trailing = append(trailing, 0xEE)
	if _, _, _, err := decodeRewriteEngineLookup(trailing); err == nil {
		t.Fatal("expected a trailing-byte error")
	}
}

func TestDecodeRewriteEngineAddressReplies(t *testing.T) {
	domains := []byte{rewritePayloadLayoutVersion}
	domains = binary.LittleEndian.AppendUint32(domains, 2)
	domains = rewriteText(domains, "nas.lan.")
	domains = rewriteText(domains, "storage.lan.")
	names, err := decodeRewriteEngineDomains(domains)
	if err != nil {
		t.Fatalf("decode domains: %v", err)
	}
	if len(names) != 2 || names[1] != "storage.lan." {
		t.Fatalf("domains = %v", names)
	}

	reverse := []byte{rewritePayloadLayoutVersion, 1}
	reverse = rewriteText(reverse, "nas.lan.")
	name, err := decodeRewriteEngineReverse(reverse)
	if err != nil || name != "nas.lan." {
		t.Fatalf("reverse = %q, err = %v", name, err)
	}

	absent := []byte{rewritePayloadLayoutVersion, 0}
	name, err = decodeRewriteEngineReverse(absent)
	if err != nil || name != "" {
		t.Fatalf("absent reverse = %q, err = %v", name, err)
	}

	if _, err := decodeRewriteEngineReverse([]byte{rewritePayloadLayoutVersion, 2}); err == nil {
		t.Fatal("expected an unknown present flag error")
	}
	if _, err := decodeRewriteEngineDomains([]byte{rewritePayloadLayoutVersion + 1}); err == nil {
		t.Fatal("expected a layout mismatch error")
	}
}
