package core

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
)

// sbPlanPayload builds a payload in the layout src/payload.rs writes, so the decoder can be tested
// without the library.
func sbPlanPayload(layout byte, flags byte, hashes [][sbHashSize]byte, question string, mutate func(*[]byte)) []byte {
	payload := []byte{layout, flags, byte(len(hashes))}
	for _, hash := range hashes {
		payload = append(payload, hash[:]...)
	}
	payload = binary.LittleEndian.AppendUint16(payload, uint16(len(question)))
	payload = append(payload, question...)
	if mutate != nil {
		mutate(&payload)
	}
	return payload
}

func TestDecodeSBPlanPayload(t *testing.T) {
	hash := [sbHashSize]byte{1, 2, 3}
	flags := byte(sbPlanFlagFound | sbPlanFlagBlocked)
	plan, err := decodeSBPlan(sbPlanPayload(sbPayloadLayoutVersion, flags, [][sbHashSize]byte{hash},
		"0102.sb.dns.adguard.com.", nil))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if plan.empty || !plan.found || !plan.blocked {
		t.Fatalf("flags decoded as %+v", plan)
	}
	if len(plan.hashes) != 1 || plan.hashes[0] != hash {
		t.Fatalf("hashes = %v", plan.hashes)
	}
	if plan.question != "0102.sb.dns.adguard.com." {
		t.Fatalf("question = %q", plan.question)
	}
}

func TestDecodeSBPlanPayloadRejectsMismatchedArtifacts(t *testing.T) {
	// A layout mismatch means the shipped .dll/.so and this binary are not the same build.
	if _, err := decodeSBPlan(sbPlanPayload(sbPayloadLayoutVersion+1, 0, nil, "", nil)); err == nil {
		t.Fatal("expected a layout mismatch error")
	}
	trailing := sbPlanPayload(sbPayloadLayoutVersion, 0, nil, "", func(payload *[]byte) {
		*payload = append(*payload, 0xEE)
	})
	if _, err := decodeSBPlan(trailing); err == nil {
		t.Fatal("expected a trailing-byte error")
	}
	if _, err := decodeSBPlan(sbPlanPayload(sbPayloadLayoutVersion, 0, nil, "", nil)[:3]); err == nil {
		t.Fatal("expected a truncated payload error")
	}
}

func TestEncodeSBApplyRequestLayout(t *testing.T) {
	queried := [][sbHashSize]byte{{0xAB, 0xCD}}
	request := encodeSBApplyRequest(sbServiceIDParental, queried, []string{"deadbeef", ""})

	if request[0] != sbPayloadLayoutVersion {
		t.Fatalf("layout = %d", request[0])
	}
	if request[1] != sbServiceIDParental {
		t.Fatalf("service = %d", request[1])
	}
	if request[2] != 1 {
		t.Fatalf("queried count = %d", request[2])
	}
	if request[3] != 0xAB || request[4] != 0xCD {
		t.Fatalf("first digest bytes = %v", request[3:5])
	}
	offset := 3 + sbHashSize
	if count := binary.LittleEndian.Uint16(request[offset:]); count != 2 {
		t.Fatalf("received count = %d", count)
	}
	offset += 2
	if length := binary.LittleEndian.Uint16(request[offset:]); length != 8 {
		t.Fatalf("first text length = %d", length)
	}
	if got := string(request[offset+2 : offset+2+8]); got != "deadbeef" {
		t.Fatalf("first text = %q", got)
	}
	offset += 2 + 8
	if length := binary.LittleEndian.Uint16(request[offset:]); length != 0 {
		t.Fatalf("second text length = %d", length)
	}
	if len(request) != offset+2 {
		t.Fatalf("payload size = %d, want %d", len(request), offset+2)
	}
}

func TestSBNativeLibraryCandidatesHonourExplicitPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "custom-lib.so")
	t.Setenv("DITING_SAFEBROWSING_CORE_LIB", path)
	candidates := sbNativeLibraryCandidates()
	if len(candidates) != 1 || candidates[0] != path {
		t.Fatalf("candidates = %v, want only %q", candidates, path)
	}
}

func TestSBNativeLibraryLookupFollowsTheExecutable(t *testing.T) {
	t.Setenv("DITING_SAFEBROWSING_CORE_LIB", "")
	candidates := sbNativeLibraryCandidates()
	executable, err := os.Executable()
	if err != nil {
		t.Skipf("os.Executable unavailable: %v", err)
	}
	want := filepath.Join(filepath.Dir(executable), sbNativeLibraryName())
	found := false
	for _, candidate := range candidates {
		if candidate == want {
			found = true
		}
	}
	if !found {
		t.Fatalf("candidates = %v, want %q among them", candidates, want)
	}
	local := filepath.Join("..", "..", "..", "..", "rust", "target", "release", sbNativeLibraryName())
	found = false
	for _, candidate := range candidates {
		if candidate == local {
			found = true
		}
	}
	if !found {
		t.Fatalf("candidates = %v, want %q among them", candidates, local)
	}
}
