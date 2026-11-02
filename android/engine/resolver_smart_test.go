// resolver_smart_test.go covers the smart_prediction scheduler: adaptive hedge
// delay, staggered hedging, fast failover and censored loser accounting.

package tunnel

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func countingHandler(counter *atomic.Int32, inner dns.HandlerFunc) dns.HandlerFunc {
	return func(w dns.ResponseWriter, r *dns.Msg) {
		counter.Add(1)
		inner(w, r)
	}
}

func TestProviderStats_HedgeDelayAndCensored(t *testing.T) {
	s := newProviderStats()
	if d := s.HedgeDelay(); d != hedgeDelayCold {
		t.Fatalf("cold hedge delay = %v, want %v", d, hedgeDelayCold)
	}
	for i := 0; i < 20; i++ {
		s.RecordSuccess(200 * time.Millisecond)
	}
	if d := s.HedgeDelay(); d < 200*time.Millisecond || d > hedgeDelayMax {
		t.Fatalf("hedge delay for stable 200ms provider = %v", d)
	}
	for i := 0; i < 20; i++ {
		s.RecordSuccess(2 * time.Millisecond)
	}
	if d := s.HedgeDelay(); d != hedgeDelayMin {
		t.Fatalf("hedge delay should clamp to %v, got %v", hedgeDelayMin, d)
	}

	before := s.Score()
	s.RecordCensored(time.Millisecond) // faster than SRTT: no information
	if s.Score() != before {
		t.Fatalf("short censored sample must not change score")
	}
	s.RecordCensored(300 * time.Millisecond)
	if s.Score() <= before || s.failureCount != 0 {
		t.Fatalf("long censored sample should raise SRTT without failure, score=%v failures=%d", s.Score(), s.failureCount)
	}
}

func TestProviderStats_FailurePenaltyDecays(t *testing.T) {
	s := newProviderStats()
	s.RecordSuccess(20 * time.Millisecond)
	for i := 0; i < 10; i++ {
		s.RecordFailure()
	}
	now := time.Now()
	fresh := s.scoreAt(now)
	later := s.scoreAt(now.Add(5 * failurePenaltyHalfLife))
	if later >= fresh {
		t.Fatalf("penalty should decay over time: fresh=%v later=%v", fresh, later)
	}
}

func TestResolver_SmartPredictionStaggeredHedge(t *testing.T) {
	var hits1, hits2, hits3 atomic.Int32
	srv1, addr1 := startMockDNSServer(t, countingHandler(&hits1, makeAnswerHandler("10.0.0.1", 400*time.Millisecond)))
	defer srv1.Shutdown()
	srv2, addr2 := startMockDNSServer(t, countingHandler(&hits2, makeAnswerHandler("10.0.0.2", 5*time.Millisecond)))
	defer srv2.Shutdown()
	srv3, addr3 := startMockDNSServer(t, countingHandler(&hits3, makeAnswerHandler("10.0.0.3", 5*time.Millisecond)))
	defer srv3.Shutdown()

	logger := &mockRaceLogger{}
	resolver := NewResolver(nil)
	resolver.SetRaceLogCallback(logger)
	if err := resolver.ConfigureProviders("smart_prediction", []dnsProviderConfig{
		{ID: "p1", Protocol: "PLAIN", Server: addr1},
		{ID: "p2", Protocol: "PLAIN", Server: addr2},
		{ID: "p3", Protocol: "PLAIN", Server: addr3},
	}); err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}

	if _, err := resolver.Resolve(makeQueryMsg("hedge.example.com")); err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}
	res := logger.lastResult()
	if res == nil || res.winnerProviderID != "p2" || !res.fallbackUsed || !res.fallbackSuccess {
		t.Fatalf("expected hedged p2 to win, got %+v", res)
	}
	if hits3.Load() != 0 {
		t.Fatalf("p3 must not be queried when the first hedge answers, hits=%d", hits3.Load())
	}

	p1 := resolver.providerStatsMap["p1"]
	// The cancelled loser reports asynchronously after Resolve returns.
	var p1Samples int64
	var p1Failures int
	for deadline := time.Now().Add(time.Second); time.Now().Before(deadline); time.Sleep(5 * time.Millisecond) {
		p1.mu.RLock()
		p1Samples, p1Failures = p1.sampleCount, p1.failureCount
		p1.mu.RUnlock()
		if p1Samples > 0 || p1Failures > 0 {
			break
		}
	}
	if p1Failures != 0 || p1Samples == 0 {
		t.Fatalf("cancelled loser must be a censored sample, samples=%d failures=%d", p1Samples, p1Failures)
	}
	if p1.Score() <= resolver.providerStatsMap["p2"].Score() {
		t.Fatalf("slow loser should rank below the winner after censoring")
	}

	// The next query should prefer p2 directly.
	if _, err := resolver.Resolve(makeQueryMsg("hedge2.example.com")); err != nil {
		t.Fatalf("second Resolve failed: %v", err)
	}
	if res := logger.lastResult(); res.selectedProviderID != "p2" || res.fallbackUsed {
		t.Fatalf("expected p2 as primary without fallback, got %+v", res)
	}
}

