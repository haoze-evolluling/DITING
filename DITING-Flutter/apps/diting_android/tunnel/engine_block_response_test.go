// engine_block_response_test.go pins the two defects behind A-018 and A-023:
//
//   - A-018: the block response mode was a plain Engine field written by the
//     gomobile setter (UI thread) and read by the DNS handlers (stack
//     goroutines) with no synchronization at all.
//   - A-023: ApplyDNSConfig applied the block response mode and the dynamic
//     block config before validating the provider list, so a snapshot the
//     caller was told to reject still changed how blocks were answered.

package tunnel

import (
	"testing"

	"github.com/miekg/dns"
)

func TestSetBlockResponseTypePublishesToReaders(t *testing.T) {
	e := NewEngine()
	if got := e.blockResponseType(); got != ResponseCustomIP {
		t.Fatalf("new engine must default to ResponseCustomIP, got %v", got)
	}

	for _, tc := range []struct {
		name  string
		input string
		want  ResponseType
	}{
		{"NXDOMAIN", "NXDOMAIN", ResponseNXDomain},
		{"REFUSED", "REFUSED", ResponseRefused},
		{"NODATA", "NODATA", ResponseNoData},
		{"unknown falls back to custom IP", "nonsense", ResponseCustomIP},
	} {
		t.Run(tc.name, func(t *testing.T) {
			e.SetBlockResponseType(tc.input)
			if got := e.blockResponseType(); got != tc.want {
				t.Fatalf("SetBlockResponseType(%q) => %v, want %v", tc.input, got, tc.want)
			}
		})
	}
}

func TestBlockResponseTypeSurvivesNilEngine(t *testing.T) {
	var e *Engine
	if got := e.blockResponseType(); got != ResponseCustomIP {
		t.Fatalf("nil engine must report the constructor default, got %v", got)
	}
}

// A rejected snapshot must not change engine behaviour.
func TestApplyDNSConfigRejectsWithoutPublishing(t *testing.T) {
	e := NewEngine()
	e.SetBlockResponseType("REFUSED")

	// No providers: rejected by the validation step that used to run *after*
	// the block response mode had already been applied.
	err := e.ApplyDNSConfig(`{"mode":"single","blockResponse":"NXDOMAIN","providers":[]}`)
	if err == nil {
		t.Fatal("expected an empty provider list to be rejected")
	}
	if got := e.blockResponseType(); got != ResponseRefused {
		t.Fatalf("rejected config changed the block response mode to %v", got)
	}

	// A bad provider endpoint must be rejected the same way.
	err = e.ApplyDNSConfig(`{"mode":"single","blockResponse":"NXDOMAIN","providers":[{"protocol":"PLAIN","server":"not-an-endpoint"}]}`)
	if err == nil {
		t.Fatal("expected an invalid provider endpoint to be rejected")
	}
	if got := e.blockResponseType(); got != ResponseRefused {
		t.Fatalf("rejected config changed the block response mode to %v", got)
	}
}

// The accepted snapshot must be published, and its dynamic block config must be
// visible to the standalone blocker.
func TestApplyDNSConfigPublishesOnSuccess(t *testing.T) {
	e := NewEngine()
	if err := e.ApplyDNSConfig(`{
		"mode":"single",
		"blockResponse":"NXDOMAIN",
		"dynamicResponse":{"enabled":true,"requestThreshold":2,"windowSeconds":60,"nxDomainDurationSeconds":30},
		"providers":[{"protocol":"PLAIN","server":"1.1.1.1:53"}]
	}`); err != nil {
		t.Fatalf("expected the snapshot to be accepted: %v", err)
	}

	if got := e.blockResponseType(); got != ResponseNXDomain {
		t.Fatalf("accepted config did not publish the block response mode, got %v", got)
	}

	e.mu.Lock()
	dynamic := e.dynamicResponse
	e.mu.Unlock()
	if !dynamic.Enabled || dynamic.RequestThreshold != 2 || dynamic.NXDomainSeconds != 30 {
		t.Fatalf("dynamic block config not published: %+v", dynamic)
	}
}

