//go:build cgo

// mitm_filter_native_test.go pins the boundary with rust/diting-mitm-core: the report payload the
// kernel encodes is decoded here byte for byte, and the failure paths (truncation, layout drift,
// trailing bytes) must be rejected instead of misread.

package tunnel

import (
	"encoding/binary"
	"testing"
)

// mitmReportPayload rebuilds the payload rust/diting-mitm-core/src/payload.rs encodes.
func mitmReportPayload(flags byte, count, threshold uint32, ttlMs int64, host, reason, writeError string) []byte {
	payload := []byte{mitmFilterPayloadLayoutVersion, flags}
	payload = binary.LittleEndian.AppendUint32(payload, count)
	payload = binary.LittleEndian.AppendUint32(payload, threshold)
	payload = binary.LittleEndian.AppendUint64(payload, uint64(ttlMs))
	for _, text := range []string{host, reason, writeError} {
		payload = binary.LittleEndian.AppendUint32(payload, uint32(len(text)))
		payload = append(payload, text...)
	}
	return payload
}

func TestMitmReportPayloadLayout(t *testing.T) {
	payload := mitmReportPayload(mitmReportRecorded|mitmReportBlacklisted|mitmReportAdded, 3, 3, 604800000,
		"example.com", "handshake_failure (3 failures)", "")

	want := []byte{mitmFilterPayloadLayoutVersion,
		mitmReportRecorded | mitmReportBlacklisted | mitmReportAdded, 3, 0, 0, 0, 3, 0, 0, 0}
	want = binary.LittleEndian.AppendUint64(want, 604800000)
	for _, text := range []string{"example.com", "handshake_failure (3 failures)", ""} {
		want = binary.LittleEndian.AppendUint32(want, uint32(len(text)))
		want = append(want, text...)
	}

	if len(payload) != len(want) {
		t.Fatalf("payload length = %d, want %d", len(payload), len(want))
	}
	for index := range want {
		if payload[index] != want[index] {
			t.Fatalf("payload byte %d = %d, want %d", index, payload[index], want[index])
		}
	}

	report, err := decodeMitmReport(payload)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !report.recorded || !report.blacklisted || !report.added {
		t.Fatalf("flags lost: %+v", report)
	}
	if report.count != 3 || report.threshold != 3 {
		t.Fatalf("streak fields lost: %+v", report)
	}
	if report.host != "example.com" || report.reason != "handshake_failure (3 failures)" {
		t.Fatalf("text fields lost: %+v", report)
	}
	if report.ttlMs != 604800000 || report.writeError != "" {
		t.Fatalf("entry fields lost: %+v", report)
	}
}

func TestMitmReportPayloadRejectsBadInput(t *testing.T) {
	// A layout byte from another version is a hard error, not a misread.
	drifted := mitmReportPayload(0, 1, 3, 0, "a", "", "")
	drifted[0]++
	if _, err := decodeMitmReport(drifted); err == nil {
		t.Fatal("expected a layout mismatch")
	}

	// Every truncation must be detected.
	full := mitmReportPayload(mitmReportBlacklisted|mitmReportAdded, 0, 0, 1, "a", "r", "w")
	for length := 0; length < len(full); length++ {
		if _, err := decodeMitmReport(full[:length]); err == nil {
			t.Fatalf("truncation to %d bytes was accepted", length)
		}
	}

	// Trailing bytes are an error too.
	trailing := append(append([]byte{}, full...), 0)
	if _, err := decodeMitmReport(trailing); err == nil {
		t.Fatal("expected trailing bytes to be rejected")
	}
}
