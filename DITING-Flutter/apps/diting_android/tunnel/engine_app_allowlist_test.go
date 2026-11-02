// engine_app_allowlist_test.go pins the strict app-allowlist IP authorization
// across the DNS cache fast paths.
//
// appAllowlistConnectionAllowed only lets a selected UID connect to an IP that a
// previous DNS answer authorized for that UID (until the record TTL expires).
// The upstream branches grant it from the resolved *dns.Msg, but the cache-hit
// and stale-while-revalidate branches return wire bytes and used to return
// before granting anything. A whitelisted app then resolved fine from cache and
// had every connection refused - permanently, because the cache kept answering.

package tunnel

import (
	"net"
	"testing"
	"time"

	"github.com/miekg/dns"
)

// recordingDNSWriter is a minimal dns.ResponseWriter that keeps the last reply.
type recordingDNSWriter struct {
	msg *dns.Msg
}

func (w *recordingDNSWriter) LocalAddr() net.Addr {
	return &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 53}
}
func (w *recordingDNSWriter) RemoteAddr() net.Addr {
	return &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 5353}
}
func (w *recordingDNSWriter) WriteMsg(m *dns.Msg) error {
	w.msg = m.Copy()
	return nil
}
func (w *recordingDNSWriter) Write(b []byte) (int, error) {
	m := new(dns.Msg)
	if err := m.Unpack(b); err != nil {
		return 0, err
	}
	w.msg = m
	return len(b), nil
}
func (w *recordingDNSWriter) Close() error        { return nil }
func (w *recordingDNSWriter) TsigStatus() error   { return nil }
func (w *recordingDNSWriter) TsigTimersOnly(bool) {}
func (w *recordingDNSWriter) Hijack()             {}

const allowlistTestUID = 10188

// newAllowlistTestEngine builds an engine whose allowlist selects one UID for
// one domain, with a warm cache already holding an answer for that domain.
func newAllowlistTestEngine(t *testing.T, domain, ip string) (*Engine, *recordingDNSWriter) {
	t.Helper()

	e := &Engine{
		dnsCache:      newDNSCache(dnsCacheConfig{Enabled: true, Mode: "follow_dns_ttl", MaxTTLSeconds: 3600}),
		ipDomainCache: newIPDomainCache(16),
		policyEngine:  newPolicyEngine(),
	}
	// standaloneForward bails out to SERVFAIL when no resolver is configured,
	// before it ever consults the cache. The cache paths under test never reach
	// the network, so a bare resolver is enough.
	e.resolver = NewResolver(nil)
	e.filterDNS.Store(true)
	e.SetAppAllowlist(`{"10188": ["` + domain + `"]}`)

	query := new(dns.Msg)
	query.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	query.Id = 0x4242
	rawQuery, err := query.Pack()
	if err != nil {
		t.Fatalf("pack query: %v", err)
	}

	resp := new(dns.Msg)
	resp.SetReply(query)
	rr, err := dns.NewRR(dns.Fqdn(domain) + " 300 IN A " + ip)
	if err != nil {
		t.Fatalf("build answer: %v", err)
	}
	resp.Answer = append(resp.Answer, rr)
	rawResp, err := resp.Pack()
	if err != nil {
		t.Fatalf("pack response: %v", err)
	}
	if !e.dnsCache.put(rawQuery, rawResp) {
		t.Fatal("cache warm-up failed")
	}
	return e, &recordingDNSWriter{}
}

func allowlistQuery(t *testing.T, domain string) *dns.Msg {
	t.Helper()
	q := new(dns.Msg)
	q.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	q.Id = 0x1234
	return q
}

// The regression: a selected UID served from the cache must end up authorized
// to connect to the cached IP.
func TestServeDNSCacheHitGrantsAppAllowlistIP(t *testing.T) {
	const domain = "allowlisted.example"
	const ip = "203.0.113.7"

	e, w := newAllowlistTestEngine(t, domain, ip)
	parsed := net.ParseIP(ip)

	if e.appAllowlistConnectionAllowed(allowlistTestUID, parsed) {
		t.Fatal("fixture must start unauthorized")
	}

	e.serveDNS(w, allowlistQuery(t, domain), "", allowlistTestUID)
	if w.msg == nil {
		t.Fatal("cache hit produced no response")
	}
	if len(w.msg.Answer) == 0 {
		t.Fatalf("expected the cached answer, got %v", w.msg)
	}

	if !e.appAllowlistConnectionAllowed(allowlistTestUID, parsed) {
		t.Fatal("cache-hit response did not authorize the resolved IP for the selected UID")
	}
}

