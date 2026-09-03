package tunnel

import (
	"fmt"
	"net"
	"sync"
	"testing"
	"time"

	"github.com/miekg/dns"
)

type mockRaceLogger struct {
	mu      sync.Mutex
	results []raceLogResult
}

type raceLogResult struct {
	queryName          string
	queryType          int
	strategy           string
	providerCount      int
	success            bool
	elapsedMs          int64
	selectedProviderID string
	selectedElapsedMs  int64
	winnerProviderID   string
	winnerElapsedMs    int64
	fallbackUsed       bool
	fallbackSuccess    bool
	errorMessage       string
}

func (m *mockRaceLogger) OnRaceResult(
	queryName string,
	queryType int,
	strategy string,
	providerCount int,
	success bool,
	elapsedMs int64,
	selectedProviderID string,
	selectedElapsedMs int64,
	winnerProviderID string,
	winnerElapsedMs int64,
	fallbackUsed bool,
	fallbackSuccess bool,
	errorMessage string,
) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.results = append(m.results, raceLogResult{
		queryName:          queryName,
		queryType:          queryType,
		strategy:           strategy,
		providerCount:      providerCount,
		success:            success,
		elapsedMs:          elapsedMs,
		selectedProviderID: selectedProviderID,
		selectedElapsedMs:  selectedElapsedMs,
		winnerProviderID:   winnerProviderID,
		winnerElapsedMs:    winnerElapsedMs,
		fallbackUsed:       fallbackUsed,
		fallbackSuccess:    fallbackSuccess,
		errorMessage:       errorMessage,
	})
}

func (m *mockRaceLogger) lastResult() *raceLogResult {
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.results) == 0 {
		return nil
	}
	return &m.results[len(m.results)-1]
}

func startMockDNSServer(t *testing.T, handler dns.HandlerFunc) (*dns.Server, string) {
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen on udp packet: %v", err)
	}
	addr := pc.LocalAddr().String()
	server := &dns.Server{
		PacketConn: pc,
		Handler:    handler,
	}
	go func() {
		_ = server.ActivateAndServe()
	}()
	return server, addr
}

func makeQueryMsg(domain string) []byte {
	m := new(dns.Msg)
	m.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	m.RecursionDesired = true
	b, _ := m.Pack()
	return b
}

func makeAnswerHandler(ip string, delay time.Duration) dns.HandlerFunc {
	return func(w dns.ResponseWriter, r *dns.Msg) {
		if delay > 0 {
			time.Sleep(delay)
		}
		m := new(dns.Msg)
		m.SetReply(r)
		if ip != "" {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A %s", r.Question[0].Name, ip))
			m.Answer = append(m.Answer, rr)
		} else {
			m.Rcode = dns.RcodeServerFailure
		}
		_ = w.WriteMsg(m)
	}
}

func TestProviderStats_EWMA(t *testing.T) {
	stats := newProviderStats()
	if stats.Score() != defaultEWMA {
		t.Fatalf("expected default score %v, got %v", defaultEWMA, stats.Score())
	}

	stats.RecordSuccess(20 * time.Millisecond)
	if stats.failureCount != 0 {
		t.Errorf("expected failureCount 0, got %d", stats.failureCount)
	}

	stats.RecordFailure()
	stats.RecordFailure()
	if stats.failureCount != 2 {
		t.Errorf("expected failureCount 2, got %d", stats.failureCount)
	}
	score := stats.Score()
	if score <= 20*time.Millisecond {
		t.Errorf("expected penalty in score, got %v", score)
	}

	stats.RecordSuccess(15 * time.Millisecond)
	if stats.failureCount != 0 {
		t.Errorf("expected failureCount reset to 0 after success, got %d", stats.failureCount)
	}
}

func TestResolver_SingleMode(t *testing.T) {
	srv, addr := startMockDNSServer(t, makeAnswerHandler("1.2.3.4", 0))
	defer srv.Shutdown()

	logger := &mockRaceLogger{}
	resolver := NewResolver(nil)
	resolver.SetRaceLogCallback(logger)

	err := resolver.ConfigureProviders("single", []dnsProviderConfig{
		{ID: "primary-1", Protocol: "PLAIN", Server: addr},
	})
	if err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}

	rawQuery := makeQueryMsg("example.com")
	resp, err := resolver.Resolve(rawQuery)
	if err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("Unpack response failed: %v", err)
	}
	if len(respMsg.Answer) == 0 {
		t.Fatalf("Expected at least 1 answer, got 0")
	}

	res := logger.lastResult()
	if res == nil {
		t.Fatalf("Expected race log result, got nil")
	}
	if res.strategy != "single" || !res.success || res.winnerProviderID != "primary-1" {
		t.Errorf("Unexpected race log result: %+v", res)
	}
}

