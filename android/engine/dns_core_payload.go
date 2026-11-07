// dns_core_payload.go is the byte layout the DNS answer kernel speaks
// (rust/diting-dns-core/src/payload.rs).
//
// It lives outside the cgo file so the encode/decode side can be tested without a C toolchain: a
// drifted layout byte or a length that disagrees with the payload is rejected here, before any
// kernel call.

package tunnel

import (
	"encoding/binary"
	"fmt"

	"github.com/miekg/dns"
)

// dnsCorePayloadLayoutVersion must match `payload::LAYOUT_VERSION`.
const dnsCorePayloadLayoutVersion = 1

// dnsInspectionBlocked is the "every A/AAAA answer is null or loopback" bit of the report.
const dnsInspectionBlocked = 1 << 0

// encodeAnswerRequest packs the A/AAAA records of an answer into the inspection request. Only
// those two types reach the kernel: the blocked verdict and the logged address list ignore
// everything else, exactly like the two Go helpers it replaced.
func encodeAnswerRequest(msg *dns.Msg) []byte {
	count := 0
	for _, rr := range msg.Answer {
		switch rr.(type) {
		case *dns.A, *dns.AAAA:
			count++
		}
	}

	payload := make([]byte, 0, 5+count*19)
	payload = append(payload, dnsCorePayloadLayoutVersion)
	payload = binary.LittleEndian.AppendUint32(payload, uint32(count))
	for _, rr := range msg.Answer {
		switch record := rr.(type) {
		case *dns.A:
			payload = append(payload, byte(dns.TypeA))
			payload = binary.LittleEndian.AppendUint16(payload, uint16(len(record.A)))
			payload = append(payload, record.A...)
		case *dns.AAAA:
			payload = append(payload, byte(dns.TypeAAAA))
			payload = binary.LittleEndian.AppendUint16(payload, uint16(len(record.AAAA)))
			payload = append(payload, record.AAAA...)
		}
	}
	return payload
}

// decodeAnswerResponse reads the inspection result: the blocked verdict and the comma separated
// unique address list (empty when the answer carried no address records).
func decodeAnswerResponse(payload []byte) (blocked bool, addresses string, err error) {
	const header = 1 + 1 + 4
	if len(payload) < header {
		return false, "", fmt.Errorf("answer report payload is %d bytes", len(payload))
	}
	if payload[0] != dnsCorePayloadLayoutVersion {
		return false, "", fmt.Errorf("answer report payload layout %d, expected %d",
			payload[0], dnsCorePayloadLayoutVersion)
	}
	flags := payload[1]
	if flags&^byte(dnsInspectionBlocked) != 0 {
		return false, "", fmt.Errorf("answer report payload has unknown flags %#x", flags)
	}
	length := int(binary.LittleEndian.Uint32(payload[2:]))
	if length != len(payload)-header {
		return false, "", fmt.Errorf("answer report payload declares %d text bytes, has %d",
			length, len(payload)-header)
	}
	return flags&dnsInspectionBlocked != 0, string(payload[header:]), nil
}