// blockDomainByPolicy installs a policy snapshot that blocks domain, so the
// standalone server would definitely synthesize a block if it evaluated rules.
func blockDomainByPolicy(t *testing.T, e *Engine, domain string) {
	t.Helper()
	if err := e.policyEngine.applySnapshot(`{"globalBlock":["` + domain + `"]}`); err != nil {
		t.Fatalf("applySnapshot: %v", err)
	}
}

// A-023: with filtering switched off the standalone server must forward instead
// of consulting the policy rules.
func TestServeDNSSkipsFilteringWhenFilterDNSDisabled(t *testing.T) {
	const domain = "blocked-by-policy.example"

	e, w := newAllowlistTestEngine(t, domain, "203.0.113.30")
	blockDomainByPolicy(t, e, domain)
	e.filterDNS.Store(false)

	e.serveDNS(w, allowlistQuery(t, domain), "", allowlistTestUID)
	if w.msg == nil {
		t.Fatal("no response written")
	}
	if w.msg.Rcode != dns.RcodeSuccess {
		t.Fatalf("filtering disabled must not synthesize a block, got rcode %d", w.msg.Rcode)
	}
	if len(w.msg.Answer) == 0 {
		t.Fatalf("expected the forwarded answer, got %v", w.msg)
	}
}

// The control: with filtering enabled the very same rule must block.
func TestServeDNSBlocksWhenFilterDNSEnabled(t *testing.T) {
	const domain = "blocked-by-policy.example"

	e, w := newAllowlistTestEngine(t, domain, "203.0.113.30")
	blockDomainByPolicy(t, e, domain)
	e.filterDNS.Store(true)
	e.SetBlockResponseType("NXDOMAIN")

	e.serveDNS(w, allowlistQuery(t, domain), "", allowlistTestUID)
	if w.msg == nil {
		t.Fatal("no response written")
	}
	if w.msg.Rcode != dns.RcodeNameError {
		t.Fatalf("filtering enabled must block via the policy rule, got rcode %d", w.msg.Rcode)
	}
}

// A-023: the full-tunnel DNS path used to switch on the raw configured mode and
// never consulted the dynamic block tracker, so a domain that had crossed the
// request threshold was not escalated to NXDOMAIN there.
func TestFullTunnelBlockEscalatesViaDynamicBlock(t *testing.T) {
	const domain = "chatty.example"

	e := NewEngine()
	e.storeBlockResponseType(ResponseCustomIP)
	e.mu.Lock()
	e.dynamicResponse = dynamicBlockConfig{
		Enabled:          true,
		RequestThreshold: 2,
		WindowSeconds:    60,
		NXDomainSeconds:  30,
	}
	e.mu.Unlock()

	// responseFor answers NODATA for every block while the domain is below the
	// threshold and escalates to NXDOMAIN once the count exceeds it. That is the
	// semantics the standalone server has always had; the full-tunnel path now
	// shares it instead of ignoring the tracker.
	if got := e.effectiveBlockResponseType(domain); got != ResponseNoData {
		t.Fatalf("first evaluation must stay below the threshold, got %v", got)
	}
	if got := e.effectiveBlockResponseType(domain); got != ResponseNoData {
		t.Fatalf("second evaluation must stay below the threshold, got %v", got)
	}
	if got := e.effectiveBlockResponseType(domain); got != ResponseNXDomain {
		t.Fatalf("third evaluation must escalate to NXDOMAIN, got %v", got)
	}

	// A different domain keeps its own counter.
	if got := e.effectiveBlockResponseType("quiet.example"); got != ResponseNoData {
		t.Fatalf("unrelated domain must not inherit the escalation, got %v", got)
	}

	// With the tracker disabled the configured mode is passed through untouched.
	e.mu.Lock()
	e.dynamicResponse = dynamicBlockConfig{}
	e.mu.Unlock()
	if got := e.effectiveBlockResponseType("another.example"); got != ResponseCustomIP {
		t.Fatalf("disabled dynamic blocking must return the configured mode, got %v", got)
	}
}


