// mitm_cosmetic_payload.go is the byte layout the cosmetic kernel speaks (rust/diting-cosmetic-core
// src/payload.rs).
//
// It lives outside the cgo file so the decode side can be tested without a C toolchain: a drifted
// layout byte or a length that disagrees with the payload is rejected here, before any kernel call.

package tunnel

import (
	"encoding/binary"
	"fmt"
)

// cosmeticPayloadLayoutVersion must match `payload::LAYOUT_VERSION`.
const cosmeticPayloadLayoutVersion = 1

// decodeCosmeticText reads the layout-prefixed text payload the kernel returns.
func decodeCosmeticText(payload []byte, what string) (string, error) {
	if len(payload) < 5 {
		return "", fmt.Errorf("%s payload is %d bytes", what, len(payload))
	}
	if payload[0] != cosmeticPayloadLayoutVersion {
		return "", fmt.Errorf("%s layout %d, expected %d", what, payload[0],
			cosmeticPayloadLayoutVersion)
	}
	length := binary.LittleEndian.Uint32(payload[1:5])
	if uint64(length) != uint64(len(payload)-5) {
		return "", fmt.Errorf("%s declares %d bytes, payload has %d", what, length, len(payload)-5)
	}
	return string(payload[5:]), nil
}

// encodeCosmeticLinkTag is the payload `diting_cosmetic_new` reads.
func encodeCosmeticLinkTag(tag string) []byte {
	payload := make([]byte, 5+len(tag))
	payload[0] = cosmeticPayloadLayoutVersion
	binary.LittleEndian.PutUint32(payload[1:5], uint32(len(tag)))
	copy(payload[5:], tag)
	return payload
}

