// engine_config.go manages dynamic configuration and runtime control knobs for the
// Engine instance, exposing gomobile-compatible setters called from Android Kotlin.
//
// Key Configuration Responsibilities:
// - Upstream DNS endpoints (Plain, DoH, DoT, DoQ), fallbacks, and block response types
//   (CUSTOM_IP 0.0.0.0, NXDOMAIN, REFUSED).
// - PolicyEngine rule snapshots and CNAME rewrite mappings.
// - Android UI event callback bridges (LogCallback, BatchLogCallback, RaceLogCallback,
//   BootstrapLogCallback, HttpLogCallback, TrafficCallback).
// - Screen state adaptive tick intervals (e.g., 1000ms interactive vs 10000ms screen-off)
//   which conserve battery while maintaining continuous atomic byte/packet accounting.
// - Outbound proxy session configuration and domain checker bindings.

package tunnel

import (
	"encoding/json"
	"net"
	"strings"
	"time"

	"github.com/miekg/dns"
)

func (e *Engine) ClearDNSCache() {
	if e.dnsCache != nil {
		e.dnsCache.clear()
	}
}

func (e *Engine) GetDNSCacheStats() string {
	if e == nil || e.dnsCache == nil {
		return "{}"
	}
	return e.dnsCache.statsJSON()
}


func (e *Engine) GetRouter() *Router {
	return e.router
}

func (e *Engine) SetOutboundAdapter(adapter OutboundAdapter) {
	e.router.SetAdapter(adapter)
}

func (e *Engine) SetDomainChecker(checker DomainChecker) {
	e.domainChecker = checker
}

func (e *Engine) ApplyRuleSnapshot(jsonSnapshot string) string {
	e.mu.Lock()
	if e.policyEngine == nil {
		e.policyEngine = newPolicyEngine()
	}
	pe := e.policyEngine
	e.mu.Unlock()

	if err := pe.applySnapshot(jsonSnapshot); err != nil {
		logf("ApplyRuleSnapshot error: %v", err)
		return err.Error()
	}
	logf("ApplyRuleSnapshot successfully updated Go policy engine rules")
	return ""
}

func (e *Engine) SetFilterDNS(enabled bool) { e.filterDNS.Store(enabled) }

// rewriteEntry holds the per-domain rewrite targets: direct IPv4/IPv6 answers
// served at the DNS stage, plus an optional CNAME target consumed by the MITM
// redirect flow.
type rewriteEntry struct {
	cname string
	ip4   net.IP
	ip6   net.IP
}

// SetRewriteRules accepts a JSON object mapping domains to either a single
// target (CNAME domain or IP literal) or an array of targets (IPv4 + IPv6).
func (e *Engine) SetRewriteRules(content string) {
	entries := make(map[string]*rewriteEntry)
	if content != "" {
		raw := make(map[string]json.RawMessage)
		if err := json.Unmarshal([]byte(content), &raw); err != nil {
			logf("SetRewriteRules: invalid JSON: %v", err)
			return
		}
		for domain, value := range raw {
			domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
			if domain == "" {
				continue
			}
			if entry := parseRewriteEntry(value); entry != nil {
				entries[domain] = entry
			}
		}
	}
	e.mu.Lock()
	e.rewriteRules = entries
	e.mu.Unlock()
}

func parseRewriteEntry(value json.RawMessage) *rewriteEntry {
	var targets []string
	var single string
	if err := json.Unmarshal(value, &single); err == nil {
		targets = []string{single}
	} else if err := json.Unmarshal(value, &targets); err != nil {
		return nil
	}
	entry := &rewriteEntry{}
	for _, target := range targets {
		target = strings.TrimSpace(target)
		if target == "" {
			continue
		}
		if ip := net.ParseIP(target); ip != nil {
			if ip.To4() != nil {
				if entry.ip4 == nil {
					entry.ip4 = ip
				}
			} else if entry.ip6 == nil {
				entry.ip6 = ip
			}
			continue
		}
		if entry.cname == "" {
			entry.cname = strings.TrimSuffix(strings.ToLower(target), ".")
		}
	}
	if entry.cname == "" && entry.ip4 == nil && entry.ip6 == nil {
		return nil
	}
	return entry
}

