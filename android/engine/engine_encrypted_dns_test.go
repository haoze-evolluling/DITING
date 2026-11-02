// engine_encrypted_dns_test.go pins the "阻断加密 DNS (DoT)" switch.
//
// SetBlockEncryptedDns used to be a dead switch: it stored an atomic.Bool that
// nothing ever read, while all three data-plane entry points dropped port 853
// unconditionally. The user-facing toggle therefore had no effect in either
// direction. These tests pin the gating predicate, including the fail-closed
// default for engines that never receive the Kotlin preference.

package tunnel

import "testing"

func TestShouldBlockEncryptedDNSFollowsSwitch(t *testing.T) {
	e := NewEngine()

	// NewEngine fails closed, matching the historical hard block.
	if !e.shouldBlockEncryptedDNS(853) {
		t.Fatal("fresh engine must block DoT by default")
	}

	e.SetBlockEncryptedDns(false)
	if e.shouldBlockEncryptedDNS(853) {
		t.Fatal("disabling the switch must stop blocking port 853")
	}

	e.SetBlockEncryptedDns(true)
	if !e.shouldBlockEncryptedDNS(853) {
		t.Fatal("enabling the switch must block port 853")
	}
}

// Only port 853 is DoT; the predicate must not swallow other ports, otherwise a
// disabled switch would still break unrelated TLS traffic.
func TestShouldBlockEncryptedDNSOnlyMatchesDotPort(t *testing.T) {
	e := NewEngine()
	e.SetBlockEncryptedDns(true)

	for _, port := range []int{53, 80, 443, 465, 993, 8443, 0, -1} {
		if e.shouldBlockEncryptedDNS(port) {
			t.Fatalf("port %d must never be treated as encrypted DNS", port)
		}
	}
	if !e.shouldBlockEncryptedDNS(853) {
		t.Fatal("port 853 must be treated as encrypted DNS")
	}
}

// The predicate is called from per-flow goroutines while the settings screen can
// toggle the switch at any time; a nil engine must not panic.
func TestShouldBlockEncryptedDNSSurvivesNilEngine(t *testing.T) {
	var e *Engine
	if e.shouldBlockEncryptedDNS(853) {
		t.Fatal("nil engine must not report a block")
	}
}
