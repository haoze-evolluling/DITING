// dns_cache_test.go provides unit tests for the in-memory DNS cache,
// covering cache hit/miss behavior, TTL expiration, zero-copy ID patching, stale fallback, and single-flight deduplication.

package tunnel

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/miekg/dns"
)


func TestDNSCachePutAndGet(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{
		Enabled:       true,
		Mode:          "follow_dns_ttl",
		MaxTTLSeconds: 3600,
	})

	query := new(dns.Msg)
	query.SetQuestion("example.com.", dns.TypeA)
	query.Id = 1234
	rawQuery, _ := query.Pack()

	resp := new(dns.Msg)
	resp.SetReply(query)
	rr, _ := dns.NewRR("example.com. 300 IN A 93.184.216.34")
	resp.Answer = append(resp.Answer, rr)
	rawResp, _ := resp.Pack()

	if !cache.put(rawQuery, rawResp) {
		t.Fatalf("expected Put to succeed")
	}

	query2 := new(dns.Msg)
	query2.SetQuestion("example.com.", dns.TypeA)
	query2.Id = 5678
	rawQuery2, _ := query2.Pack()

	cachedBytes, hit, _ := cache.get(rawQuery2)
	if !hit {
		t.Fatalf("expected cache hit")
	}

	var cachedMsg dns.Msg
	if err := cachedMsg.Unpack(cachedBytes); err != nil {
		t.Fatalf("failed to unpack cached response: %v", err)
	}

	if cachedMsg.Id != 5678 {
		t.Errorf("expected cached Msg.Id to be 5678, got %d", cachedMsg.Id)
	}

	if len(cachedMsg.Answer) != 1 {
		t.Fatalf("expected 1 answer record, got %d", len(cachedMsg.Answer))
	}

	aRecord, ok := cachedMsg.Answer[0].(*dns.A)
	if !ok {
		t.Fatalf("expected A record, got %T", cachedMsg.Answer[0])
	}

	if aRecord.A.String() != "93.184.216.34" {
		t.Errorf("expected IP 93.184.216.34, got %s", aRecord.A.String())
	}
}

func TestDNSCacheTTLClamping(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{
		Enabled:       true,
		Mode:          "limit_max_ttl",
		MaxTTLSeconds: 60,
		MinTTLEnabled: true,
		MinTTLSeconds: 10,
	})

	query := new(dns.Msg)
	query.SetQuestion("clamp.com.", dns.TypeA)
	rawQuery, _ := query.Pack()

	resp := new(dns.Msg)
	resp.SetReply(query)
	rr, _ := dns.NewRR("clamp.com. 3600 IN A 1.2.3.4")
	resp.Answer = append(resp.Answer, rr)
	rawResp, _ := resp.Pack()

	cache.put(rawQuery, rawResp)

	entry := cache.getEntry(cacheKey("clamp.com", dns.TypeA, dns.ClassINET))
	if entry == nil {
		t.Fatalf("expected entry to exist")
	}

	if entry.effectiveTTL != 60*time.Second {
		t.Errorf("expected effective TTL 60s, got %v", entry.effectiveTTL)
	}
}

func TestDNSCacheStaleFallback(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{
		Enabled:              true,
		Mode:                 "fixed_ttl",
		FixedTTLSeconds:      1,
		StaleFallbackEnabled: true,
		StaleFallbackSeconds: 10,
	})

	query := new(dns.Msg)
	query.SetQuestion("stale.com.", dns.TypeA)
	query.Id = 111
	rawQuery, _ := query.Pack()

	resp := new(dns.Msg)
	resp.SetReply(query)
	rr, _ := dns.NewRR("stale.com. 1 IN A 1.1.1.1")
	resp.Answer = append(resp.Answer, rr)
	rawResp, _ := resp.Pack()

	cache.put(rawQuery, rawResp)

	entry := cache.getEntry(cacheKey("stale.com", dns.TypeA, dns.ClassINET))
	entry.expiresAt = time.Now().Add(-1 * time.Second)
	entry.staleUntil = time.Now().Add(10 * time.Second)

	_, hit, staleCandidate := cache.get(rawQuery)
	if hit {
		t.Errorf("expected expired entry not to be a direct hit")
	}
	if staleCandidate == nil {
		t.Fatalf("expected stale candidate to be returned")
	}

	staleRespBytes := cache.buildStaleResponse(rawQuery, staleCandidate)
	if staleRespBytes == nil {
		t.Fatalf("expected valid stale response")
	}

	var staleMsg dns.Msg
	_ = staleMsg.Unpack(staleRespBytes)
	if staleMsg.Answer[0].Header().Ttl != 1 {
		t.Errorf("expected stale TTL=1, got %d", staleMsg.Answer[0].Header().Ttl)
	}
}

