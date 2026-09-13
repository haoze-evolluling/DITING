package tunnel

import (
	"net"
	"strings"
	"time"

	"github.com/miekg/dns"
)

// handleDNSQuery processes a single DNS query.
func (e *Engine) handleDNSQuery(queryInfo *DNSQueryInfo) {
	// Early exit: if engine was stopped while this goroutine was queued,
	// don't touch any shared state — the resources may already be freed.
	e.mu.Lock()
	running := e.running
	e.mu.Unlock()
	if !running {
		return
	}

	startTime := time.Now()
	domain := strings.ToLower(queryInfo.Domain)

	// Local asset host: synthesize a response with a routable IP from the
	// RFC 5737 documentation range so the browser can SYN to it and have
	// the packet enter our TUN; the userspace stack catches the flow and
	// serves cosmetic.css from memory based on SNI.
	if domain == LocalAssetHost {
		response := BuildRedirectResponse(queryInfo, localAssetSynthIP)
		e.writeToTUN(response)
		e.totalQueries.Add(1)
		return
	}

	// Fetch App Name for logging (and firewall)
	appName := ""
	if e.appResolver != nil {
		appName = e.appResolver.ResolveApp(
			int(queryInfo.SourcePort),
			[]byte(queryInfo.SourceIP),
			[]byte(queryInfo.DestIP),
			int(queryInfo.DestPort),
		)
	} else if uidr, appUidr := e.uidResolver, e.appUidResolver; uidr != nil && appUidr != nil {
		uid := uidr.ResolveUID(
			ProtocolUDP,
			queryInfo.SourceIP.String(),
			int(queryInfo.SourcePort),
			queryInfo.DestIP.String(),
			int(queryInfo.DestPort),
		)
		if uid != UIDUnknown {
			appName = appUidr.PackageForUid(uid)
		}
	}

	// Apply literal-IP hosts rewrites in the userspace DNS path used by HTTPS
	// inspection. This path does not go through the standalone resolver.
	if target := e.rewriteTarget(domain); target != "" {
		if ip := net.ParseIP(target); ip != nil && (queryInfo.QueryType == dns.TypeA || queryInfo.QueryType == dns.TypeAAAA) {
			if (queryInfo.QueryType == dns.TypeA && ip.To4() != nil) || (queryInfo.QueryType == dns.TypeAAAA && ip.To4() == nil) {
				response := buildRewriteIPResponse(queryInfo, ip)
				e.writeToTUN(response)
				e.totalQueries.Add(1)
				e.notifyLog(domain, false, queryInfo.QueryType, time.Since(startTime).Milliseconds(), appName, ip.String(), "rewrite="+target, "", false)
				return
			}
		}
	}

	// Firewall check (per-app blocking via Kotlin callback)
	if e.firewallChecker != nil && appName != "" {
		if e.firewallChecker.ShouldBlock(appName) {
			e.handleFirewallBlock(queryInfo, appName, startTime)
			return
		}
	}

	// Engine-level capability switch: when disabled, DNS queries skip all
	// domain-rule evaluation and go straight to forwarding. The Kotlin side
	// keeps DNS filtering enabled at all times, including while HTTPS
	// inspection is active.
	if !e.filterDNS.Load() {
		e.handleForward(queryInfo, appName, startTime)
		return
	}

	// 1. Local Go PolicyEngine check (zero JNI, fast path)
	if e.policyEngine != nil && e.policyEngine.isActive() {
		blocked, reason := e.policyEngine.evaluate(domain, appName)
		if blocked {
			e.handleBlockedDomain(queryInfo, reason, appName, startTime)
			return
		}
		// PolicyEngine evaluated domain as not blocked: fall through to cache check & forward (0 JNI).
	} else {
		// Fallback to legacy checks if policyEngine has no rules
		if e.hasImportantMatch(domain) {
			e.handleBlockedDomain(queryInfo, "important", appName, startTime)
			return
		}

		// Custom & Subscription rules override: single-shot JNI check.
		// "__ALLOW__" = explicitly allowed, non-empty = blocked with reason.
		if e.domainChecker != nil {
			checkRes := e.domainChecker.CheckDomain(domain, appName)
			if checkRes == "__ALLOW__" {
				// Explicitly allowed by user or whitelist, skip trie checks
				e.handleForward(queryInfo, appName, startTime)
				return
			} else if checkRes != "" {
				e.handleBlockedDomain(queryInfo, checkRes, appName, startTime)
				return
			}
		}
	}

	if e.hasNativeRules.Load() {
		// Fast native Go domain blocking: Step 1 Bloom filter (O(1)) — if it says
		// "definitely not blocked", skip the trie entirely; Step 2 Mmap trie
		// (O(L)) confirms. Eliminates trie traversal for ~90%+ of clean queries.

		// Snapshot tries under lock to avoid use-after-free when Stop() closes them.
		e.mu.Lock()
		secBlooms := e.secBlooms
		secTries := e.secTries
		secTrieIDs := e.secTrieIDs
		adBlooms := e.adBlooms
		adTries := e.adTries
		adTrieIDs := e.adTrieIDs
		e.mu.Unlock()

		// Collect ALL matching filter IDs so every filter gets attribution in statistics
		var matchedIDs []string

		// Security domains
		for i, secTrie := range secTries {
			if secTrie == nil { continue }
			var secBloom *BloomFilter
			if i < len(secBlooms) {
				secBloom = secBlooms[i]
			}
			if secBloom == nil || secBloom.MightContainDomainOrParent(domain) {
				if secTrie.ContainsOrParent(domain) {
					id := "security"
					if i < len(secTrieIDs) {
						id = secTrieIDs[i]
					}
					matchedIDs = append(matchedIDs, id)
				}
			}
		}

		// Ad domains
		for i, adTrie := range adTries {
			if adTrie == nil { continue }
			var adBloom *BloomFilter
			if i < len(adBlooms) {
				adBloom = adBlooms[i]
			}
			if adBloom == nil || adBloom.MightContainDomainOrParent(domain) {
				if adTrie.ContainsOrParent(domain) {
					id := "filter_list"
					if i < len(adTrieIDs) {
						id = adTrieIDs[i]
					}
					matchedIDs = append(matchedIDs, id)
				}
			}
		}

		if len(matchedIDs) > 0 {
			e.handleBlockedDomain(queryInfo, strings.Join(matchedIDs, ","), appName, startTime)
			return
		}
	}

	// Cache Check (Fast path)
	if e.dnsCache != nil && e.dnsCache.isEnabled() {
		if cachedResp, hit, _ := e.dnsCache.get(queryInfo.RawDNSPayload); hit {
			response := BuildForwardedResponse(queryInfo, cachedResp)
			e.writeToTUN(response)
			e.totalQueries.Add(1)
			elapsed := time.Since(startTime).Milliseconds()
			e.notifyLog(queryInfo.Domain, false, queryInfo.QueryType, elapsed, appName, resolvedAddresses(cachedResp), "", "", true)
			return
		}
	}

	e.handleForward(queryInfo, appName, startTime)
}

