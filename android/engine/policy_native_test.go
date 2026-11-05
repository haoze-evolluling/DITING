//go:build cgo

// policy_native_test.go pins the Go <-> Rust boundary: the ABI version the loader checks and a set
// of fixed payloads whose verdicts must not drift. Rule semantics themselves are covered by the
// Rust test suite (`rust/diting-policy-core/tests/policy_core.rs`).
//
// The kernel is required, so a checkout without the built library fails instead of skipping: build
// it with `cargo build --release` in `rust/` (what `python rust/verify.py --go` does).

package tunnel

import (
	"testing"

	"github.com/miekg/dns"
)

func requireNativeKernel(t *testing.T) {
	t.Helper()
	if _, err := nativeKernel(); err != nil {
		t.Fatalf("Rust policy kernel unavailable (%v); build it with `cargo build --release` in rust/", err)
	}
}

func TestNativePolicyKernelAvailable(t *testing.T) {
	// loadNativeLibrary only hands out a library whose `diting_policy_abi_version` equals
	// nativePolicyABIVersion, so reaching this point proves the Go constant and
	// rust/diting-policy-core/src/ffi.rs agree.
	requireNativeKernel(t)
}

func TestNativePolicyFixedCases(t *testing.T) {
	requireNativeKernel(t)
	payload := `{
		"globalImportant": ["important.com"],
		"globalAllow": ["safe.allow.com"],
		"globalBlock": ["*.block.com", "ads.example.com"],
		"appRules": {"com.a": {"allow": ["x.com"], "block": ["y.com"], "important": ["z.com"]}},
		"invertedBlock": [{"pattern": "*.track.com", "source": "inv", "important": true, "excludedApps": ["com.a"]}],
		"specialBlock": [
			{"pattern": "^ad[s0-9]+\\.test\\.com$", "isRegex": true},
			{"pattern": "v6.com", "dnsType": "AAAA"}
		],
		"specialAllow": [{"pattern": "target.com", "appScope": "com.test.app"}]
	}`
	pe := newPolicyEngine()
	t.Cleanup(pe.close)
	if err := pe.applySnapshot(payload); err != nil {
		t.Fatalf("applySnapshot: %v", err)
	}
	cases := []struct {
		domain  string
		app     string
		qtype   uint16
		blocked bool
		reason  string
	}{
		{"important.com", "", dns.TypeA, true, "important"},
		{"safe.allow.com", "", dns.TypeA, false, "__ALLOW__"},
		{"x.block.com", "", dns.TypeA, true, ""},
		{"ads.example.com", "", dns.TypeA, true, "ads.example.com"},
		{"y.com", "com.a", dns.TypeA, true, ""},
		{"y.com", "com.b", dns.TypeA, false, ""},
		{"x.com", "com.a", dns.TypeA, false, "__ALLOW__"},
		{"z.com", "com.a", dns.TypeA, true, ""},
		{"q.track.com", "", dns.TypeA, true, ""},
		{"q.track.com", "com.a", dns.TypeA, false, ""},
		{"ad12.test.com", "", dns.TypeA, true, ""},
		{"v6.com", "", dns.TypeAAAA, true, ""},
		{"v6.com", "", dns.TypeA, false, ""},
		{"target.com", "com.test.app", dns.TypeA, false, "__ALLOW__"},
		{"other.org", "", dns.TypeA, false, ""},
	}
	for _, tc := range cases {
		// The cached path and the raw kernel call must agree: the cache is the only thing Go adds.
		blocked, reason := pe.evaluate(tc.domain, tc.app, tc.qtype)
		if blocked != tc.blocked || (tc.reason != "" && reason != tc.reason) {
			t.Errorf("evaluate(%q, %q, %d) = (%v, %q), want (%v, %q)",
				tc.domain, tc.app, tc.qtype, blocked, reason, tc.blocked, tc.reason)
		}
		uncachedBlocked, uncachedReason := pe.snapshot.Load().evaluateUncached(tc.domain, tc.app, tc.qtype)
		if uncachedBlocked != blocked || uncachedReason != reason {
			t.Errorf("evaluateUncached(%q, %q, %d) = (%v, %q), cache said (%v, %q)",
				tc.domain, tc.app, tc.qtype, uncachedBlocked, uncachedReason, blocked, reason)
		}
	}
}

// BenchmarkPolicyApplyLargeWithRust times the whole apply path: JSON decode, kernel build (rule
// tables, wildcard index, DTRI mmap) and the swap.
func BenchmarkPolicyApplyLargeWithRust(b *testing.B) {
	snapshotJSON := largePolicySnapshotJSON(b)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		pe := newPolicyEngine()
		if err := pe.applySnapshot(snapshotJSON); err != nil {
			b.Fatal(err)
		}
		pe.close()
	}
}