func (e *Engine) rewriteLookup(domain string) *rewriteEntry {
	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if domain == "" {
		return nil
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	for candidate := domain; candidate != ""; {
		if entry := e.rewriteRules[candidate]; entry != nil {
			return entry
		}
		dot := strings.IndexByte(candidate, '.')
		if dot < 0 {
			break
		}
		candidate = candidate[dot+1:]
	}
	return nil
}

// rewriteIP returns the DNS-stage rewrite answer for the requested family.
func (e *Engine) rewriteIP(domain string, ipv4 bool) net.IP {
	entry := e.rewriteLookup(domain)
	if entry == nil {
		return nil
	}
	if ipv4 {
		return entry.ip4
	}
	return entry.ip6
}

// rewriteCNAME returns the CNAME rewrite target used by the MITM redirect flow.
func (e *Engine) rewriteCNAME(domain string) string {
	entry := e.rewriteLookup(domain)
	if entry == nil {
		return ""
	}
	return entry.cname
}

type resolveDomainResult struct {
	IPs    []string `json:"ips,omitempty"`
	TTLs   []int    `json:"ttls,omitempty"`
	Source string   `json:"source"`
	Reason string   `json:"reason,omitempty"`
	Error  string   `json:"error,omitempty"`
}

// rewriteAnswerTTL is the TTL advertised on synthesized rewrite answers.
const rewriteAnswerTTL = 300

// ResolveDomain resolves a domain through the tunnel's DNS decision path for
// the diagnostics tools: IPv4/IPv6 rewrites first, then policy blocking, then
// the configured upstream resolver. Returns JSON with "ips" plus a "source"
// of "rewrite", "blocked", or "upstream", or an "error" object.
func (e *Engine) ResolveDomain(domain string, ipv4 bool) string {
	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if domain == "" {
		return resolveDomainError("empty domain")
	}
	qtype := dns.TypeAAAA
	if ipv4 {
		qtype = dns.TypeA
	}

	if ip := e.rewriteIP(domain, ipv4); ip != nil {
		return resolveDomainJSON([]string{ip.String()}, []int{rewriteAnswerTTL}, "rewrite", "")
	}

	if e.filterDNS.Load() && e.policyEngine != nil && e.policyEngine.isActive() && e.policyEngine.hasRules() {
		if blocked, reason := e.policyEngine.evaluate(domain, "", qtype); blocked {
			return resolveDomainJSON(nil, nil, "blocked", reason)
		}
	}

	e.mu.Lock()
	resolver := e.resolver
	e.mu.Unlock()
	if resolver == nil {
		return resolveDomainError("tunnel resolver not active")
	}

	query := new(dns.Msg)
	query.SetQuestion(dns.Fqdn(domain), qtype)
	query.RecursionDesired = true
	rawQuery, err := query.Pack()
	if err != nil {
		return resolveDomainError(err.Error())
	}
	resp, err := resolver.Resolve(rawQuery)
	if err != nil {
		return resolveDomainError(err.Error())
	}
	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		return resolveDomainError(err.Error())
	}
	if isUpstreamBlockedMsg(&respMsg) {
		return resolveDomainJSON(nil, nil, "blocked", "upstream_dns")
	}

	ips := make([]string, 0, len(respMsg.Answer))
	ttls := make([]int, 0, len(respMsg.Answer))
	for _, rr := range respMsg.Answer {
		if a, ok := rr.(*dns.A); ok && ipv4 && a.A != nil {
			ips = append(ips, a.A.String())
			ttls = append(ttls, int(a.Hdr.Ttl))
		} else if aaaa, ok := rr.(*dns.AAAA); ok && !ipv4 && aaaa.AAAA != nil {
			ips = append(ips, aaaa.AAAA.String())
			ttls = append(ttls, int(aaaa.Hdr.Ttl))
		}
	}
	if len(ips) == 0 {
		reason := dns.RcodeToString[respMsg.Rcode]
		if reason == "" {
			reason = "no answer records"
		}
		return resolveDomainJSON(nil, nil, "nodata", reason)
	}
	return resolveDomainJSON(ips, ttls, "upstream", "")
}

func resolveDomainJSON(ips []string, ttls []int, source, reason string) string {
	data, err := json.Marshal(resolveDomainResult{IPs: ips, TTLs: ttls, Source: source, Reason: reason})
	if err != nil {
		return resolveDomainError(err.Error())
	}
	return string(data)
}

func resolveDomainError(message string) string {
	data, _ := json.Marshal(resolveDomainResult{Error: message})
	return string(data)
}

func (e *Engine) SetFirewallChecker(checker FirewallChecker) {
	e.firewallChecker = checker
}

func (e *Engine) SetAppResolver(resolver AppResolver) {
	e.appResolver = resolver
}