func TestResolver_SmartPredictionFastFailover(t *testing.T) {
	srv1, addr1 := startMockDNSServer(t, makeAnswerHandler("", 0)) // SERVFAIL
	defer srv1.Shutdown()
	srv2, addr2 := startMockDNSServer(t, makeAnswerHandler("10.0.0.2", 0))
	defer srv2.Shutdown()

	logger := &mockRaceLogger{}
	resolver := NewResolver(nil)
	resolver.SetRaceLogCallback(logger)
	if err := resolver.ConfigureProviders("smart_prediction", []dnsProviderConfig{
		{ID: "p1", Protocol: "PLAIN", Server: addr1},
		{ID: "p2", Protocol: "PLAIN", Server: addr2},
	}); err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}

	start := time.Now()
	if _, err := resolver.Resolve(makeQueryMsg("failover.example.com")); err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}
	if elapsed := time.Since(start); elapsed >= hedgeDelayCold {
		t.Fatalf("failover should not wait for the hedge timer, took %v", elapsed)
	}
	res := logger.lastResult()
	if res == nil || res.winnerProviderID != "p2" || !res.fallbackUsed || !res.fallbackSuccess {
		t.Fatalf("expected failover to p2, got %+v", res)
	}
}

func makeDropFirstUDPHandler(drops int32, ip string) (dns.HandlerFunc, *atomic.Int32) {
	var count atomic.Int32
	return func(w dns.ResponseWriter, r *dns.Msg) {
		if count.Add(1) <= drops {
			return // simulate UDP packet drop
		}
		m := new(dns.Msg)
		m.SetReply(r)
		rr, _ := dns.NewRR(r.Question[0].Name + " 300 IN A " + ip)
		m.Answer = append(m.Answer, rr)
		_ = w.WriteMsg(m)
	}, &count
}

func makeRcodeHandler(rcode int) dns.HandlerFunc {
	return func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetRcode(r, rcode)
		_ = w.WriteMsg(m)
	}
}

func TestResolver_SingleAdaptiveUDPRetry(t *testing.T) {
	handler, attempts := makeDropFirstUDPHandler(1, "10.9.8.7")
	srv, addr := startMockDNSServer(t, handler)
	defer srv.Shutdown()

	resolver := NewResolver(nil)
	if err := resolver.ConfigureProviders("single", []dnsProviderConfig{
		{ID: "p1", Protocol: "PLAIN", Server: addr},
	}); err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}
	// Warm up SRTT to ~10ms so UDPRetryDelay clamps to udpRetryDelayMin (200ms).
	for i := 0; i < 5; i++ {
		resolver.providerStatsMap["p1"].RecordSuccess(10 * time.Millisecond)
	}

	start := time.Now()
	resp, err := resolver.Resolve(makeQueryMsg("retry.example.com"))
	if err != nil || len(resp) == 0 {
		t.Fatalf("expected retry to succeed, err=%v", err)
	}
	elapsed := time.Since(start)
	if attempts.Load() < 2 {
		t.Fatalf("expected at least 2 UDP attempts, got %d", attempts.Load())
	}
	if elapsed >= 900*time.Millisecond {
		t.Fatalf("adaptive UDP retry took too long (%v), expected near %v", elapsed, udpRetryDelayMin)
	}
}