func TestNegativeCaching(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{
		Enabled:            true,
		NegativeTTLEnabled: true,
		NegativeTTLSeconds: 20,
	})
	defer cache.close()

	// 1. Test NXDOMAIN caching
	nxQuery := new(dns.Msg)
	nxQuery.SetQuestion("nonexistent.example.com.", dns.TypeA)
	nxQuery.Id = 1001
	rawNxQuery, _ := nxQuery.Pack()

	nxResp := new(dns.Msg)
	nxResp.SetReply(nxQuery)
	nxResp.Rcode = dns.RcodeNameError
	// SOA record in Authority section with TTL=10
	soa, _ := dns.NewRR("example.com. 10 IN SOA ns1.example.com. hostmaster.example.com. 1 7200 3600 1209600 10")
	nxResp.Ns = append(nxResp.Ns, soa)
	rawNxResp, _ := nxResp.Pack()

	if !cache.put(rawNxQuery, rawNxResp) {
		t.Fatalf("expected NXDOMAIN to be cached")
	}

	nxQuery2 := new(dns.Msg)
	nxQuery2.SetQuestion("nonexistent.example.com.", dns.TypeA)
	nxQuery2.Id = 1002
	rawNxQuery2, _ := nxQuery2.Pack()

	cachedBytes, hit, _, _, _, isNegative, _ := cache.getFast(rawNxQuery2)
	if !hit {
		t.Fatalf("expected cache hit for NXDOMAIN")
	}
	if !isNegative {
		t.Errorf("expected isNegative=true")
	}

	var parsedNx dns.Msg
	if err := parsedNx.Unpack(cachedBytes); err != nil {
		t.Fatalf("failed to unpack cached NXDOMAIN: %v", err)
	}
	if parsedNx.Id != 1002 {
		t.Errorf("expected Query ID 1002, got %d", parsedNx.Id)
	}
	if parsedNx.Rcode != dns.RcodeNameError {
		t.Errorf("expected RCODE NXDOMAIN, got %d", parsedNx.Rcode)
	}

	// 2. Test NODATA (NOERROR with 0 answers)
	noDataQuery := new(dns.Msg)
	noDataQuery.SetQuestion("ipv4only.example.com.", dns.TypeAAAA)
	noDataQuery.Id = 2001
	rawNoDataQuery, _ := noDataQuery.Pack()

	noDataResp := new(dns.Msg)
	noDataResp.SetReply(noDataQuery)
	noDataResp.Rcode = dns.RcodeSuccess
	rawNoDataResp, _ := noDataResp.Pack()

	if !cache.put(rawNoDataQuery, rawNoDataResp) {
		t.Fatalf("expected NODATA to be cached")
	}

	cachedNoDataBytes, hit, _, _, _, isNegative, _ := cache.getFast(rawNoDataQuery)
	if !hit {
		t.Fatalf("expected cache hit for NODATA")
	}
	if !isNegative {
		t.Errorf("expected isNegative=true for NODATA")
	}
	var parsedNoData dns.Msg
	_ = parsedNoData.Unpack(cachedNoDataBytes)
	if parsedNoData.Rcode != dns.RcodeSuccess || len(parsedNoData.Answer) != 0 {
		t.Errorf("expected empty answer with NOERROR for NODATA")
	}
}

func TestWireFormatZeroCopy(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{
		Enabled:       true,
		Mode:          "follow_dns_ttl",
		MaxTTLSeconds: 3600,
	})
	defer cache.close()

	query := new(dns.Msg)
	query.SetQuestion("zerocopy.com.", dns.TypeA)
	query.Id = 999
	rawQuery, _ := query.Pack()

	resp := new(dns.Msg)
	resp.SetReply(query)
	rr1, _ := dns.NewRR("zerocopy.com. 300 IN A 1.2.3.4")
	rr2, _ := dns.NewRR("zerocopy.com. 300 IN A 5.6.7.8")
	resp.Answer = append(resp.Answer, rr1, rr2)
	rawResp, _ := resp.Pack()

	if !cache.put(rawQuery, rawResp) {
		t.Fatalf("failed to put response in cache")
	}

	// Query with new ID 8888
	query2 := new(dns.Msg)
	query2.SetQuestion("zerocopy.com.", dns.TypeA)
	query2.Id = 8888
	rawQuery2, _ := query2.Pack()

	cachedBytes, hit, targets, ipList, resolvedIPs, _, _ := cache.getFast(rawQuery2)
	if !hit {
		t.Fatalf("expected hit")
	}
	if len(targets) != 0 {
		t.Errorf("expected 0 CNAME targets, got %d", len(targets))
	}
	if len(ipList) != 2 {
		t.Errorf("expected 2 pre-extracted IPs, got %d", len(ipList))
	}
	if resolvedIPs != "1.2.3.4,5.6.7.8" {
		t.Errorf("expected '1.2.3.4,5.6.7.8', got %q", resolvedIPs)
	}

	var parsed dns.Msg
	if err := parsed.Unpack(cachedBytes); err != nil {
		t.Fatalf("failed to unpack patched wire: %v", err)
	}
	if parsed.Id != 8888 {
		t.Errorf("expected ID 8888, got %d", parsed.Id)
	}
	if len(parsed.Answer) != 2 {
		t.Fatalf("expected 2 answers, got %d", len(parsed.Answer))
	}
	if parsed.Answer[0].Header().Ttl == 0 || parsed.Answer[0].Header().Ttl > 300 {
		t.Errorf("unexpected TTL: %d", parsed.Answer[0].Header().Ttl)
	}
}

