package tunnel

import (
	"encoding/json"
	"strings"
	"time"
)

// ClearDNSCache removes all entries from the in-memory DNS cache.
func (e *Engine) ClearDNSCache() {
	if e.dnsCache != nil {
		e.dnsCache.clear()
	}
}

// GetRouter returns the engine's Router for setting outbound adapters.
func (e *Engine) GetRouter() *Router {
	return e.router
}

// SetOutboundAdapter sets the active outbound adapter on the router.
// Pass nil to switch to DNS-only mode (no proxy).
func (e *Engine) SetOutboundAdapter(adapter OutboundAdapter) {
	e.router.SetAdapter(adapter)
}

// SetDomainChecker sets the Kotlin-side domain checker.
// This is called before Start() to provide the blocking logic for rules not in the trie (like Custom Rules).
func (e *Engine) SetDomainChecker(checker DomainChecker) {
	e.domainChecker = checker
}

// ApplyRuleSnapshot updates the Go-side policy engine rules from a JSON snapshot.
// Returns an error message string, or empty string on success.
func (e *Engine) ApplyRuleSnapshot(jsonSnapshot string) string {
	if e.policyEngine == nil {
		e.policyEngine = newPolicyEngine()
	}
	if err := e.policyEngine.applySnapshot(jsonSnapshot); err != nil {
		logf("ApplyRuleSnapshot error: %v", err)
		return err.Error()
	}
	logf("ApplyRuleSnapshot successfully updated Go policy engine rules")
	return ""
}

func (e *Engine) SetFilterDNS(enabled bool) { e.filterDNS.Store(enabled) }

// SetRewriteRules replaces the CNAME rewrite map used by DNS and HTTP(S).
// The input is a JSON object whose keys are source domains and values are
// target domains. Parent-domain rules also match subdomains.
func (e *Engine) SetRewriteRules(content string) {
	rules := make(map[string]string)
	if content != "" {
		if err := json.Unmarshal([]byte(content), &rules); err != nil {
			logf("SetRewriteRules: invalid JSON: %v", err)
			return
		}
	}
	clean := make(map[string]string, len(rules))
	for source, target := range rules {
		source = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(source)), ".")
		target = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(target)), ".")
		if source != "" && target != "" {
			clean[source] = target
		}
	}
	e.mu.Lock()
	e.rewriteRules = clean
	e.mu.Unlock()
}

func (e *Engine) rewriteTarget(domain string) string {
	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	e.mu.Lock()
	defer e.mu.Unlock()
	for candidate := domain; candidate != ""; {
		if target := e.rewriteRules[candidate]; target != "" {
			return target
		}
		dot := strings.IndexByte(candidate, '.')
		if dot < 0 {
			break
		}
		candidate = candidate[dot+1:]
	}
	return ""
}

// SetFirewallChecker sets the Kotlin-side firewall checker.
// This is called before Start() to enable per-app DNS blocking.
func (e *Engine) SetFirewallChecker(checker FirewallChecker) {
	e.firewallChecker = checker
}

// SetAppResolver sets the Kotlin-side app name resolver for logging who made the request.
func (e *Engine) SetAppResolver(resolver AppResolver) {
	e.appResolver = resolver
}

// SetAppUidResolver sets the Kotlin-side UID→package resolver used for
// full-tunnel per-app DNS attribution and connection logging.
func (e *Engine) SetAppUidResolver(resolver AppUidResolver) {
	e.appUidResolver = resolver
}

// SetLogCallback sets the callback for DNS query events.
func (e *Engine) SetLogCallback(cb LogCallback) {
	e.logCallback = cb
}

// SetBatchLogCallback sets the callback for batched DNS and connection query events.
func (e *Engine) SetBatchLogCallback(cb BatchLogCallback) {
	e.batchLogCallback = cb
	if e.logAggregator != nil {
		e.logAggregator.setCallback(cb)
		if cb != nil {
			e.logAggregator.start()
		}
	}
}

// SetRaceLogCallback sets the callback for DNS race events.
func (e *Engine) SetRaceLogCallback(cb RaceLogCallback) {
	e.mu.Lock()
	e.raceLogCallback = cb
	resolver := e.resolver
	e.mu.Unlock()
	if resolver != nil {
		resolver.SetRaceLogCallback(cb)
	}
}

// SetBootstrapLogCallback sets the callback for Bootstrap DNS events.
func (e *Engine) SetBootstrapLogCallback(cb BootstrapLogCallback) {
	e.mu.Lock()
	e.bootstrapLogCallback = cb
	resolver := e.resolver
	e.mu.Unlock()
	if resolver != nil {
		resolver.SetBootstrapLogCallback(cb)
	}
}

// ResetBootstrapStats clears health statistics and host cache in the bootstrap resolver.
func (e *Engine) ResetBootstrapStats() {
	e.mu.Lock()
	resolver := e.resolver
	e.mu.Unlock()
	if resolver != nil {
		resolver.ResetBootstrapStats()
	}
}

// SetHttpLogCallback registers the Kotlin persistence bridge for inspected
// HTTP(S) request metadata.
func (e *Engine) SetHttpLogCallback(cb HttpLogCallback) {
	e.httpLogCallback = cb
}

func (e *Engine) SetOutboundProxyStatusCallback(cb OutboundProxyStatusCallback) {
	e.outboundStatusCallback = cb
}

// SetTrafficCallback registers the Kotlin callback for periodic traffic statistics deltas.
func (e *Engine) SetTrafficCallback(cb TrafficCallback) {
	e.trafficCallback = cb
	if e.trafficTracker != nil {
		e.trafficTracker.SetCallback(cb)
	}
}

// SetTickIntervalMs sets the periodic traffic-statistics tick interval in
// milliseconds (gomobile-bound; Kotlin drives it from screen state:
// 1000ms while interactive, 10000ms with the screen off). Deltas keep
// accumulating in per-UID atomics regardless of the interval, so totals
// are conserved; only reporting cadence changes.
func (e *Engine) SetTickIntervalMs(ms int64) {
	if e.trafficTracker != nil {
		e.trafficTracker.SetTickInterval(time.Duration(ms) * time.Millisecond)
	}
}

// ConfigureOutboundProxy validates and stores a session snapshot. An empty
// return value means success; a non-empty value is safe to display to users.
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
	if cb := e.outboundStatusCallback; cb != nil {
		cb.OnOutboundProxyStatus(state, message)
	}
}

// SetDNS configures the DNS settings.
// protocol: "PLAIN", "DOH", "DOT", "DOQ"
// primary: primary DNS server (e.g., "8.8.8.8")
// fallback: fallback DNS server (e.g., "1.1.1.1"), can be empty
// dohURL: DoH/DoQ server URL (e.g., "https://dns.cloudflare.com/dns-query")
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

// SetBlockResponseType sets how blocked domains are responded to.
// responseType: "CUSTOM_IP" (0.0.0.0), "NXDOMAIN", "REFUSED"
func (e *Engine) SetBlockResponseType(responseType string) {
	e.responseType = ParseResponseType(responseType)
}

func (e *Engine) notifyLog(domain string, blocked bool, queryType uint16, responseTimeMs int64, appName, resolvedIPs, blockedBy, errorMessage string, cached bool) {
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
		})
		return
	}
	if e.logCallback != nil {
		e.logCallback.OnDNSQuery(domain, blocked, int(queryType), responseTimeMs, appName, resolvedIPs, blockedBy, errorMessage, cached)
	}
}
