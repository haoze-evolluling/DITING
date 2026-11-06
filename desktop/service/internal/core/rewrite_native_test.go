package core

import (
	"encoding/binary"
	"net"
	"strings"
	"testing"

	"github.com/miekg/dns"
)

// rewriteText appends a `u32`-length string, the shape src/payload.rs uses.
func rewriteText(payload []byte, value string) []byte {
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len(value)))
	return append(payload, value...)
}

// rewriteRecordReply starts a reply that carries one record of rrtype.
func rewriteRecordReply(rrtype uint16, owner string, ttl uint32) []byte {
	payload := []byte{rewritePayloadLayoutVersion, 1}
	payload = binary.LittleEndian.AppendUint16(payload, rrtype)
	payload = rewriteText(payload, owner)
	return binary.LittleEndian.AppendUint32(payload, ttl)
}

func TestEncodeRewriteRecordRequest(t *testing.T) {
	payload := encodeRewriteRecordRequest("host.", dns.TypeHTTPS, RewriteRecord{
		Type:  "HTTPS",
		Value: "1 . alpn=h3",
	}, 60)

	want := []byte{rewritePayloadLayoutVersion, 0x41, 0x00, 60, 0, 0, 0}
	want = rewriteText(want, "host.")
	want = rewriteText(want, "HTTPS")
	want = rewriteText(want, "1 . alpn=h3")
	if string(payload) != string(want) {
		t.Fatalf("请求载荷 = %v, want %v", payload, want)
	}
}

func TestDecodeRewriteRecordAddresses(t *testing.T) {
	a := rewriteRecordReply(dns.TypeA, "host.lan.", 60)
	a = append(a, 10, 0, 0, 1)
	record, err := decodeRewriteRecord(a)
	if err != nil {
		t.Fatalf("decode A: %v", err)
	}
	addr, ok := record.(*dns.A)
	if !ok || !addr.A.Equal(net.ParseIP("10.0.0.1")) {
		t.Fatalf("A 记录 = %v", record)
	}
	if addr.Hdr.Name != "host.lan." || addr.Hdr.Ttl != 60 || addr.Hdr.Class != dns.ClassINET {
		t.Fatalf("A 记录头 = %+v", addr.Hdr)
	}

	aaaa := rewriteRecordReply(dns.TypeAAAA, "host.lan.", 60)
	aaaa = append(aaaa, net.ParseIP("fe80::1")...)
	record, err = decodeRewriteRecord(aaaa)
	if err != nil {
		t.Fatalf("decode AAAA: %v", err)
	}
	if v6, ok := record.(*dns.AAAA); !ok || !v6.AAAA.Equal(net.ParseIP("fe80::1")) {
		t.Fatalf("AAAA 记录 = %v", record)
	}
}

func TestDecodeRewriteRecordNamesAndText(t *testing.T) {
	for _, tc := range []struct {
		rrtype uint16
		value  string
		check  func(dns.RR) bool
	}{
		{dns.TypeCNAME, "target.example.", func(rr dns.RR) bool {
			return rr.(*dns.CNAME).Target == "target.example."
		}},
		{dns.TypeNS, "ns1.example.", func(rr dns.RR) bool { return rr.(*dns.NS).Ns == "ns1.example." }},
		{dns.TypePTR, "host.example.", func(rr dns.RR) bool { return rr.(*dns.PTR).Ptr == "host.example." }},
		{dns.TypeTXT, "v=spf1 ~all", func(rr dns.RR) bool {
			txt := rr.(*dns.TXT)
			return len(txt.Txt) == 1 && txt.Txt[0] == "v=spf1 ~all"
		}},
	} {
		payload := rewriteRecordReply(tc.rrtype, "host.lan.", 30)
		payload = rewriteText(payload, tc.value)
		record, err := decodeRewriteRecord(payload)
		if err != nil {
			t.Fatalf("decode %d: %v", tc.rrtype, err)
		}
		if !tc.check(record) {
			t.Fatalf("记录 = %v", record)
		}
	}
}

