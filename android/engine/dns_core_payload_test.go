// dns_core_payload_test.go pins the boundary with rust/diting-dns-core: the answer inspection
// request the Go side encodes and the report it decodes. It needs no cgo, so the layout is checked
// even on a machine without a C toolchain.

package tunnel

import (
	"encoding/binary"
	"net"
	"testing"

	"github.com/miekg/dns"
)

func answerHeader(rrtype uint16) dns.RR_Header {
	return dns.RR_Header{Name: "example.com.", Rrtype: rrtype, Class: dns.ClassINET, Ttl: 300}
}

func TestDNSCoreAnswerRequestLayout(t *testing.T) {
	message := &dns.Msg{Answer: []dns.RR{
		&dns.A{Hdr: answerHeader(dns.TypeA), A: net.IP{0, 0, 0, 0}},
		&dns.CNAME{Hdr: answerHeader(dns.TypeCNAME), Target: "target.example."},
		&dns.AAAA{Hdr: answerHeader(dns.TypeAAAA), AAAA: net.IP(make([]byte, 16))},
		&dns.A{Hdr: answerHeader(dns.TypeA), A: nil},
	}}

	want := []byte{dnsCorePayloadLayoutVersion}
	want = binary.LittleEndian.AppendUint32(want, 3)
	want = append(want, byte(dns.TypeA))
	want = binary.LittleEndian.AppendUint16(want, 4)
	want = append(want, 0, 0, 0, 0)
	want = append(want, byte(dns.TypeAAAA))
	want = binary.LittleEndian.AppendUint16(want, 16)
	want = append(want, make([]byte, 16)...)
	want = append(want, byte(dns.TypeA))
	want = binary.LittleEndian.AppendUint16(want, 0)

	got := encodeAnswerRequest(message)
	if len(got) != len(want) {
		t.Fatalf("request length = %d, want %d", len(got), len(want))
	}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("request byte %d = %d, want %d", index, got[index], want[index])
		}
	}
}

func TestDNSCoreAnswerReportDecode(t *testing.T) {
	payload := []byte{dnsCorePayloadLayoutVersion, dnsInspectionBlocked}
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len("0.0.0.0,::1")))
	payload = append(payload, "0.0.0.0,::1"...)

	blocked, addresses, err := decodeAnswerResponse(payload)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !blocked || addresses != "0.0.0.0,::1" {
		t.Fatalf("report lost: blocked=%v addresses=%q", blocked, addresses)
	}

	clean := []byte{dnsCorePayloadLayoutVersion, 0}
	clean = binary.LittleEndian.AppendUint32(clean, 0)
	blocked, addresses, err = decodeAnswerResponse(clean)
	if err != nil || blocked || addresses != "" {
		t.Fatalf("empty report: blocked=%v addresses=%q err=%v", blocked, addresses, err)
	}
}

func TestDNSCoreAnswerReportRejectsDamage(t *testing.T) {
	valid := []byte{dnsCorePayloadLayoutVersion, dnsInspectionBlocked}
	valid = binary.LittleEndian.AppendUint32(valid, 3)
	valid = append(valid, "1.2"...)

	cases := map[string][]byte{
		"short header":   valid[:5],
		"wrong layout":   append([]byte{dnsCorePayloadLayoutVersion + 1}, valid[1:]...),
		"unknown flags":  append([]byte{dnsCorePayloadLayoutVersion, 0x80}, valid[2:]...),
		"trailing bytes": append(append([]byte{}, valid...), 'x'),
		"truncated text": valid[:len(valid)-1],
	}
	for name, payload := range cases {
		if _, _, err := decodeAnswerResponse(payload); err == nil {
			t.Fatalf("%s: expected an error", name)
		}
	}
}