func TestSingleFlightPanicSafety(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{Enabled: true})
	defer cache.close()

	query := new(dns.Msg)
	query.SetQuestion("panic.example.com.", dns.TypeA)
	query.Id = 123
	rawQuery, _ := query.Pack()

	// 1. Panicking resolveFn
	_, _, err := cache.singleFlight(rawQuery, func() ([]byte, error) {
		panic("simulated upstream parser crash")
	})
	if err == nil {
		t.Fatalf("expected error from recovered panic")
	}

	// 2. Subsequent call must NOT deadlock
	done := make(chan bool)
	go func() {
		resp, _, callErr := cache.singleFlight(rawQuery, func() ([]byte, error) {
			m := new(dns.Msg)
			m.SetReply(query)
			rr, _ := dns.NewRR("panic.example.com. 60 IN A 1.1.1.1")
			m.Answer = append(m.Answer, rr)
			return m.Pack()
		})
		if callErr != nil || len(resp) == 0 {
			t.Errorf("subsequent singleflight call failed: %v", callErr)
		}
		done <- true
	}()

	select {
	case <-done:
		// Succeeded, no deadlock!
	case <-time.After(2 * time.Second):
		t.Fatalf("singleFlight deadlocked after panic!")
	}
}

func TestShardedConcurrentAccess(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{
		Enabled:       true,
		Mode:          "follow_dns_ttl",
		MaxTTLSeconds: 300,
	})
	defer cache.close()

	const numWorkers = 30
	const numQueries = 100

	var wg sync.WaitGroup
	wg.Add(numWorkers)

	for w := 0; w < numWorkers; w++ {
		go func(workerID int) {
			defer wg.Done()
			for q := 0; q < numQueries; q++ {
				domain := fmt.Sprintf("worker-%d-domain-%d.com.", workerID%5, q%20)
				query := new(dns.Msg)
				query.SetQuestion(domain, dns.TypeA)
				query.Id = uint16(q)
				rawQuery, _ := query.Pack()

				// Random read or write
				if q%2 == 0 {
					_, _, _, _, _, _, _ = cache.getFast(rawQuery)
				} else {
					resp := new(dns.Msg)
					resp.SetReply(query)
					rr, _ := dns.NewRR(fmt.Sprintf("%s 60 IN A 10.0.0.%d", domain, q%250))
					resp.Answer = append(resp.Answer, rr)
					rawResp, _ := resp.Pack()
					cache.put(rawQuery, rawResp)
				}
			}
		}(w)
	}

	wg.Wait()

	stats := cache.stats()
	if stats.TotalHits+stats.TotalMisses == 0 {
		t.Errorf("expected stats to record lookups")
	}
}

func BenchmarkDNSCacheGetFast_Hit(b *testing.B) {
	cache := newDNSCache(dnsCacheConfig{
		Enabled:       true,
		Mode:          "follow_dns_ttl",
		MaxTTLSeconds: 3600,
	})
	defer cache.close()

	query := new(dns.Msg)
	query.SetQuestion("bench.example.com.", dns.TypeA)
	query.Id = 1
	rawQuery, _ := query.Pack()

	resp := new(dns.Msg)
	resp.SetReply(query)
	rr, _ := dns.NewRR("bench.example.com. 300 IN A 93.184.216.34")
	resp.Answer = append(resp.Answer, rr)
	rawResp, _ := resp.Pack()
	cache.put(rawQuery, rawResp)

	b.ResetTimer()
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		_, hit, _, _, _, _, _ := cache.getFast(rawQuery)
		if !hit {
			b.Fatalf("expected hit")
		}
	}
}

