package core

// ratelimit_native_test.go pins the payload layout and the normalisation the Go side sees through
// the C ABI. The decision logic itself is covered by the Rust corpus, generated from the Go
// implementation before the move.

import (
	"math"
	"testing"
)

func TestRateLimitNativeConfigPayload(t *testing.T) {
	cfg := RateLimitConfig{
		Enabled:    true,
		Rate:       12.5,
		Burst:      40,
		IPv4Prefix: 24,
		IPv6Prefix: 56,
		ExemptIPs:  []string{"127.0.0.1", "10.0.0.0/8"},
	}
	reader := &payloadReader{data: encodeRateLimitConfig(cfg)}

	layout, err := reader.u8()
	if err != nil || layout != rateLimitPayloadLayoutVersion {
		t.Fatalf("layout = %d, err = %v", layout, err)
	}
	enabled, err := reader.u8()
	if err != nil || enabled != 1 {
		t.Fatalf("enabled = %d, err = %v", enabled, err)
	}
	rateBits, err := reader.u64()
	if err != nil || math.Float64frombits(rateBits) != cfg.Rate {
		t.Fatalf("rate bits = %d, err = %v", rateBits, err)
	}
	for _, want := range []int64{int64(cfg.Burst), int64(cfg.IPv4Prefix), int64(cfg.IPv6Prefix)} {
		value, err := reader.u64()
		if err != nil || int64(value) != want {
			t.Fatalf("field = %d, want %d, err = %v", int64(value), want, err)
		}
	}
	count, err := reader.u32()
	if err != nil || count != uint32(len(cfg.ExemptIPs)) {
		t.Fatalf("exemption count = %d, err = %v", count, err)
	}
	for _, want := range cfg.ExemptIPs {
		entry, err := reader.text32()
		if err != nil || entry != want {
			t.Fatalf("exemption = %q, want %q, err = %v", entry, want, err)
		}
	}
	if err := expectPayloadEnd(reader, "config"); err != nil {
		t.Fatal(err)
	}
}

func TestRateLimitNativeInfoNormalizesThroughTheKernel(t *testing.T) {
	limiter, err := buildRateLimitNativeLimiter(RateLimitConfig{Enabled: true})
	if err != nil {
		t.Fatalf("buildRateLimitNativeLimiter: %v", err)
	}
	defer limiter.free()

	info, err := limiter.info()
	if err != nil {
		t.Fatalf("info: %v", err)
	}
	if !info.Enabled || info.Rate != 50 || info.Burst != 100 ||
		info.IPv4Prefix != 32 || info.IPv6Prefix != 128 || info.Buckets != 0 ||
		info.ExemptIPs != 0 || info.ExemptNets != 0 {
		t.Fatalf("unexpected normalised info: %+v", info)
	}
}

func TestRateLimitNativeInfoRejectsAStaleLayout(t *testing.T) {
	for _, payload := range [][]byte{
		nil,
		{rateLimitPayloadLayoutVersion + 1, 0},
		{rateLimitPayloadLayoutVersion},
		{rateLimitPayloadLayoutVersion, 0, 0},
	} {
		if _, err := decodeRateLimitInfo(payload); err == nil {
			t.Fatalf("payload %v should be rejected", payload)
		}
	}
}
