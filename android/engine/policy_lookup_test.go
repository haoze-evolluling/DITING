// policy_lookup_test.go pins the observable behaviour of the decision cache that now lives inside
// the Rust kernel (`rust/diting-policy-core/src/cache.rs`): a reload must not serve a stale answer,
// and the app/qtype dimensions must only be part of the key when some rule reads them.
//
// Eviction (CLOCK + frequency aging) and hot-key prewarming are cache internals, so their fixed
// expectations live in the Rust unit tests next to the implementation instead of reaching through
// the FFI just to inspect a table.

package tunnel

import (
	"testing"

	"github.com/miekg/dns"
)

func TestPolicyDecisionCacheTracksSnapshotReload(t *testing.T) {
	pe := newPolicyEngine()
	if err := pe.applySnapshot(`{"globalBlock":["*.ads.com"]}`); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		if blocked, _ := pe.evaluate("x.ads.com", "", dns.TypeA); !blocked {
			t.Fatal("want blocked before reload")
		}
	}
	if err := pe.applySnapshot(`{"globalAllow":["x.ads.com"],"globalBlock":["*.ads.com"]}`); err != nil {
		t.Fatal(err)
	}
	// Raw input: the kernel folds case and drops the trailing dot itself.
	if blocked, reason := pe.evaluate("X.Ads.com.", "", dns.TypeA); blocked || reason != "__ALLOW__" {
		t.Fatalf("after reload got (%v,%q), want allow", blocked, reason)
	}
}

func TestPolicyDecisionCacheKeepsAppAndQtypeApart(t *testing.T) {
	pe := newPolicyEngine()
	snapshot := `{
		"appRules": {"com.a": {"block": ["t.example.com"]}},
		"specialBlock": [{"pattern": "q.example.com", "source": "s", "dnsType": "AAAA"}]
	}`
	if err := pe.applySnapshot(snapshot); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if blocked, _ := pe.evaluate("t.example.com", "com.a", dns.TypeA); !blocked {
			t.Fatal("app rule should block com.a")
		}
		if blocked, _ := pe.evaluate("t.example.com", "com.b", dns.TypeA); blocked {
			t.Fatal("app rule must not leak to com.b via cache")
		}
		if blocked, _ := pe.evaluate("q.example.com", "", dns.TypeAAAA); !blocked {
			t.Fatal("dnsType rule should block AAAA")
		}
		if blocked, _ := pe.evaluate("q.example.com", "", dns.TypeA); blocked {
			t.Fatal("dnsType rule must not leak to A via cache")
		}
	}
}