func TestResolver_PrimaryBackupMode(t *testing.T) {
	// Server 1 fails (SERVFAIL)
	srv1, addr1 := startMockDNSServer(t, makeAnswerHandler("", 0))
	defer srv1.Shutdown()

	// Server 2 succeeds
	srv2, addr2 := startMockDNSServer(t, makeAnswerHandler("9.9.9.9", 0))
	defer srv2.Shutdown()

	logger := &mockRaceLogger{}
	resolver := NewResolver(nil)
	resolver.SetRaceLogCallback(logger)

	err := resolver.ConfigureProviders("primary_backup", []dnsProviderConfig{
		{ID: "p1", Protocol: "PLAIN", Server: addr1},
		{ID: "p2", Protocol: "PLAIN", Server: addr2},
	})
	if err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}

	rawQuery := makeQueryMsg("backup.example.com")
	resp, err := resolver.Resolve(rawQuery)
	if err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("Unpack response failed: %v", err)
	}
	if len(respMsg.Answer) == 0 {
		t.Fatalf("Expected answer from backup provider, got none")
	}

	res := logger.lastResult()
	if res == nil {
		t.Fatalf("Expected race log result, got nil")
	}
	if !res.fallbackUsed || !res.fallbackSuccess || res.winnerProviderID != "p2" {
		t.Errorf("Unexpected race log result: %+v", res)
	}
}

func TestResolver_ParallelRaceMode(t *testing.T) {
	// Slow server (150ms)
	srvSlow, addrSlow := startMockDNSServer(t, makeAnswerHandler("1.1.1.1", 150*time.Millisecond))
	defer srvSlow.Shutdown()

	// Fast server (5ms)
	srvFast, addrFast := startMockDNSServer(t, makeAnswerHandler("2.2.2.2", 5*time.Millisecond))
	defer srvFast.Shutdown()

	logger := &mockRaceLogger{}
	resolver := NewResolver(nil)
	resolver.SetRaceLogCallback(logger)

	err := resolver.ConfigureProviders("parallel_race", []dnsProviderConfig{
		{ID: "slow", Protocol: "PLAIN", Server: addrSlow},
		{ID: "fast", Protocol: "PLAIN", Server: addrFast},
	})
	if err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}

	rawQuery := makeQueryMsg("race.example.com")
	resp, err := resolver.Resolve(rawQuery)
	if err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("Unpack response failed: %v", err)
	}

	res := logger.lastResult()
	if res == nil {
		t.Fatalf("Expected race log result, got nil")
	}
	if res.winnerProviderID != "fast" {
		t.Errorf("Expected 'fast' provider to win, got %q", res.winnerProviderID)
	}
}

func TestResolver_SmartPredictionMode(t *testing.T) {
	// Fast primary server (5ms)
	srv1, addr1 := startMockDNSServer(t, makeAnswerHandler("10.0.0.1", 5*time.Millisecond))
	defer srv1.Shutdown()

	// Slow backup server (100ms)
	srv2, addr2 := startMockDNSServer(t, makeAnswerHandler("10.0.0.2", 100*time.Millisecond))
	defer srv2.Shutdown()

	logger := &mockRaceLogger{}
	resolver := NewResolver(nil)
	resolver.SetRaceLogCallback(logger)

	err := resolver.ConfigureProviders("smart_prediction", []dnsProviderConfig{
		{ID: "p1", Protocol: "PLAIN", Server: addr1},
		{ID: "p2", Protocol: "PLAIN", Server: addr2},
	})
	if err != nil {
		t.Fatalf("ConfigureProviders failed: %v", err)
	}

	rawQuery := makeQueryMsg("smart.example.com")
	resp, err := resolver.Resolve(rawQuery)
	if err != nil {
		t.Fatalf("Resolve failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("Unpack response failed: %v", err)
	}

	res := logger.lastResult()
	if res == nil {
		t.Fatalf("Expected race log result, got nil")
	}
	// Fast server should have responded before the 50ms fallback trigger
	if res.winnerProviderID != "p1" || res.fallbackUsed {
		t.Errorf("Expected p1 to win without fallback, got %+v", res)
	}
}
