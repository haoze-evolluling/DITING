// policy_lookup_test.go pins the decision cache that sits between the call sites and the Rust
// policy kernel: a reload must not serve a stale answer, and the app/qtype dimensions must only be
// part of the key when the kernel says some rule reads them.

package tunnel

import (
	"fmt"
	"testing"
	"time"

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

func TestPolicyDecisionCacheEvictionAndPrewarm(t *testing.T) {
	pe := newPolicyEngine()
	if err := pe.applySnapshot(`{"globalBlock":["hot.com"]}`); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 20; i++ {
		pe.evaluate("hot.com", "", dns.TypeA)
	}
	for i := 0; i < decisionCacheShards*decisionCacheShardSize*2; i++ {
		pe.evaluate(fmt.Sprintf("d%d.example", i), "", dns.TypeA)
	}
	prev := pe.snapshot.Load()
	if _, _, ok := prev.cache.get(decisionKey{domain: "hot.com"}); !ok {
		t.Fatal("frequently used entry should survive CLOCK eviction")
	}

	if err := pe.applySnapshot(`{"globalAllow":["hot.com"],"globalBlock":["*.ads.com"]}`); err != nil {
		t.Fatal(err)
	}
	next := pe.snapshot.Load()
	// Prewarming runs in the background: wait for the hot key to show up instead of racing it.
	deadline := time.Now().Add(5 * time.Second)
	for {
		blocked, reason, ok := next.cache.get(decisionKey{domain: "hot.com"})
		if ok {
			if blocked || reason != "__ALLOW__" {
				t.Fatalf("prewarmed entry = (%v,%q), want fresh allow decision", blocked, reason)
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("hot key was not prewarmed into the new snapshot")
		}
		time.Sleep(5 * time.Millisecond)
	}
}