func buildRewriteIPResponse(queryInfo *DNSQueryInfo, ip net.IP) []byte {
	var msg dns.Msg
	_ = msg.Unpack(queryInfo.RawDNSPayload)
	resp := new(dns.Msg)
	resp.SetReply(&msg)
	resp.RecursionAvailable = true
	if len(msg.Question) > 0 {
		q := msg.Question[0]
		if q.Qtype == dns.TypeA {
			resp.Answer = append(resp.Answer, &dns.A{Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300}, A: ip.To4()})
		} else if q.Qtype == dns.TypeAAAA {
			resp.Answer = append(resp.Answer, &dns.AAAA{Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: 300}, AAAA: ip})
		}
	}
	packed, _ := resp.Pack()
	return buildIPUDPPacket(queryInfo, packed)
}

// handleFirewallBlock handles a DNS query blocked by the per-app firewall.
func (e *Engine) handleFirewallBlock(queryInfo *DNSQueryInfo, appName string, startTime time.Time) {
	var response []byte
	switch e.responseType {
	case ResponseNXDomain:
		response = BuildNXDomainResponse(queryInfo)
	case ResponseRefused:
		response = BuildRefusedResponse(queryInfo)
	default:
		response = BuildBlockedResponse(queryInfo)
	}

	e.writeToTUN(response)
	e.totalQueries.Add(1)
	e.blockedQueries.Add(1)

	elapsed := time.Since(startTime).Milliseconds()
	logf("BLOCKED: %s (by: firewall, app: %s)", queryInfo.Domain, appName)
	e.notifyLog(queryInfo.Domain, true, queryInfo.QueryType, elapsed, appName, "", "firewall", "", false)
}

// handleBlockedDomain handles a blocked domain.
func (e *Engine) handleBlockedDomain(queryInfo *DNSQueryInfo, blockedBy, appName string, startTime time.Time) {
	var response []byte
	switch e.responseType {
	case ResponseNXDomain:
		response = BuildNXDomainResponse(queryInfo)
	case ResponseRefused:
		response = BuildRefusedResponse(queryInfo)
	default:
		response = BuildBlockedResponse(queryInfo)
	}

	e.writeToTUN(response)
	e.totalQueries.Add(1)
	e.blockedQueries.Add(1)

	elapsed := time.Since(startTime).Milliseconds()
	logf("BLOCKED: %s (by: %s, app: %s)", queryInfo.Domain, blockedBy, appName)
	e.notifyLog(queryInfo.Domain, true, queryInfo.QueryType, elapsed, appName, "", blockedBy, "", false)
}

