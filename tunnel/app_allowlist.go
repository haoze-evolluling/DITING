package tunnel

import (
    "fmt"
    "net"
    "strings"
    "sync"
    "time"

    "github.com/miekg/dns"
)

// appAllowlist keeps the per-UID DNS authorization cache used by the strict
// application allowlist mode. A destination is usable only while its DNS TTL
// remains valid for the application that resolved it.
type appAllowlist struct {
    mu sync.RWMutex
    uids map[int]struct{}
    domains map[string]struct{}
    ips map[int]map[string]time.Time
}

func (e *Engine) SetAppAllowlist(uidsCSV, domainsCSV string) {
    uids := make(map[int]struct{})
    for _, raw := range strings.Split(uidsCSV, ",") {
        var uid int
        if _, err := fmt.Sscanf(strings.TrimSpace(raw), "%d", &uid); err == nil && uid > 0 { uids[uid] = struct{}{} }
    }
    domains := make(map[string]struct{})
    for _, raw := range strings.Split(domainsCSV, ",") {
        domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(raw)), ".")
        if domain != "" { domains[domain] = struct{}{} }
    }
    e.appAllowlist.mu.Lock()
    e.appAllowlist.uids, e.appAllowlist.domains, e.appAllowlist.ips = uids, domains, make(map[int]map[string]time.Time)
    e.appAllowlist.mu.Unlock()
}

func (e *Engine) appAllowlistDomainAllowed(uid int, domain string) bool {
    e.appAllowlist.mu.RLock(); defer e.appAllowlist.mu.RUnlock()
    if _, selected := e.appAllowlist.uids[uid]; !selected { return true }
    for candidate := strings.TrimSuffix(strings.ToLower(domain), "."); candidate != ""; {
        if _, ok := e.appAllowlist.domains[candidate]; ok { return true }
        dot := strings.IndexByte(candidate, '.')
        if dot < 0 { break }; candidate = candidate[dot+1:]
    }
    return false
}

func (e *Engine) appAllowlistConnectionAllowed(uid int, ip net.IP) bool {
    e.appAllowlist.mu.RLock()
    _, selected := e.appAllowlist.uids[uid]
    expiry := e.appAllowlist.ips[uid][ip.String()]
    e.appAllowlist.mu.RUnlock()
    return !selected || (!expiry.IsZero() && time.Now().Before(expiry))
}

func (e *Engine) rememberAppAllowlistResponse(uid int, response *dns.Msg) {
    e.appAllowlist.mu.Lock(); defer e.appAllowlist.mu.Unlock()
    if _, selected := e.appAllowlist.uids[uid]; !selected { return }
    if e.appAllowlist.ips[uid] == nil { e.appAllowlist.ips[uid] = make(map[string]time.Time) }
    for _, answer := range response.Answer {
        var ip net.IP; var ttl uint32
        switch rr := answer.(type) { case *dns.A: ip, ttl = rr.A, rr.Hdr.Ttl; case *dns.AAAA: ip, ttl = rr.AAAA, rr.Hdr.Ttl; default: continue }
        if ttl > 0 { e.appAllowlist.ips[uid][ip.String()] = time.Now().Add(time.Duration(ttl) * time.Second) }
    }
}