func TestDecodeRewriteRecordMXAndSRV(t *testing.T) {
	mx := rewriteRecordReply(dns.TypeMX, "mail.lan.", 60)
	mx = binary.LittleEndian.AppendUint16(mx, 32)
	mx = rewriteText(mx, "example.mail.")
	record, err := decodeRewriteRecord(mx)
	if err != nil {
		t.Fatalf("decode MX: %v", err)
	}
	if got, ok := record.(*dns.MX); !ok || got.Preference != 32 || got.Mx != "example.mail." {
		t.Fatalf("MX 记录 = %v", record)
	}

	srv := rewriteRecordReply(dns.TypeSRV, "_sip._tcp.lan.", 60)
	srv = binary.LittleEndian.AppendUint16(srv, 10)
	srv = binary.LittleEndian.AppendUint16(srv, 60)
	srv = binary.LittleEndian.AppendUint16(srv, 8080)
	srv = rewriteText(srv, "sip.lan.")
	record, err = decodeRewriteRecord(srv)
	if err != nil {
		t.Fatalf("decode SRV: %v", err)
	}
	got, ok := record.(*dns.SRV)
	if !ok || got.Priority != 10 || got.Weight != 60 || got.Port != 8080 || got.Target != "sip.lan." {
		t.Fatalf("SRV 记录 = %v", record)
	}
}

func TestDecodeRewriteRecordSVCB(t *testing.T) {
	payload := rewriteRecordReply(dns.TypeHTTPS, "svc.lan.", 60)
	payload = binary.LittleEndian.AppendUint16(payload, 1) // priority
	payload = rewriteText(payload, ".")
	payload = binary.LittleEndian.AppendUint16(payload, 6) // six parameters

	payload = binary.LittleEndian.AppendUint16(payload, rewriteSVCBKeyALPN)
	payload = binary.LittleEndian.AppendUint16(payload, 2)
	payload = rewriteText(payload, "h3")
	payload = rewriteText(payload, "h2")

	payload = binary.LittleEndian.AppendUint16(payload, rewriteSVCBKeyNoDefaultALPN)

	payload = binary.LittleEndian.AppendUint16(payload, rewriteSVCBKeyPort)
	payload = binary.LittleEndian.AppendUint16(payload, 8443)

	payload = binary.LittleEndian.AppendUint16(payload, rewriteSVCBKeyIPv4Hint)
	payload = binary.LittleEndian.AppendUint16(payload, 1)
	payload = append(payload, 10, 0, 0, 9)

	payload = binary.LittleEndian.AppendUint16(payload, rewriteSVCBKeyIPv6Hint)
	payload = binary.LittleEndian.AppendUint16(payload, 1)
	payload = append(payload, net.ParseIP("2001:db8::1")...)

	payload = binary.LittleEndian.AppendUint16(payload, rewriteSVCBKeyMandatory)
	payload = binary.LittleEndian.AppendUint16(payload, 1)
	payload = binary.LittleEndian.AppendUint16(payload, rewriteSVCBKeyALPN)

	record, err := decodeRewriteRecord(payload)
	if err != nil {
		t.Fatalf("decode HTTPS: %v", err)
	}
	https, ok := record.(*dns.HTTPS)
	if !ok {
		t.Fatalf("记录类型 = %T, want *dns.HTTPS", record)
	}
	if https.Priority != 1 || https.Target != "." || https.Hdr.Rrtype != dns.TypeHTTPS {
		t.Fatalf("HTTPS 头 = %+v", https.SVCB)
	}
	if len(https.Value) != 6 {
		t.Fatalf("参数数量 = %d, want 6", len(https.Value))
	}
	if alpn, ok := https.Value[0].(*dns.SVCBAlpn); !ok || len(alpn.Alpn) != 2 || alpn.Alpn[0] != "h3" {
		t.Fatalf("alpn = %v", https.Value[0])
	}
	if _, ok := https.Value[1].(*dns.SVCBNoDefaultAlpn); !ok {
		t.Fatalf("no-default-alpn = %v", https.Value[1])
	}
	if port, ok := https.Value[2].(*dns.SVCBPort); !ok || port.Port != 8443 {
		t.Fatalf("port = %v", https.Value[2])
	}
	if hint, ok := https.Value[3].(*dns.SVCBIPv4Hint); !ok || !hint.Hint[0].Equal(net.ParseIP("10.0.0.9")) {
		t.Fatalf("ipv4hint = %v", https.Value[3])
	}
	if hint, ok := https.Value[4].(*dns.SVCBIPv6Hint); !ok || !hint.Hint[0].Equal(net.ParseIP("2001:db8::1")) {
		t.Fatalf("ipv6hint = %v", https.Value[4])
	}
	if mandatory, ok := https.Value[5].(*dns.SVCBMandatory); !ok || len(mandatory.Code) != 1 || mandatory.Code[0] != dns.SVCB_ALPN {
		t.Fatalf("mandatory = %v", https.Value[5])
	}

	// The same body with the SVCB type stays an SVCB record.
	svcbPayload := rewriteRecordReply(dns.TypeSVCB, "svc.lan.", 60)
	svcbPayload = binary.LittleEndian.AppendUint16(svcbPayload, 1)
	svcbPayload = rewriteText(svcbPayload, "svc.example.")
	svcbPayload = binary.LittleEndian.AppendUint16(svcbPayload, 1)
	svcbPayload = binary.LittleEndian.AppendUint16(svcbPayload, rewriteSVCBKeyDoHPath)
	svcbPayload = rewriteText(svcbPayload, "/dns-query")
	record, err = decodeRewriteRecord(svcbPayload)
	if err != nil {
		t.Fatalf("decode SVCB: %v", err)
	}
	svcb, ok := record.(*dns.SVCB)
	if !ok || svcb.Target != "svc.example." {
		t.Fatalf("SVCB 记录 = %v", record)
	}
	if path, ok := svcb.Value[0].(*dns.SVCBDoHPath); !ok || path.Template != "/dns-query" {
		t.Fatalf("dohpath = %v", svcb.Value[0])
	}
}

