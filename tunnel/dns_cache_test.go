package tunnel

import (
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

	entry := cache.entries[cacheKey("clamp.com", dns.TypeA, dns.ClassINET)]
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

	// Artificially expire the entry
	entry := cache.entries[cacheKey("stale.com", dns.TypeA, dns.ClassINET)]
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