func TestResolver_PrimaryBackupAdaptiveTimeoutAndCircuitBreaker(t *testing.T) {
	var primaryHits atomic.Int32
	// Primary returns REFUSED (policy rejection -> trips circuit breaker immediately).
	srv1, addr1 := startMockDNSServer(t, countingHandler(&primaryHits, makeRcodeHandler(dns.RcodeRefused)))
	defer srv1.Shutdown()
	srv2, addr2 := startMockDNSServer(t, makeAnswerHandler("10.0.0.2", 5*time.Millisecond))
	defer srv2.Shutdown()

	logger := &mockRaceLogger{}
	resolver := NewResolver(nil)
	resolver.SetRaceLogCallback(logger)
	if err := resolver.ConfigureProviders("primary_backup", []dnsProviderConfig{
		{ID: "p1", Protocol: "PLAIN", Server: addr1},
		{ID: "p2", Protocol: "PLAIN", Server: addr2},
	}); err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}

	// Query 1: hits p1 (REFUSED -> trips circuit), falls back to p2.
	if _, err := resolver.Resolve(makeQueryMsg("cb1.example.com")); err != nil {
		t.Fatalf("first Resolve failed: %v", err)
	}
	if primaryHits.Load() != 1 {
		t.Fatalf("expected 1 hit on primary, got %d", primaryHits.Load())
	}

	// Query 2: circuit is open, so p1 must be skipped immediately without hitting srv1.
	if _, err := resolver.Resolve(makeQueryMsg("cb2.example.com")); err != nil {
		t.Fatalf("second Resolve failed: %v", err)
	}
	if primaryHits.Load() != 1 {
		t.Fatalf("circuit-broken primary should have been skipped, hits=%d", primaryHits.Load())
	}
	res := logger.lastResult()
	if res == nil || !res.fallbackUsed || !res.fallbackSuccess || res.winnerProviderID != "p2" {
		t.Fatalf("unexpected race log on circuit skip: %+v", res)
	}
}

func TestResolver_PrimaryBackupPerAttemptBudget(t *testing.T) {
	// Primary blackholes packets; backup answers in 5ms.
	blackhole, _ := makeDropFirstUDPHandler(100, "10.0.0.1")
	srv1, addr1 := startMockDNSServer(t, blackhole)
	defer srv1.Shutdown()
	srv2, addr2 := startMockDNSServer(t, makeAnswerHandler("10.0.0.2", 5*time.Millisecond))
	defer srv2.Shutdown()

	resolver := NewResolver(nil)
	if err := resolver.ConfigureProviders("primary_backup", []dnsProviderConfig{
		{ID: "p1", Protocol: "PLAIN", Server: addr1},
		{ID: "p2", Protocol: "PLAIN", Server: addr2},
	}); err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}
	// Warm p1 stats to a fast SRTT so its per-attempt timeout is attemptTimeoutMin (300ms).
	for i := 0; i < 5; i++ {
		resolver.providerStatsMap["p1"].RecordSuccess(10 * time.Millisecond)
	}

	start := time.Now()
	if _, err := resolver.Resolve(makeQueryMsg("budget.example.com")); err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}
	if elapsed := time.Since(start); elapsed >= time.Second {
		t.Fatalf("primary_backup should fail over within adaptive budget, took %v", elapsed)
	}
}

