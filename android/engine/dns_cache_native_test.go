//go:build cgo

// dns_cache_native_test.go pins the boundary with rust/diting-dns-cache-core: the config payload
// the Go side encodes, and the hit payload decoder on the other side of the container ABI.

package tunnel

import (
	"encoding/binary"
	"testing"
)

func TestNativeDNSCacheConfigPayload(t *testing.T) {
	payload := encodeDNSCacheConfig(dnsCacheConfig{
		Enabled:              true,
		Mode:                 "fixed_ttl",
		MaxTTLSeconds:        60,
		FixedTTLSeconds:      120,
		MinTTLEnabled:        true,
		MinTTLSeconds:        5,
		StaleFallbackEnabled: true,
		StaleFallbackSeconds: 30,
		NegativeTTLSeconds:   10,
	})

	want := []byte{dnsCachePayloadLayoutVersion,
		dnsCacheFlagEnabled | dnsCacheFlagMinTTL | dnsCacheFlagStaleFallback}
	for _, value := range []int64{60, 120, 5, 30, 10} {
		want = binary.LittleEndian.AppendUint64(want, uint64(value))
	}
	want = binary.LittleEndian.AppendUint32(want, uint32(len("fixed_ttl")))
	want = append(want, "fixed_ttl"...)

	if len(payload) != len(want) {
		t.Fatalf("payload length = %d, want %d", len(payload), len(want))
	}
	for index := range want {
		if payload[index] != want[index] {
			t.Fatalf("payload byte %d = %d, want %d", index, payload[index], want[index])
		}
	}
}

func hitPayload(stale byte, flags byte, wire []byte, targets []chainTarget, ips []string, resolved string) []byte {
	payload := []byte{dnsCachePayloadLayoutVersion, stale, flags}
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len(wire)))
	payload = append(payload, wire...)
	payload = binary.LittleEndian.AppendUint16(payload, uint16(len(targets)))
	for _, target := range targets {
		code := byte(0)
		if target.kind == "svcb" {
			code = 1
		}
		payload = append(payload, code)
		payload = binary.LittleEndian.AppendUint32(payload, uint32(len(target.domain)))
		payload = append(payload, target.domain...)
	}
	payload = binary.LittleEndian.AppendUint16(payload, uint16(len(ips)))
	for _, ip := range ips {
		payload = binary.LittleEndian.AppendUint32(payload, uint32(len(ip)))
		payload = append(payload, ip...)
	}
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len(resolved)))
	return append(payload, resolved...)
}

func TestNativeDNSCacheHitPayloadDecode(t *testing.T) {
	wire := []byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}
	payload := hitPayload(1, 1, wire,
		[]chainTarget{{domain: "chain.example", kind: "cname"}},
		[]string{"192.0.2.7"}, "192.0.2.7")

	hit, err := decodeDNSCacheHit(payload)
	if err != nil {
		t.Fatalf("decode hit: %v", err)
	}
	if !hit.stale || !hit.isNegative {
		t.Fatalf("stale=%v negative=%v", hit.stale, hit.isNegative)
	}
	if string(hit.wire) != string(wire) {
		t.Fatalf("wire = %v", hit.wire)
	}
	if len(hit.chainTargets) != 1 || hit.chainTargets[0] != (chainTarget{domain: "chain.example", kind: "cname"}) {
		t.Fatalf("chain targets = %+v", hit.chainTargets)
	}
	if len(hit.ipList) != 1 || hit.ipList[0] != "192.0.2.7" {
		t.Fatalf("IPs = %v", hit.ipList)
	}
	if hit.resolvedIPs != "192.0.2.7" {
		t.Fatalf("resolved IPs = %q", hit.resolvedIPs)
	}
}

func TestNativeDNSCacheHitPayloadRejectsBadInput(t *testing.T) {
	good := hitPayload(0, 0, make([]byte, 12), nil, nil, "")

	wrongLayout := append([]byte(nil), good...)
	wrongLayout[0] = dnsCachePayloadLayoutVersion + 1
	if _, err := decodeDNSCacheHit(wrongLayout); err == nil {
		t.Fatal("a stale layout byte must be rejected")
	}

	if _, err := decodeDNSCacheHit(good[:len(good)-1]); err == nil {
		t.Fatal("a truncated payload must be rejected")
	}
	if _, err := decodeDNSCacheHit(append(append([]byte(nil), good...), 0)); err == nil {
		t.Fatal("a trailing byte must be rejected")
	}

	unknownKind := hitPayload(0, 0, make([]byte, 12), []chainTarget{{domain: "x", kind: "other"}}, nil, "")
	unknownKind[7+12+2] = 2 // kind byte of the first chain target
	if _, err := decodeDNSCacheHit(unknownKind); err == nil {
		t.Fatal("an unknown chain kind must be rejected")
	}
}

func TestNativeDNSCacheStatsAndSnapshotDecodeErrors(t *testing.T) {
	if _, err := decodeDNSCacheStats([]byte{dnsCachePayloadLayoutVersion}); err == nil {
		t.Fatal("a truncated stats payload must be rejected")
	}
	if _, err := decodeDNSCacheSnapshot(nil); err == nil {
		t.Fatal("an empty snapshot payload must be rejected")
	}
}
