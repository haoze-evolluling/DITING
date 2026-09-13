package tunnel

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/miekg/dns"
)

type mockBootstrapCallback struct {
	mu      sync.Mutex
	results []bootstrapResult
}

type bootstrapResult struct {
	ipID         string
	ipName       string
	ip           string
	host         string
	success      bool
	elapsedMs    int64
	fallbackUsed bool
	errorMessage string
}

func (m *mockBootstrapCallback) OnBootstrapResult(
	ipID string,
	ipName string,
	ip string,
	host string,
	success bool,
	elapsedMs int64,
	fallbackUsed bool,
	errorMessage string,
) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.results = append(m.results, bootstrapResult{
		ipID:         ipID,
		ipName:       ipName,
		ip:           ip,
		host:         host,
		success:      success,
		elapsedMs:    elapsedMs,
		fallbackUsed: fallbackUsed,
		errorMessage: errorMessage,
	})
}

func TestBootstrapIPHealthScoring(t *testing.T) {
	health := newBootstrapIPHealth()
	now := time.Now()
	entry := bootstrapIPConfig{ID: "ip1", Name: "Test 1", IP: "1.1.1.1"}

	// Initial score
	initialScore := health.GetScore(entry, now)
	if initialScore.weight != 1.0 {
		t.Fatalf("expected initial weight 1.0, got %f", initialScore.weight)
	}

	// Record fast success (10ms)
	for i := 0; i < 5; i++ {
		health.RecordResult(true, 10, now)
	}
	fastScore := health.GetScore(entry, now)
	if fastScore.weight <= 1.0 {
		t.Fatalf("expected weight > 1.0 for fast responses, got %f", fastScore.weight)
	}

	// Record consecutive failures
	health.RecordResult(false, 3000, now)
	health.RecordResult(false, 3000, now)
	health.RecordResult(false, 3000, now)

	failedScore := health.GetScore(entry, now)
	if !failedScore.coolingDown {
		t.Fatalf("expected coolingDown to be true after 3 consecutive failures")
	}
	if failedScore.weight >= 0.5 {
		t.Fatalf("expected penalty weight < 0.5 during cooldown, got %f", failedScore.weight)
	}
}

func TestBootstrapPlanDistribution(t *testing.T) {
	resolver := newBootstrapResolver(nil)
	ips := []bootstrapIPConfig{
		{ID: "fast", Name: "Fast IP", IP: "1.1.1.1"},
		{ID: "slow", Name: "Slow IP", IP: "2.2.2.2"},
	}

	now := time.Now()
	fastHealth := resolver.getOrCreateHealth("fast")
	for i := 0; i < 10; i++ {
		fastHealth.RecordResult(true, 20, now)
	}

	slowHealth := resolver.getOrCreateHealth("slow")
	for i := 0; i < 10; i++ {
		slowHealth.RecordResult(true, 800, now)
	}

	fastCount := 0
	slowCount := 0
	iterations := 1000

	for i := 0; i < iterations; i++ {
		plan := resolver.choosePlan(ips, now)
		if plan.primary.ID == "fast" {
			fastCount++
		} else if plan.primary.ID == "slow" {
			slowCount++
		}
	}

	if fastCount <= slowCount*2 {
		t.Fatalf("expected fast IP count (%d) to be significantly greater than slow IP count (%d)", fastCount, slowCount)
	}
}

func TestBootstrapResolveHostMock(t *testing.T) {
	server1, addr1 := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		m.Rcode = dns.RcodeServerFailure
		_ = w.WriteMsg(m)
	})
	defer server1.Shutdown()

	server2, addr2 := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 93.184.216.34", r.Question[0].Name))
		m.Answer = append(m.Answer, rr)
		_ = w.WriteMsg(m)
	})
	defer server2.Shutdown()

	resolver := newBootstrapResolver(nil)
	cb := &mockBootstrapCallback{}
	resolver.SetCallback(cb)

	resolver.UpdateConfig(bootstrapConfig{
		Enabled: true,
		IPs: []bootstrapIPConfig{
			{ID: "srv1", Name: "Server 1", IP: addr1},
			{ID: "srv2", Name: "Server 2", IP: addr2},
		},
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	ip, err := resolver.ResolveHost(ctx, "example.com")
	if err != nil {
		t.Fatalf("expected successful resolution via fallback, got error: %v", err)
	}
	if ip != "93.184.216.34" {
		t.Fatalf("expected IP 93.184.216.34, got %s", ip)
	}

	resolver.ResetStats()
	resolver.healthMu.RLock()
	healthLen := len(resolver.healthMap)
	resolver.healthMu.RUnlock()
	if healthLen != 0 {
		t.Fatalf("expected health map to be empty after ResetStats, got len %d", healthLen)
	}
}
