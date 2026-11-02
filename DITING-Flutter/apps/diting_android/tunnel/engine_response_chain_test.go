package tunnel

import (
	"net"
	"strings"
	"testing"

	"github.com/miekg/dns"
)

// chainTestSnapshot mirrors the JSON shape pushed by ApplyRuleSnapshot.
const chainTestSnapshot = `{
  "globalBlock": ["tracker.example.com", "blocked-svcb.example.net"],
  "globalAllow": ["allowed-hop.example.org"]
}`

func newChainTestEngine(t *testing.T, snapshotJSON string) *Engine {
	t.Helper()
	e := &Engine{policyEngine: newPolicyEngine()}
	if err := e.policyEngine.applySnapshot(snapshotJSON); err != nil {
		t.Fatalf("applySnapshot: %v", err)
	}
	return e
}

func cnameRR(name, target string) *dns.CNAME {
	return &dns.CNAME{
		Hdr:    dns.RR_Header{Name: dns.Fqdn(name), Rrtype: dns.TypeCNAME, Class: dns.ClassINET, Ttl: 300},
		Target: dns.Fqdn(target),
	}
}

func aRR(name, ip string) *dns.A {
	return &dns.A{
		Hdr: dns.RR_Header{Name: dns.Fqdn(name), Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60},
		A:   net.ParseIP(ip),
	}
}

func svcbRR(name, target string) *dns.SVCB {
	return &dns.SVCB{
		Hdr:      dns.RR_Header{Name: dns.Fqdn(name), Rrtype: dns.TypeSVCB, Class: dns.ClassINET, Ttl: 300},
		Priority: 1,
		Target:   dns.Fqdn(target),
	}
}

func httpsRR(name, target string) *dns.HTTPS {
	return &dns.HTTPS{SVCB: dns.SVCB{
		Hdr:      dns.RR_Header{Name: dns.Fqdn(name), Rrtype: dns.TypeHTTPS, Class: dns.ClassINET, Ttl: 300},
		Priority: 1,
		Target:   dns.Fqdn(target),
	}}
}

func chainQueryMsg(name string, qtype uint16, answers ...dns.RR) *dns.Msg {
	msg := new(dns.Msg)
	msg.SetQuestion(dns.Fqdn(name), qtype)
	msg.Answer = answers
	return msg
}

func TestCheckResponseChain_CNAMEHit(t *testing.T) {
	e := newChainTestEngine(t, chainTestSnapshot)
	msg := chainQueryMsg("first-party.example.com", dns.TypeA,
		cnameRR("first-party.example.com", "tracker.example.com"),
		aRR("tracker.example.com", "203.0.113.10"),
	)
	blocked, reason := e.checkResponseChain(msg, "com.example.app")
	if !blocked {
		t.Fatal("expected CNAME chain hit to block the response")
	}
	if !strings.HasPrefix(reason, "cname:tracker.example.com") {
		t.Fatalf("unexpected reason: %q", reason)
	}
}

func TestCheckResponseChain_AllowlistOnlyExemptsTarget(t *testing.T) {
	e := newChainTestEngine(t, chainTestSnapshot)

	// Chain contains only an allowlisted hop: must pass.
	msg := chainQueryMsg("first-party.example.com", dns.TypeA,
		cnameRR("first-party.example.com", "allowed-hop.example.org"),
		aRR("allowed-hop.example.org", "192.0.2.1"),
	)
	if blocked, _ := e.checkResponseChain(msg, ""); blocked {
		t.Fatal("allowlisted target must not block the response")
	}

	// Allowlisted hop followed by a blocked hop: whitelist only exempts the
	// first target; the second hop must still block the whole answer.
	msg.Answer = []dns.RR{
		cnameRR("first-party.example.com", "allowed-hop.example.org"),
		cnameRR("allowed-hop.example.org", "tracker.example.com"),
		aRR("tracker.example.com", "203.0.113.10"),
	}
	blocked, reason := e.checkResponseChain(msg, "")
	if !blocked || !strings.HasPrefix(reason, "cname:tracker.example.com") {
		t.Fatalf("expected later chain hop to block, got blocked=%v reason=%q", blocked, reason)
	}
}

func TestCheckResponseChain_SVCBTargetHit(t *testing.T) {
	e := newChainTestEngine(t, chainTestSnapshot)

	// HTTPS (type 65) TargetName.
	msg := chainQueryMsg("edge.example.net", dns.TypeHTTPS,
		httpsRR("edge.example.net", "blocked-svcb.example.net"),
	)
	blocked, reason := e.checkResponseChain(msg, "")
	if !blocked || !strings.HasPrefix(reason, "svcb:blocked-svcb.example.net") {
		t.Fatalf("expected HTTPS TargetName hit, got blocked=%v reason=%q", blocked, reason)
	}

	// SVCB (type 64) TargetName.
	svcbMsg := chainQueryMsg("edge.example.net", dns.TypeSVCB,
		svcbRR("edge.example.net", "blocked-svcb.example.net"),
	)
	if blocked, _ := e.checkResponseChain(svcbMsg, ""); !blocked {
		t.Fatal("expected SVCB (type 64) TargetName hit")
	}
}

func TestCheckResponseChain_InactiveEngineSkips(t *testing.T) {
	e := &Engine{policyEngine: newPolicyEngine()} // initialized=false
	msg := chainQueryMsg("first-party.example.com", dns.TypeA,
		cnameRR("first-party.example.com", "tracker.example.com"),
	)
	if blocked, _ := e.checkResponseChain(msg, ""); blocked {
		t.Fatal("inactive policy engine must skip chain filtering")
	}
}

func TestCheckResponseChain_NoRulesSkips(t *testing.T) {
	e := newChainTestEngine(t, `{"globalBlock":[]}`)
	msg := chainQueryMsg("first-party.example.com", dns.TypeA,
		cnameRR("first-party.example.com", "tracker.example.com"),
	)
	if blocked, _ := e.checkResponseChain(msg, ""); blocked {
		t.Fatal("engine without rules must skip chain filtering")
	}
}

func TestCheckResponseChain_NoChainUnchanged(t *testing.T) {
	e := newChainTestEngine(t, chainTestSnapshot)
	msg := chainQueryMsg("first-party.example.com", dns.TypeA,
		aRR("first-party.example.com", "192.0.2.7"),
	)
	if blocked, reason := e.checkResponseChain(msg, ""); blocked || reason != "" {
		t.Fatalf("plain A answer must pass unchanged, got blocked=%v reason=%q", blocked, reason)
	}
}

func TestCheckResponseChain_TargetNormalization(t *testing.T) {
	e := newChainTestEngine(t, chainTestSnapshot)
	msg := chainQueryMsg("first-party.example.com", dns.TypeA,
		cnameRR("first-party.example.com", "Tracker.Example.COM."),
	)
	blocked, reason := e.checkResponseChain(msg, "")
	if !blocked || !strings.HasPrefix(reason, "cname:tracker.example.com") {
		t.Fatalf("case/trailing-dot normalization failed: blocked=%v reason=%q", blocked, reason)
	}
}
