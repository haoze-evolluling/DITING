// mitm_sniffer_payload_test.go pins the payload the kernel writes, without needing the library.

package tunnel

import (
	"encoding/binary"
	"testing"
)

func encodeSnifferTestPayload(kind byte, host []byte) []byte {
	payload := make([]byte, 6+len(host))
	payload[0] = snifferPayloadLayoutVersion
	payload[1] = kind
	binary.LittleEndian.PutUint32(payload[2:6], uint32(len(host)))
	copy(payload[6:], host)
	return payload
}

func TestDecodeSnifferPayload(t *testing.T) {
	payload := encodeSnifferTestPayload(snifferKindHTTP, []byte("example.com"))
	kind, host, err := decodeSnifferPayload(payload)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if kind != snifferKindHTTP {
		t.Fatalf("kind is %d", kind)
	}
	if string(host) != "example.com" {
		t.Fatalf("host is %q", host)
	}

	unknown := encodeSnifferTestPayload(snifferKindUnknown, nil)
	if kind, host, err := decodeSnifferPayload(unknown); err != nil || kind != snifferKindUnknown || len(host) != 0 {
		t.Fatalf("unknown: kind=%d host=%q err=%v", kind, host, err)
	}

	cases := map[string][]byte{
		"short":           {snifferPayloadLayoutVersion, snifferKindTLS, 0, 0},
		"layout drift":    {snifferPayloadLayoutVersion + 1, snifferKindTLS, 0, 0, 0, 0},
		"unknown kind":    {snifferPayloadLayoutVersion, 9, 0, 0, 0, 0},
		"length too big":  {snifferPayloadLayoutVersion, snifferKindTLS, 9, 0, 0, 0, 'x'},
		"trailing bytes":  {snifferPayloadLayoutVersion, snifferKindTLS, 1, 0, 0, 0, 'x', 'y'},
		"undeclared byte": {snifferPayloadLayoutVersion, snifferKindTLS, 0, 0, 0, 0, 'x'},
	}
	for name, payload := range cases {
		if _, _, err := decodeSnifferPayload(payload); err == nil {
			t.Fatalf("%s: payload was accepted", name)
		}
	}
}

func TestEncodeSnifferTestPayloadLayout(t *testing.T) {
	payload := encodeSnifferTestPayload(snifferKindTLS, []byte("a.com"))
	if payload[0] != snifferPayloadLayoutVersion || payload[1] != snifferKindTLS {
		t.Fatalf("header is %v", payload[:2])
	}
	if got := binary.LittleEndian.Uint32(payload[2:6]); got != 5 {
		t.Fatalf("declared length is %d", got)
	}
	if string(payload[6:]) != "a.com" {
		t.Fatalf("payload carries %q", payload[6:])
	}
}
