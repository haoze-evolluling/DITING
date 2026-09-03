package tunnel

import (
	"encoding/json"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
)

// appAllowlist keeps the per-UID DNS authorization cache used by the strict
// application allowlist mode. A destination is usable only while its DNS TTL
// remains valid for the application that resolved it.
type appAllowlist struct {
	mu      sync.RWMutex
	domains map[int]map[string]struct{}
	ips     map[int]map[string]time.Time
}

// SetAppAllowlist updates per-UID domain allowlists using JSON formatted as:
// {"10001": ["example.com", "sub.example.com"], "10002": ["github.com"]}
func (e *Engine) SetAppAllowlist(rulesJSON string) {
	rules := make(map[int]map[string]struct{})
	if strings.TrimSpace(rulesJSON) != "" {
		var rawMap map[string][]string
		if err := json.Unmarshal([]byte(rulesJSON), &rawMap); err == nil {
			for uidStr, domainList := range rawMap {
				uid, err := strconv.Atoi(strings.TrimSpace(uidStr))
				if err != nil || uid <= 0 {
					continue
				}
				domMap := make(map[string]struct{})
				for _, raw := range domainList {
					domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(raw)), ".")
					if domain != "" {
						domMap[domain] = struct{}{}
					}
				}
				if len(domMap) > 0 {
					rules[uid] = domMap
				}
			}
		}
	}

	e.appAllowlist.mu.Lock()
	e.appAllowlist.domains = rules
	e.appAllowlist.ips = make(map[int]map[string]time.Time)
	e.appAllowlist.mu.Unlock()
}

func (e *Engine) appAllowlistDomainAllowed(uid int, domain string) bool {
	e.appAllowlist.mu.RLock()
	defer e.appAllowlist.mu.RUnlock()
	allowedDomains, selected := e.appAllowlist.domains[uid]
	if !selected {
		return true
	}
	for candidate := strings.TrimSuffix(strings.ToLower(domain), "."); candidate != ""; {
		if _, ok := allowedDomains[candidate]; ok {
			return true
		}
		dot := strings.IndexByte(candidate, '.')
		if dot < 0 {
			break
		}
		candidate = candidate[dot+1:]
	}
	return false
}

func (e *Engine) appAllowlistConnectionAllowed(uid int, ip net.IP) bool {
	e.appAllowlist.mu.RLock()
	_, selected := e.appAllowlist.domains[uid]
	expiry := e.appAllowlist.ips[uid][ip.String()]
	e.appAllowlist.mu.RUnlock()
	return !selected || (!expiry.IsZero() && time.Now().Before(expiry))
}

func (e *Engine) rememberAppAllowlistResponse(uid int, response *dns.Msg) {
	e.appAllowlist.mu.Lock()
	defer e.appAllowlist.mu.Unlock()
	if _, selected := e.appAllowlist.domains[uid]; !selected {
		return
	}
	if e.appAllowlist.ips[uid] == nil {
		e.appAllowlist.ips[uid] = make(map[string]time.Time)
	}
	for _, answer := range response.Answer {
		var ip net.IP
		var ttl uint32
		switch rr := answer.(type) {
		case *dns.A:
			ip, ttl = rr.A, rr.Hdr.Ttl
		case *dns.AAAA:
			ip, ttl = rr.AAAA, rr.Hdr.Ttl
		default:
			continue
		}
		if ttl > 0 {
			e.appAllowlist.ips[uid][ip.String()] = time.Now().Add(time.Duration(ttl) * time.Second)
		}
	}
}