func (e *Engine) SetAppUidResolver(resolver AppUidResolver) {
	e.appUidResolver = resolver
}

func (e *Engine) SetLogCallback(cb LogCallback) {
	e.logCallback = cb
}

func (e *Engine) SetBatchLogCallback(cb BatchLogCallback) {
	e.batchLogCallback = cb
	if e.logAggregator != nil {
		e.logAggregator.setCallback(cb)
		if cb != nil {
			e.logAggregator.start()
		}
	}
}

func (e *Engine) SetRaceLogCallback(cb RaceLogCallback) {
	e.mu.Lock()
	e.raceLogCallback = cb
	resolver := e.resolver
	e.mu.Unlock()
	if resolver != nil {
		resolver.SetRaceLogCallback(cb)
	}
}

func (e *Engine) SetBootstrapLogCallback(cb BootstrapLogCallback) {
	e.mu.Lock()
	e.bootstrapLogCallback = cb
	resolver := e.resolver
	e.mu.Unlock()
	if resolver != nil {
		resolver.SetBootstrapLogCallback(cb)
	}
}

func (e *Engine) ResetBootstrapStats() {
	e.mu.Lock()
	resolver := e.resolver
	e.mu.Unlock()
	if resolver != nil {
		resolver.ResetBootstrapStats()
	}
}

func (e *Engine) SetHttpLogCallback(cb HttpLogCallback) {
	e.callbackMu.Lock()
	e.httpLogCallback = cb
	e.callbackMu.Unlock()
}

func (e *Engine) SetOutboundProxyStatusCallback(cb OutboundProxyStatusCallback) {
	e.callbackMu.Lock()
	e.outboundStatusCallback = cb
	e.callbackMu.Unlock()
}

func (e *Engine) SetTrafficCallback(cb TrafficCallback) {
	e.trafficCallback = cb
	if e.trafficTracker != nil {
		e.trafficTracker.SetCallback(cb)
	}
}

func (e *Engine) SetTickIntervalMs(ms int64) {
	if e.trafficTracker != nil {
		e.trafficTracker.SetTickInterval(time.Duration(ms) * time.Millisecond)
	}
}

func (e *Engine) ConfigureOutboundProxy(configJSON string) string {
	cfg, err := parseOutboundProxyConfig(configJSON)
	if err != nil {
		return err.Error()
	}
	e.mu.Lock()
	e.outboundConfig = cfg
	e.mu.Unlock()
	return ""
}

func (e *Engine) reportOutboundStatus(state, message string) {
	e.callbackMu.RLock()
	cb := e.outboundStatusCallback
	e.callbackMu.RUnlock()
	if cb != nil {
		cb.OnOutboundProxyStatus(state, message)
	}
}

func (e *Engine) SetDNS(protocol, primary, fallback, dohURL string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.protocol = protocol
	e.primaryDNS = primary
	e.fallbackDNS = fallback
	e.dohURL = dohURL
	if e.resolver != nil {
		e.resolver.Configure(ParseProtocol(protocol), primary, fallback, dohURL)
	}
}

func (e *Engine) SetBlockResponseType(responseType string) {
	e.responseType = ParseResponseType(responseType)
}

func (e *Engine) notifyLog(domain string, blocked bool, queryType uint16, responseTimeMs int64, appName, resolvedIPs, blockedBy, errorMessage string, cached bool) {
	e.notifyLogWithTTL(domain, blocked, queryType, responseTimeMs, appName, resolvedIPs, blockedBy, errorMessage, cached, 0)
}

func (e *Engine) notifyLogWithTTL(domain string, blocked bool, queryType uint16, responseTimeMs int64, appName, resolvedIPs, blockedBy, errorMessage string, cached bool, ttl int64) {
	if e.logAggregator != nil && e.logAggregator.hasCallback() {
		e.logAggregator.push(logItem{
			Domain:         domain,
			Blocked:        blocked,
			QueryType:      int(queryType),
			ResponseTimeMs: responseTimeMs,
			AppName:        appName,
			ResolvedIPs:    resolvedIPs,
			BlockedBy:      blockedBy,
			ErrorMessage:   errorMessage,
			Cached:         cached,
			Timestamp:      time.Now().UnixMilli(),
			TTL:            ttl,
		})
		return
	}
	if e.logCallback != nil {
		e.logCallback.OnDNSQuery(domain, blocked, int(queryType), responseTimeMs, appName, resolvedIPs, blockedBy, errorMessage, cached)
	}
}