func TestDecodeRewriteRecordECH(t *testing.T) {
	payload := rewriteRecordReply(dns.TypeHTTPS, "svc.lan.", 60)
	payload = binary.LittleEndian.AppendUint16(payload, 1)
	payload = rewriteText(payload, ".")
	payload = binary.LittleEndian.AppendUint16(payload, 1)
	payload = binary.LittleEndian.AppendUint16(payload, rewriteSVCBKeyECHConfig)
	payload = binary.LittleEndian.AppendUint32(payload, 3)
	payload = append(payload, 0xaa, 0xbb, 0xcc)

	record, err := decodeRewriteRecord(payload)
	if err != nil {
		t.Fatalf("decode ECH: %v", err)
	}
	ech, ok := record.(*dns.HTTPS).Value[0].(*dns.SVCBECHConfig)
	if !ok || len(ech.ECH) != 3 || ech.ECH[0] != 0xaa {
		t.Fatalf("ech = %v", record)
	}
}

func TestDecodeRewriteRecordNODATA(t *testing.T) {
	record, err := decodeRewriteRecord([]byte{rewritePayloadLayoutVersion, 0})
	if err != nil {
		t.Fatalf("decode NODATA: %v", err)
	}
	if record != nil {
		t.Fatalf("NODATA 应答不应产出记录: %v", record)
	}
}

func TestDecodeRewriteRecordRejectsMismatchedArtifacts(t *testing.T) {
	// 布局不一致意味着随包发布的库与这份二进制不是同一次构建。
	if _, err := decodeRewriteRecord([]byte{rewritePayloadLayoutVersion + 1, 0}); err == nil {
		t.Fatal("expected a layout mismatch error")
	}
	if _, err := decodeRewriteRecord([]byte{rewritePayloadLayoutVersion, 1, 9}); err == nil {
		t.Fatal("expected a truncated payload error")
	}

	trailing := rewriteRecordReply(dns.TypeA, "host.lan.", 60)
	trailing = append(trailing, 10, 0, 0, 1, 0xEE)
	if _, err := decodeRewriteRecord(trailing); err == nil {
		t.Fatal("expected a trailing-byte error")
	}

	unknownType := rewriteRecordReply(1234, "host.lan.", 60)
	if _, err := decodeRewriteRecord(unknownType); err == nil {
		t.Fatal("expected an unsupported record type error")
	}

	unknownParam := rewriteRecordReply(dns.TypeSVCB, "svc.lan.", 60)
	unknownParam = binary.LittleEndian.AppendUint16(unknownParam, 1)
	unknownParam = rewriteText(unknownParam, ".")
	unknownParam = binary.LittleEndian.AppendUint16(unknownParam, 1)
	unknownParam = binary.LittleEndian.AppendUint16(unknownParam, 99)
	if _, err := decodeRewriteRecord(unknownParam); err == nil {
		t.Fatal("expected an unsupported SVCB parameter error")
	}
}

func TestRewriteNativeCandidates(t *testing.T) {
	// 显式环境变量是唯一候选：打错名字要立刻失败，而不是悄悄用上另一份库。
	t.Setenv("DITING_REWRITE_CORE_LIB", "/explicit/libditing_rewrite_core.so")
	candidates := nativeLibraryCandidates("DITING_REWRITE_CORE_LIB", "diting_rewrite_core")
	if len(candidates) != 1 || candidates[0] != "/explicit/libditing_rewrite_core.so" {
		t.Fatalf("candidates = %v", candidates)
	}

	t.Setenv("DITING_REWRITE_CORE_LIB", "")
	candidates = nativeLibraryCandidates("DITING_REWRITE_CORE_LIB", "diting_rewrite_core")
	if len(candidates) == 0 || !strings.Contains(candidates[0], nativeLibraryFile("diting_rewrite_core")) {
		t.Fatalf("candidates = %v", candidates)
	}
}