func TestResolver_ParallelRaceConcurrencyCapAndEncryptedPreference(t *testing.T) {
	var hits1, hits2, hits3 atomic.Int32
	srv1, addr1 := startMockDNSServer(t, countingHandler(&hits1, makeAnswerHandler("10.0.0.1", 5*time.Millisecond)))
	defer srv1.Shutdown()
	srv2, addr2 := startMockDNSServer(t, countingHandler(&hits2, makeAnswerHandler("10.0.0.2", 15*time.Millisecond)))
	defer srv2.Shutdown()
	srv3, addr3 := startMockDNSServer(t, countingHandler(&hits3, makeAnswerHandler("10.0.0.3", 5*time.Millisecond)))
	defer srv3.Shutdown()

	logger := &mockRaceLogger{}
	resolver := NewResolver(nil)
	resolver.SetRaceLogCallback(logger)
	if err := resolver.ConfigureProvidersWithOptions("parallel_race", []dnsProviderConfig{
		{ID: "p1", Protocol: "PLAIN", Server: addr1},
		{ID: "p2", Protocol: "PLAIN", Server: addr2},
		{ID: "p3", Protocol: "PLAIN", Server: addr3},
	}, 2); err != nil {
		t.Fatalf("ConfigureProvidersWithOptions failed: %v", err)
	}
	// Make p3 the worst-ranked provider so top-2 cap picks p1 and p2.
	resolver.providerStatsMap["p1"].RecordSuccess(5 * time.Millisecond)
	resolver.providerStatsMap["p2"].RecordSuccess(10 * time.Millisecond)
	resolver.providerStatsMap["p3"].RecordSuccess(300 * time.Millisecond)

	if _, err := resolver.Resolve(makeQueryMsg("cap.example.com")); err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}
	if hits3.Load() != 0 {
		t.Fatalf("expected p3 to be excluded by raceMaxParallel=2, hits=%d", hits3.Load())
	}
	if res := logger.lastResult(); res == nil || res.providerCount != 3 {
		t.Fatalf("expected providerCount=3 (configured count), got %+v", res)
	}
}

func TestResolver_ParallelRacePrefersEncryptedWithinGraceWindow(t *testing.T) {
	// Plain UDP answers immediately (1ms); DoH answers in 8ms (within 25ms grace window).
	srvPlain, addrPlain := startMockDNSServer(t, makeAnswerHandler("10.0.0.1", time.Millisecond))
	defer srvPlain.Shutdown()

	dohServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		var buf [512]byte
		n, _ := r.Body.Read(buf[:])
		var req dns.Msg
		if err := req.Unpack(buf[:n]); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		time.Sleep(8 * time.Millisecond)
		m := new(dns.Msg)
		m.SetReply(&req)
		rr, _ := dns.NewRR(req.Question[0].Name + " 300 IN A 10.0.0.99")
		m.Answer = append(m.Answer, rr)
		packed, _ := m.Pack()
		w.Header().Set("Content-Type", "application/dns-message")
		_, _ = w.Write(packed)
	}))
	defer dohServer.Close()

	logger := &mockRaceLogger{}
	resolver := NewResolver(nil)
	resolver.SetRaceLogCallback(logger)
	if err := resolver.ConfigureProviders("parallel_race", []dnsProviderConfig{
		{ID: "plain", Protocol: "PLAIN", Server: addrPlain},
		{ID: "doh", Protocol: "DOH", URL: dohServer.URL},
	}); err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}

	resp, err := resolver.Resolve(makeQueryMsg("mixed.example.com"))
	if err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}
	var msg dns.Msg
	if err := msg.Unpack(resp); err != nil || len(msg.Answer) == 0 {
		t.Fatalf("unpack failed: %v", err)
	}
	if got := logger.lastResult(); got == nil || got.winnerProviderID != "doh" {
		t.Fatalf("expected encrypted DoH provider to win within grace window, got %+v", got)
	}
}

func TestResolver_ParallelRaceAggregatesErrors(t *testing.T) {
	srv1, addr1 := startMockDNSServer(t, makeRcodeHandler(dns.RcodeServerFailure))
	defer srv1.Shutdown()
	srv2, addr2 := startMockDNSServer(t, makeRcodeHandler(dns.RcodeRefused))
	defer srv2.Shutdown()

	resolver := NewResolver(nil)
	if err := resolver.ConfigureProviders("parallel_race", []dnsProviderConfig{
		{ID: "p1", Protocol: "PLAIN", Server: addr1},
		{ID: "p2", Protocol: "PLAIN", Server: addr2},
	}); err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}

	_, err := resolver.Resolve(makeQueryMsg("allfail.example.com"))
	if err == nil {
		t.Fatalf("expected error when all providers fail")
	}
	msg := err.Error()
	if !strings.Contains(msg, "p1:") || !strings.Contains(msg, "p2:") {
		t.Fatalf("expected aggregated error to mention both p1 and p2, got %q", msg)
	}
}