// The stale-while-revalidate branch returns wire bytes from a different code
// path and had the same gap.
func TestServeDNSStaleResponseGrantsAppAllowlistIP(t *testing.T) {
	const domain = "stale-allowlisted.example"
	const ip = "203.0.113.8"

	e, w := newAllowlistTestEngine(t, domain, ip)
	e.dnsCache.updatePolicy(dnsCacheConfig{
		Enabled:              true,
		Mode:                 "follow_dns_ttl",
		MaxTTLSeconds:        3600,
		StaleFallbackEnabled: true,
		StaleFallbackSeconds: 60,
	})

	entry := e.dnsCache.getEntry(cacheKey(domain, dns.TypeA, dns.ClassINET))
	if entry == nil {
		t.Fatal("cache entry missing")
	}
	entry.expiresAt = time.Now().Add(-1 * time.Second)
	entry.staleUntil = time.Now().Add(30 * time.Second)

	// The stale branch kicks off a background resolve; there is no resolver in
	// this fixture, so guard against a nil dereference in that goroutine.
	e.serveDNS(w, allowlistQuery(t, domain), "", allowlistTestUID)
	if w.msg == nil {
		t.Fatal("stale response was not written")
	}

	if !e.appAllowlistConnectionAllowed(allowlistTestUID, net.ParseIP(ip)) {
		t.Fatal("stale response did not authorize the resolved IP for the selected UID")
	}
}

// A negative answer must never authorize anything, and the domain-based UID
// fan-out must still reach the selected UID when the query is attributed to
// netd/UIDUnknown (Android dispatches system resolver queries that way).
func TestRememberAppAllowlistWireSkipsNegativeAnswersAndFansOutByDomain(t *testing.T) {
	const domain = "allowlisted.example"
	const ip = "203.0.113.7"

	e, _ := newAllowlistTestEngine(t, domain, ip)

	negative := new(dns.Msg)
	negative.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	negative.Response = true
	negative.Rcode = dns.RcodeNameError
	rawNegative, err := negative.Pack()
	if err != nil {
		t.Fatalf("pack negative: %v", err)
	}
	e.rememberAppAllowlistWire(allowlistTestUID, rawNegative)
	if e.appAllowlistConnectionAllowed(allowlistTestUID, net.ParseIP(ip)) {
		t.Fatal("a negative answer must not authorize any IP")
	}

	// Garbage input must be ignored rather than panicking.
	e.rememberAppAllowlistWire(allowlistTestUID, []byte{0, 1, 2})
	e.rememberAppAllowlistWire(allowlistTestUID, nil)

	// A positive answer arriving under the netd UID must still authorize the
	// selected UID, exactly like the upstream path does.
	positive := new(dns.Msg)
	positive.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	positive.Response = true
	rr, err := dns.NewRR(dns.Fqdn(domain) + " 300 IN A " + ip)
	if err != nil {
		t.Fatalf("build answer: %v", err)
	}
	positive.Answer = append(positive.Answer, rr)
	rawPositive, err := positive.Pack()
	if err != nil {
		t.Fatalf("pack positive: %v", err)
	}
	e.rememberAppAllowlistWire(UIDUnknown, rawPositive)
	if !e.appAllowlistConnectionAllowed(allowlistTestUID, net.ParseIP(ip)) {
		t.Fatal("netd-attributed query must still authorize the allowlisted UID")
	}

	// A UID with no allowlist entry must not be authorized.
	e.appAllowlist.mu.RLock()
	_, unselectedGranted := e.appAllowlist.ips[10200]
	e.appAllowlist.mu.RUnlock()
	if unselectedGranted {
		t.Fatal("a UID outside the allowlist must never be granted")
	}
}

// The grant must expire: authorization follows the DNS TTL, never outlives it.
func TestRememberAppAllowlistWireHonorsTTL(t *testing.T) {
	e := &Engine{ipDomainCache: newIPDomainCache(8)}
	e.SetAppAllowlist(`{"10188": ["short.example"]}`)

	resp := new(dns.Msg)
	resp.SetQuestion("short.example.", dns.TypeA)
	resp.Response = true
	rr, err := dns.NewRR("short.example. 1 IN A 203.0.113.10")
	if err != nil {
		t.Fatalf("build answer: %v", err)
	}
	resp.Answer = append(resp.Answer, rr)
	raw, err := resp.Pack()
	if err != nil {
		t.Fatalf("pack: %v", err)
	}

	e.rememberAppAllowlistWire(allowlistTestUID, raw)
	ip := net.ParseIP("203.0.113.10")
	if !e.appAllowlistConnectionAllowed(allowlistTestUID, ip) {
		t.Fatal("grant must be active before the TTL elapses")
	}

	e.appAllowlist.mu.Lock()
	e.appAllowlist.ips[allowlistTestUID][ip.String()] = time.Now().Add(-time.Second)
	e.appAllowlist.mu.Unlock()
	if e.appAllowlistConnectionAllowed(allowlistTestUID, ip) {
		t.Fatal("grant must lapse once the TTL expires")
	}
}
