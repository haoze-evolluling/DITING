// engine_lifecycle_test.go pins the Engine teardown and start/stop
// interleaving contracts.
//
// NewEngine eagerly allocates a DNS cache whose cleaner goroutine ticks every
// 30 seconds, so an Engine dropped without Stop() leaks that goroutine for the
// rest of the process lifetime. StartFull, meanwhile, publishes its TUN stack
// only after releasing e.mu, so a Stop() landing inside that window must be
// able to tell "I am still the session" from "I was superseded".

package tunnel

import (
	"testing"
)

func TestEngineStopClosesDNSCache(t *testing.T) {
	e := NewEngine()
	cache := e.dnsCache
	if cache == nil {
		t.Fatal("NewEngine did not allocate a DNS cache")
	}
	if cache.closed.Load() {
		t.Fatal("fresh cache reports itself closed before Stop")
	}

	e.Stop()

	if !cache.closed.Load() {
		t.Fatal("Engine.Stop did not close the DNS cache cleaner (goroutine leak)")
	}
}

// Stop() runs on every service teardown path and is routinely called twice
// (service onDestroy plus the tunnel manager). A double close would panic on the
// closed stopCleaner channel, so the second call must be inert.
func TestEngineStopIsIdempotent(t *testing.T) {
	e := NewEngine()
	e.Stop()
	e.Stop()
	e.Stop()

	if !e.dnsCache.closed.Load() {
		t.Fatal("cache should still report closed after repeated Stop calls")
	}
}

// The MITM certificate cache is likewise released on Stop so a restarted Engine
// does not keep certificates for hosts the user has since removed.
func TestEngineStopReleasesCertCache(t *testing.T) {
	e := NewEngine()
	e.Stop()

	if e.stackCertMgr != nil {
		t.Fatal("Engine.Stop left the MITM certificate manager attached")
	}
}

func TestSessionGenInvalidatesInFlightStart(t *testing.T) {
	e := NewEngine()

	// Stand in for StartFull's capture-under-lock step.
	e.mu.Lock()
	gen := e.sessionGen
	e.mu.Unlock()

	// Stop() then a brand-new session: running ends up true again, which is
	// exactly what an e.running-only check would mistake for "still mine".
	e.Stop()
	e.mu.Lock()
	e.sessionGen++
	e.running = true
	stillCurrent := e.running && e.sessionGen == gen
	e.mu.Unlock()

	if stillCurrent {
		t.Fatal("stale StartFull was considered current after Stop + restart")
	}
}

// The common case must keep working: nothing intervenes, so the captured
// generation still identifies the live session when the publish happens.
func TestSessionGenAcceptsUninterruptedStart(t *testing.T) {
	e := NewEngine()

	e.mu.Lock()
	gen := e.sessionGen
	e.running = true
	e.mu.Unlock()

	e.mu.Lock()
	stillCurrent := e.running && e.sessionGen == gen
	e.mu.Unlock()

	if !stillCurrent {
		t.Fatal("uninterrupted StartFull was rejected as stale")
	}
}

// Stop() must bump the generation even when no tunnel was running, otherwise a
// StartFull that captured the generation and then lost the race to a Stop would
// still see a matching value and publish into a stopped engine.
func TestStopBumpsSessionGenWithoutRunningTunnel(t *testing.T) {
	e := NewEngine()
	before := e.sessionGen
	e.Stop()
	if e.sessionGen == before {
		t.Fatal("Stop did not advance sessionGen while idle")
	}
	// And it must still have released the cache (A-017 stays fixed).
	if !e.dnsCache.closed.Load() {
		t.Fatal("idle Stop no longer closes the DNS cache")
	}
}
