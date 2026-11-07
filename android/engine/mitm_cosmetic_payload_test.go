// mitm_cosmetic_payload_test.go pins the payload the kernel writes, without needing the library.

package tunnel

import "testing"

func TestDecodeCosmeticTextPayload(t *testing.T) {
	payload := encodeCosmeticLinkTag(`<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css?h=a.com">`)
	got, err := decodeCosmeticText(payload, "link tag")
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got != string(payload[5:]) {
		t.Fatalf("decoded %q", got)
	}

	cases := map[string][]byte{
		"short":          {cosmeticPayloadLayoutVersion, 0, 0, 0},
		"layout drift":   {cosmeticPayloadLayoutVersion + 1, 1, 0, 0, 0, 'x'},
		"length too big": {cosmeticPayloadLayoutVersion, 9, 0, 0, 0, 'x'},
		"trailing bytes": {cosmeticPayloadLayoutVersion, 1, 0, 0, 0, 'x', 'y'},
	}
	for name, payload := range cases {
		if _, err := decodeCosmeticText(payload, "link tag"); err == nil {
			t.Fatalf("%s: payload was accepted", name)
		}
	}
}

func TestEncodeCosmeticLinkTagLayout(t *testing.T) {
	payload := encodeCosmeticLinkTag("abc")
	if payload[0] != cosmeticPayloadLayoutVersion {
		t.Fatalf("layout byte is %d", payload[0])
	}
	if got := uint32(payload[1]) | uint32(payload[2])<<8 | uint32(payload[3])<<16 | uint32(payload[4])<<24; got != 3 {
		t.Fatalf("declared length is %d", got)
	}
	if string(payload[5:]) != "abc" {
		t.Fatalf("payload carries %q", payload[5:])
	}
}
