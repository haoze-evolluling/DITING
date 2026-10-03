// engine_app_allowlist.go implements per-UID domain authorization caching for strict application allowlist mode.
//
// Key Behaviors:
// - Authorization Lifetime: Destinations are usable only while their DNS TTL remains valid for the resolving app UID.
// - System Resolver Handling: Evaluates queries against all restricted UIDs to handle Android netd system
//   resolver queries dispatched under netd UID or UIDUnknown on behalf of client apps.
// - Expiration Pruning: Cached IP mappings are pruned automatically when size exceeds thresholds.

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

type appAllowlist struct {
	mu      sync.RWMutex
	domains map[int]map[string]struct{}
	ips     map[int]map[string]time.Time
}

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
				rules[uid] = domMap
			}
		}
	}

	e.appAllowlist.mu.Lock()
	e.appAllowlist.domains = rules
	e.appAllowlist.ips = make(map[int]map[string]time.Time)
	e.appAllowlist.mu.Unlock()
}

func domainMatches(allowedDomains map[string]struct{}, domain string) bool {
	if len(allowedDomains) == 0 {
		return false
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

func (e *Engine) appAllowlistDomainAllowed(uid int, domain string) bool {
	e.appAllowlist.mu.RLock()
	defer e.appAllowlist.mu.RUnlock()
	allowedDomains, selected := e.appAllowlist.domains[uid]
	if !selected {
		return true
	}
	return domainMatches(allowedDomains, domain)
}

func (e *Engine) appAllowlistConnectionAllowed(uid int, ip net.IP) bool {
	if ip.IsLoopback() {
		return true
	}
	e.appAllowlist.mu.RLock()
	_, selected := e.appAllowlist.domains[uid]
	expiry := e.appAllowlist.ips[uid][ip.String()]
	e.appAllowlist.mu.RUnlock()
	return !selected || (!expiry.IsZero() && time.Now().Before(expiry))
}

func (e *Engine) rememberAppAllowlistResponse(uid int, response *dns.Msg) {
	if response == nil || len(response.Answer) == 0 {
		return
	}
	var qname string
	if len(response.Question) > 0 {
		qname = strings.TrimSuffix(strings.ToLower(response.Question[0].Name), ".")
	}

	e.appAllowlist.mu.Lock()
	defer e.appAllowlist.mu.Unlock()

	targetUIDs := make([]int, 0, 2)
	for targetUID, allowed := range e.appAllowlist.domains {
		if qname != "" && domainMatches(allowed, qname) {
			targetUIDs = append(targetUIDs, targetUID)
		} else if targetUID == uid && qname == "" {
			targetUIDs = append(targetUIDs, targetUID)
		}
	}

	if len(targetUIDs) == 0 {
		return
	}

	now := time.Now()
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
		if ttl > 0 && ip != nil && !ip.IsUnspecified() {
			expiry := now.Add(time.Duration(ttl) * time.Second)
			ipStr := ip.String()
			for _, targetUID := range targetUIDs {
				if e.appAllowlist.ips[targetUID] == nil {
					e.appAllowlist.ips[targetUID] = make(map[string]time.Time)
				}
				e.appAllowlist.ips[targetUID][ipStr] = expiry

				if len(e.appAllowlist.ips[targetUID]) > 256 {
					for k, exp := range e.appAllowlist.ips[targetUID] {
						if now.After(exp) {
							delete(e.appAllowlist.ips[targetUID], k)
						}
					}
				}
			}
		}
	}
}