// handleForward forwards a DNS query to upstream and writes the response.
func (e *Engine) handleForward(queryInfo *DNSQueryInfo, appName string, startTime time.Time) {
	// Grab resolver snapshot under lock to avoid nil dereference during shutdown
	e.mu.Lock()
	resolver := e.resolver
	dnsCache := e.dnsCache
	e.mu.Unlock()
	if resolver == nil {
		// Engine is shutting down, drop the query silently
		return
	}

	var resp []byte
	var isCached bool
	var err error

	if dnsCache != nil && dnsCache.isEnabled() {
		resp, isCached, err = dnsCache.singleFlight(queryInfo.RawDNSPayload, func() ([]byte, error) {
			return resolver.Resolve(queryInfo.RawDNSPayload)
		})
		if err != nil {
			_, _, staleEntry := dnsCache.get(queryInfo.RawDNSPayload)
			if staleEntry != nil {
				staleResp := dnsCache.buildStaleResponse(queryInfo.RawDNSPayload, staleEntry)
				if staleResp != nil {
					response := BuildForwardedResponse(queryInfo, staleResp)
					e.writeToTUN(response)
					e.totalQueries.Add(1)
					elapsed := time.Since(startTime).Milliseconds()
					e.notifyLog(queryInfo.Domain, false, queryInfo.QueryType, elapsed, appName, resolvedAddresses(staleResp), "", "", true)
					return
				}
			}
		}
	} else {
		resp, err = resolver.Resolve(queryInfo.RawDNSPayload)
	}

	if err != nil {
		logf("DNS resolve failed for %s: %v", queryInfo.Domain, err)
		servfail := BuildServfailResponse(queryInfo)
		e.writeToTUN(servfail)
		e.totalQueries.Add(1)

		elapsed := time.Since(startTime).Milliseconds()
		e.notifyLog(queryInfo.Domain, false, queryInfo.QueryType, elapsed, appName, "", "", err.Error(), false)
		return
	}

	// Detect upstream DNS blocking (e.g., NextDNS/AdGuard DNS returning 0.0.0.0)
	if isUpstreamBlocked(resp) {
		response := BuildForwardedResponse(queryInfo, resp)
		e.writeToTUN(response)
		e.totalQueries.Add(1)
		e.blockedQueries.Add(1)

		elapsed := time.Since(startTime).Milliseconds()
		logf("BLOCKED: %s (by: upstream_dns, app: %s)", queryInfo.Domain, appName)
		e.notifyLog(queryInfo.Domain, true, queryInfo.QueryType, elapsed, appName, "", "upstream_dns", "", false)
		return
	}

	response := BuildForwardedResponse(queryInfo, resp)
	e.writeToTUN(response)
	e.totalQueries.Add(1)

	elapsed := time.Since(startTime).Milliseconds()
	e.notifyLog(queryInfo.Domain, false, queryInfo.QueryType, elapsed, appName, resolvedAddresses(resp), "", "", isCached)
}

// isUpstreamBlocked reports whether a DNS response indicates the domain was
// blocked by the upstream server (e.g., NextDNS, AdGuard DNS, ControlD),
// which typically return 0.0.0.0 (A) or :: (AAAA). Only flagged when ALL
// answer records are null IPs; NXDOMAIN, empty answers, and mixed null/real
// results are NOT flagged to avoid false positives (e.g. typos).
func isUpstreamBlocked(rawResp []byte) bool {
	var msg dns.Msg
	if err := msg.Unpack(rawResp); err != nil {
		return false
	}

	if len(msg.Answer) == 0 {
		return false
	}

	nullCount := 0
	ipRecordCount := 0

	for _, rr := range msg.Answer {
		switch r := rr.(type) {
		case *dns.A:
			ipRecordCount++
			if r.A.Equal(net.IPv4zero) {
				nullCount++
			}
		case *dns.AAAA:
			ipRecordCount++
			if r.AAAA.Equal(net.IPv6zero) {
				nullCount++
			}
		}
	}

	return ipRecordCount > 0 && nullCount == ipRecordCount
}

// resolvedAddresses extracts comma-separated IP strings from the answer section.
func resolvedAddresses(rawResponse []byte) string {
	var response dns.Msg
	if err := response.Unpack(rawResponse); err != nil {
		return ""
	}
	seen := make(map[string]struct{})
	addresses := make([]string, 0, len(response.Answer))
	for _, answer := range response.Answer {
		var address string
		switch record := answer.(type) {
		case *dns.A:
			address = record.A.String()
		case *dns.AAAA:
			address = record.AAAA.String()
		}
		if address == "" {
			continue
		}
		if _, exists := seen[address]; exists {
			continue
		}
		seen[address] = struct{}{}
		addresses = append(addresses, address)
	}
	return strings.Join(addresses, ",")
}
