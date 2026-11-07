// mitm_sniffer_payload.go is the byte layout the flow sniffer speaks
// (rust/diting-sniffer-core src/payload.rs).
//
// It lives outside the cgo file so the decode side can be tested without a C toolchain: a drifted
// layout byte, an unknown kind or a length that disagrees with the payload is rejected here,
// before any kernel call.

package tunnel

import (
	"encoding/binary"
	"fmt"
)

// snifferPayloadLayoutVersion must match `payload::LAYOUT_VERSION`.
const snifferPayloadLayoutVersion = 1

// Kinds the kernel reports; must match `payload::KIND_*`.
const (
	snifferKindUnknown = 0
	snifferKindTLS     = 1
	snifferKindHTTP    = 2
)

// decodeSnifferPayload reads `u8 layout | u8 kind | u32 host_len | host bytes`.
func decodeSnifferPayload(payload []byte) (uint8, []byte, error) {
	if len(payload) < 6 {
		return 0, nil, fmt.Errorf("sniffer payload is %d bytes", len(payload))
	}
	if payload[0] != snifferPayloadLayoutVersion {
		return 0, nil, fmt.Errorf("sniffer layout %d, expected %d", payload[0],
			snifferPayloadLayoutVersion)
	}
	kind := payload[1]
	if kind > snifferKindHTTP {
		return 0, nil, fmt.Errorf("sniffer kind %d is unknown", kind)
	}
	length := binary.LittleEndian.Uint32(payload[2:6])
	if uint64(length) != uint64(len(payload)-6) {
		return 0, nil, fmt.Errorf("sniffer declares %d host bytes, payload has %d", length,
			len(payload)-6)
	}
	return kind, payload[6:], nil
}
