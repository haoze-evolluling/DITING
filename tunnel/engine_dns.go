// engine_dns.go handles the complete lifecycle of DNS packets intercepted from the TUN interface.
//
// Interception Pipeline:
// 1. Local Assets: Synthesizes loopback answers for internal cosmetic CSS and documentation hosts.
// 2. DDR Mitigation: Returns NXDOMAIN for _dns.resolver.arpa (RFC 9462) to prevent client DoH/DoQ bypass.
// 3. Firewall: Evaluates per-app network blocking rules via Kotlin callbacks.
// 4. Policy & Trie Matching: Evaluates PolicyEngine fast-path rules and mmap bloom/trie structures.
// 5. Cache & Upstream: Checks in-memory cache before forwarding queries to upstream resolvers.
// 6. Upstream Ad Detection: Flags upstream ad-block sinkhole responses (0.0.0.0 / ::) for telemetry attribution.

package tunnel

import (
	"net"
	"strings"
	"time"

	"github.com/miekg/dns"
)

func (e *Engine) handleDNSQuery(queryInfo *DNSQueryInfo) {

	e.mu.Lock()
	running := e.running
	e.mu.Unlock()
	if !running {
		return
	}

	startTime := time.Now()
	domain := strings.ToLower(queryInfo.Domain)

	if domain == LocalAssetHost {
		response := BuildRedirectResponse(queryInfo, localAssetSynthIP)
		e.writeToTUN(response)
		e.totalQueries.Add(1)
		return
	}

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

	if queryInfo.QueryType == dns.TypeA || queryInfo.QueryType == dns.TypeAAAA {
		if ip := e.rewriteIP(domain, queryInfo.QueryType == dns.TypeA); ip != nil {
			response := buildRewriteIPResponse(queryInfo, ip)
			e.writeToTUN(response)
			e.totalQueries.Add(1)
			e.notifyLog(domain, false, queryInfo.QueryType, time.Since(startTime).Milliseconds(), appName, ip.String(), "rewrite="+ip.String(), "", false)
			return
		}
	}

	if domain == "_dns.resolver.arpa" || strings.HasSuffix(domain, "._dns.resolver.arpa") {
		e.handleBlockedDomain(queryInfo, "ddr_blocked", appName, startTime)
		return
	}

	if e.firewallChecker != nil && appName != "" {
		if e.firewallChecker.ShouldBlock(appName) {
			e.handleFirewallBlock(queryInfo, appName, startTime)
			return
		}
	}

	if !e.filterDNS.Load() {
		e.handleForward(queryInfo, appName, startTime)
		return
	}

	if e.policyEngine != nil && e.policyEngine.isActive() && e.policyEngine.hasRules() {
		blocked, reason := e.policyEngine.evaluate(domain, appName, queryInfo.QueryType)
		if blocked {
			e.handleBlockedDomain(queryInfo, reason, appName, startTime)
			return
		}
		if reason == "__ALLOW__" {
			e.handleForward(queryInfo, appName, startTime)
			return
		}

	} else {

		if e.hasImportantMatch(domain) {
			e.handleBlockedDomain(queryInfo, "important", appName, startTime)
			return
		}

		if e.domainChecker != nil {
			checkRes := e.domainChecker.CheckDomain(domain, appName)
			if checkRes == "__ALLOW__" {

				e.handleForward(queryInfo, appName, startTime)
				return
			} else if checkRes != "" {
				e.handleBlockedDomain(queryInfo, checkRes, appName, startTime)
				return
			}
		}
	}

	if e.hasNativeRules.Load() {

		e.mu.Lock()
		secBlooms := e.secBlooms
		secTries := e.secTries
		secTrieIDs := e.secTrieIDs
		adBlooms := e.adBlooms
		adTries := e.adTries
		adTrieIDs := e.adTrieIDs
		e.mu.Unlock()

		var matchedIDs []string

		for i, secTrie := range secTries {
			if secTrie == nil {
				continue
			}
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

		for i, adTrie := range adTries {
			if adTrie == nil {
				continue
			}
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

	if e.dnsCache != nil && e.dnsCache.isEnabled() {
		cachedResp, hit, targets, ipList, resolvedIPs, isNegative, staleCandidate := e.dnsCache.getFast(queryInfo.RawDNSPayload)
		if hit {
			if len(targets) > 0 {
				if chainBlocked, chainReason := e.checkResponseChainTargets(targets, appName, queryInfo.QueryType); chainBlocked {
					e.handleBlockedDomain(queryInfo, chainReason, appName, startTime)
					return
				}
			}
			response := BuildForwardedResponse(queryInfo, cachedResp)
			e.writeToTUN(response)
			e.totalQueries.Add(1)
			if !isNegative && len(ipList) > 0 {
				e.rememberResolvedIPList(queryInfo.Domain, ipList)
			}
			elapsed := time.Since(startTime).Milliseconds()
			e.notifyLog(queryInfo.Domain, false, queryInfo.QueryType, elapsed, appName, resolvedIPs, "", "", true)
			return
		}

		// Fast Stale-While-Revalidate (RFC 8767):
		// Instantly return stale candidate if within stale window, and trigger asynchronous background resolve.
		if staleCandidate != nil && e.dnsCache.isStaleFallbackEnabled() {
			staleResp := e.dnsCache.buildStaleResponse(queryInfo.RawDNSPayload, staleCandidate)
			if staleResp != nil {
				if len(staleCandidate.chainTargets) > 0 {
					if chainBlocked, chainReason := e.checkResponseChainTargets(staleCandidate.chainTargets, appName, queryInfo.QueryType); chainBlocked {
						e.handleBlockedDomain(queryInfo, chainReason, appName, startTime)
						return
					}
				}
				response := BuildForwardedResponse(queryInfo, staleResp)
				e.writeToTUN(response)
				e.totalQueries.Add(1)
				if !staleCandidate.isNegative && len(staleCandidate.ipList) > 0 {
					e.rememberResolvedIPList(queryInfo.Domain, staleCandidate.ipList)
				}
				elapsed := time.Since(startTime).Milliseconds()
				e.notifyLog(queryInfo.Domain, false, queryInfo.QueryType, elapsed, appName, staleCandidate.resolvedIPs, "", "", true)

				// Asynchronous background refresh
				e.mu.Lock()
				resolver := e.resolver
				e.mu.Unlock()
				if resolver != nil {
					payloadCopy := make([]byte, len(queryInfo.RawDNSPayload))
					copy(payloadCopy, queryInfo.RawDNSPayload)
					go func() {
						_, _, _ = e.dnsCache.singleFlight(payloadCopy, func() ([]byte, error) {
							return resolver.Resolve(payloadCopy)
						})
					}()
				}
				return
			}
		}
	}


	e.handleForward(queryInfo, appName, startTime)
}

func rewriteAnswerRecord(q dns.Question, ip net.IP) dns.RR {
	if q.Qtype == dns.TypeAAAA {
		return &dns.AAAA{Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: rewriteAnswerTTL}, AAAA: ip}
	}
	return &dns.A{Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: rewriteAnswerTTL}, A: ip.To4()}
}

func buildRewriteIPResponse(queryInfo *DNSQueryInfo, ip net.IP) []byte {
	var msg dns.Msg
	_ = msg.Unpack(queryInfo.RawDNSPayload)
	resp := new(dns.Msg)
	resp.SetReply(&msg)
	resp.RecursionAvailable = true
	if len(msg.Question) > 0 {
		resp.Answer = append(resp.Answer, rewriteAnswerRecord(msg.Question[0], ip))
	}
	packed, _ := resp.Pack()
	return buildIPUDPPacket(queryInfo, packed)
}

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

func (e *Engine) handleForward(queryInfo *DNSQueryInfo, appName string, startTime time.Time) {

	e.mu.Lock()
	resolver := e.resolver
	dnsCache := e.dnsCache
	e.mu.Unlock()
	if resolver == nil {

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
					if len(staleEntry.chainTargets) > 0 {
						if chainBlocked, chainReason := e.checkResponseChainTargets(staleEntry.chainTargets, appName, queryInfo.QueryType); chainBlocked {
							e.handleBlockedDomain(queryInfo, chainReason, appName, startTime)
							return
						}
					}
					response := BuildForwardedResponse(queryInfo, staleResp)
					e.writeToTUN(response)
					e.totalQueries.Add(1)
					if !staleEntry.isNegative && len(staleEntry.ipList) > 0 {
						e.rememberResolvedIPList(queryInfo.Domain, staleEntry.ipList)
					}
					elapsed := time.Since(startTime).Milliseconds()
					e.notifyLog(queryInfo.Domain, false, queryInfo.QueryType, elapsed, appName, staleEntry.resolvedIPs, "", "", true)
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

	var respMsg dns.Msg
	hasUnpacked := (respMsg.Unpack(resp) == nil)
	if hasUnpacked {
		if chainBlocked, chainReason := e.checkResponseChain(&respMsg, appName); chainBlocked {
			e.handleBlockedDomain(queryInfo, chainReason, appName, startTime)
			return
		}
	}

	blocked := false
	resolvedIPs := ""
	if hasUnpacked {
		blocked = isUpstreamBlockedMsg(&respMsg)
		if !blocked {
			resolvedIPs = resolvedAddressesMsg(&respMsg)
			e.rememberResolvedIPs(queryInfo.Domain, &respMsg)
		}
	} else {
		blocked = isUpstreamBlocked(resp)
		if !blocked {
			resolvedIPs = resolvedAddresses(resp)
		}
	}

	response := BuildForwardedResponse(queryInfo, resp)
	e.writeToTUN(response)
	e.totalQueries.Add(1)

	elapsed := time.Since(startTime).Milliseconds()
	if blocked {
		e.blockedQueries.Add(1)
		logf("BLOCKED: %s (by: upstream_dns, app: %s)", queryInfo.Domain, appName)
		e.notifyLog(queryInfo.Domain, true, queryInfo.QueryType, elapsed, appName, "", "upstream_dns", "", false)
		return
	}

	var respTTL int64
	if hasUnpacked {
		if minTtl, found := extractMinTTL(&respMsg); found {
			respTTL = int64(minTtl)
		}
	}
	e.notifyLogWithTTL(queryInfo.Domain, false, queryInfo.QueryType, elapsed, appName, resolvedIPs, "", "", isCached, respTTL)
}


func isUpstreamBlocked(rawResp []byte) bool {
	var msg dns.Msg
	if err := msg.Unpack(rawResp); err != nil {
		return false
	}
	return isUpstreamBlockedMsg(&msg)
}

func isUpstreamBlockedMsg(msg *dns.Msg) bool {
	if msg == nil || len(msg.Answer) == 0 {
		return false
	}

	nullCount := 0
	ipRecordCount := 0

	for _, rr := range msg.Answer {
		switch r := rr.(type) {
		case *dns.A:
			ipRecordCount++
			if r.A.Equal(net.IPv4zero) || r.A.IsLoopback() {
				nullCount++
			}
		case *dns.AAAA:
			ipRecordCount++
			if r.AAAA.Equal(net.IPv6zero) || r.AAAA.IsLoopback() {
				nullCount++
			}
		}
	}

	return ipRecordCount > 0 && nullCount == ipRecordCount
}

func resolvedAddresses(rawResponse []byte) string {
	var response dns.Msg
	if err := response.Unpack(rawResponse); err != nil {
		return ""
	}
	return resolvedAddressesMsg(&response)
}

func resolvedAddressesMsg(response *dns.Msg) string {
	if response == nil {
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

func (e *Engine) rememberResolvedIPs(domain string, respMsg *dns.Msg) {
	if e == nil || e.ipDomainCache == nil || respMsg == nil || len(respMsg.Answer) == 0 {
		return
	}
	cleanDomain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if cleanDomain == "" {
		return
	}
	for _, ans := range respMsg.Answer {
		switch rr := ans.(type) {
		case *dns.A:
			if rr.A != nil && !rr.A.IsUnspecified() && !rr.A.IsLoopback() {
				e.ipDomainCache.put(rr.A.String(), cleanDomain)
			}
		case *dns.AAAA:
			if rr.AAAA != nil && !rr.AAAA.IsUnspecified() && !rr.AAAA.IsLoopback() {
				e.ipDomainCache.put(rr.AAAA.String(), cleanDomain)
			}
		}
	}
}

func (e *Engine) rememberResolvedIPList(domain string, ipList []string) {
	if e == nil || e.ipDomainCache == nil || len(ipList) == 0 {
		return
	}
	cleanDomain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if cleanDomain == "" {
		return
	}
	for _, ip := range ipList {
		if ip != "" && ip != "0.0.0.0" && ip != "::" && ip != "127.0.0.1" {
			e.ipDomainCache.put(ip, cleanDomain)
		}
	}
}

