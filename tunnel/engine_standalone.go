package tunnel

import (
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/miekg/dns"
)

// Standalone DNS server (root/proxy mode).

// ServeDNS handles incoming DNS queries directly from a socket (no TUN fd).
func (e *Engine) ServeDNS(w dns.ResponseWriter, r *dns.Msg) {
	e.serveDNS(w, r, "", UIDUnknown)
}

// serveDNS is the implementation. appOverride, when non-empty, is used as
// the logged app name (full-tunnel passes the UID-resolved package here so
// DNS is attributed to the real app instead of the root-mode "RootProxy").
func (e *Engine) serveDNS(w dns.ResponseWriter, r *dns.Msg, appOverride string, uid int) {
	startTime := time.Now()
	if len(r.Question) == 0 {
		return
	}

	domain := strings.ToLower(r.Question[0].Name)
	domain = strings.TrimSuffix(domain, ".")
	queryType := r.Question[0].Qtype
	if !e.appAllowlistDomainAllowed(uid, domain) {
		e.standaloneBlock(w, r, "app_allowlist", appOverride, startTime)
		return
	}

	// Local asset host: synthesize a response with a routable IP from
	// the RFC 5737 documentation range so the browser can SYN to it
	// and have the packet enter our TUN.
	if domain == LocalAssetHost {
		m := new(dns.Msg)
		m.SetReply(r)
		if queryType == dns.TypeA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A %s", r.Question[0].Name, localAssetSynthIP.String()))
			m.Answer = append(m.Answer, rr)
		} else if queryType == dns.TypeAAAA {
			// No IPv6 for local asset host; return empty NOERROR
		}
		_ = w.WriteMsg(m)
		e.totalQueries.Add(1)
		return
	}

	appName := "RootProxy"
	// Try to resolve the real app name from the source port of the incoming connection.
	// iptables REDIRECT preserves the original source port, so we can look up the UID
	// in /proc/net/udp by matching that port.
	if appOverride != "" {
		appName = appOverride
	} else if e.appResolver != nil {
		if addr := w.RemoteAddr(); addr != nil {
			srcPort := 0
			srcIP := net.IPv4(127, 0, 0, 1)

			switch a := addr.(type) {
			case *net.UDPAddr:
				srcPort = a.Port
				if a.IP != nil {
					srcIP = a.IP
				}
			case *net.TCPAddr:
				srcPort = a.Port
				if a.IP != nil {
					srcIP = a.IP
				}
			default:
				// Fallback: parse "host:port" string
				if host, portStr, err := net.SplitHostPort(addr.String()); err == nil {
					if p, err2 := fmt.Sscanf(portStr, "%d", &srcPort); p == 1 && err2 == nil {
						if parsed := net.ParseIP(host); parsed != nil {
							srcIP = parsed
						}
					}
				}
			}

			if srcPort > 0 {
				// Normalize to IPv4 bytes if possible, otherwise use raw 16-byte IPv6
				ipBytes := srcIP.To4()
				if ipBytes == nil {
					ipBytes = srcIP.To16()
				}
				if ipBytes == nil {
					ipBytes = []byte{127, 0, 0, 1}
				}

				resolved := e.appResolver.ResolveApp(
					srcPort,
					ipBytes,
					[]byte{127, 0, 0, 1},
					53,
				)
				if resolved != "" {
					appName = resolved
				}
			}
		}
	}

	// 0. Firewall (App Blocker) Check
	if e.firewallChecker != nil && appName != "" && appName != "RootProxy" {
		if e.firewallChecker.ShouldBlock(appName) {
			e.standaloneBlock(w, r, "firewall", appName, startTime)
			return
		}
	}

	// CNAME rewrites take precedence over allow/block rules. Resolve the
	// target through the configured upstream and return a complete answer so
	// Android stub resolvers do not have to chase an incomplete CNAME.
	if target := e.rewriteTarget(domain); target != "" {
		if e.standaloneRewrite(w, r, target, appName, startTime) {
			return
		}
	}

	// 1. Local Go PolicyEngine check (zero JNI, fast path)
	if e.policyEngine != nil && e.policyEngine.isActive() {
		blocked, reason := e.policyEngine.evaluate(domain, appName)
		if blocked {
			e.standaloneBlock(w, r, reason, appName, startTime)
			return
		}
		e.standaloneForward(w, r, appName, startTime, uid)
		return
	} else {
		// Fallback to legacy checks if policyEngine has no rules
		if e.hasImportantMatch(domain) {
			e.standaloneBlock(w, r, "important", appName, startTime)
			return
		}
		if e.domainChecker != nil {
			checkRes := e.domainChecker.CheckDomain(domain, appName)
			if checkRes == "__ALLOW__" {
				e.standaloneForward(w, r, appName, startTime, uid)
				return
			} else if checkRes != "" {
				e.standaloneBlock(w, r, checkRes, appName, startTime)
				return
			}
		}
	}

	// 2. Fast Native Go Tries (Security then Ads)
	e.mu.Lock()
	secBlooms := e.secBlooms
	secTries := e.secTries
	adBlooms := e.adBlooms
	adTries := e.adTries
	e.mu.Unlock()

	var matchedIDs []string

	for i, secTrie := range secTries {
		if secTrie == nil { continue }
		var secBloom *BloomFilter
		if i < len(secBlooms) { secBloom = secBlooms[i] }
		if secBloom == nil || secBloom.MightContainDomainOrParent(domain) {
			if secTrie.ContainsOrParent(domain) {
				id := "security"
				if i < len(e.secTrieIDs) { id = e.secTrieIDs[i] }
				matchedIDs = append(matchedIDs, id)
			}
		}
	}

	for i, adTrie := range adTries {
		if adTrie == nil { continue }
		var adBloom *BloomFilter
		if i < len(adBlooms) { adBloom = adBlooms[i] }
		if adBloom == nil || adBloom.MightContainDomainOrParent(domain) {
			if adTrie.ContainsOrParent(domain) {
				id := "filter_list"
				if i < len(e.adTrieIDs) { id = e.adTrieIDs[i] }
				matchedIDs = append(matchedIDs, id)
			}
		}
	}

	if len(matchedIDs) > 0 {
		e.standaloneBlock(w, r, strings.Join(matchedIDs, ","), appName, startTime)
		return
	}

	// 3. Forward to Upstream
	e.standaloneForward(w, r, appName, startTime, uid)
}

// lookupIP resolves a domain to an IP via the engine's internal resolver.
// Used by the MITM proxy to bypass Android's problematic system DNS resolver
// (the app itself may be excluded from the VPN). Uses the full Resolve()
// pipeline (DoH/DoT/DoQ/Plain + fallback); on transport failure it falls back
// to direct UDP against well-known public resolvers. A successful response
// with no A record (NXDOMAIN / empty answer) is NOT retried — that's
// intentional filtering by the user's configured DNS.
func (e *Engine) lookupIP(domain string) (net.IP, error) {
	e.mu.Lock()
	resolver := e.resolver
	e.mu.Unlock()

	if resolver == nil {
		return nil, fmt.Errorf("engine resolver not initialized")
	}

	msg := new(dns.Msg)
	msg.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	msg.RecursionDesired = true

	rawQuery, err := msg.Pack()
	if err != nil {
		return nil, fmt.Errorf("pack query: %w", err)
	}

	resp, err := resolver.Resolve(rawQuery)
	if err != nil {
		// Primary + configured fallback both failed at the transport
		// level. Try unfiltered public DNS over plain UDP so the MITM
		// proxy doesn't have to fall through to Go's system resolver
		// (which is unreliable on Android for VPN-excluded processes).
		for _, server := range []string{"1.1.1.1:53", "8.8.8.8:53"} {
			if ip, fbErr := resolver.ResolveARecord(domain, server); fbErr == nil && ip != nil {
				logf("lookupIP: %s resolved via public fallback %s (primary err: %v)", domain, server, err)
				return ip, nil
			}
		}
		return nil, fmt.Errorf("resolve %s: %w", domain, err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		return nil, fmt.Errorf("unpack response: %w", err)
	}

	for _, rr := range respMsg.Answer {
		if a, ok := rr.(*dns.A); ok {
			return a.A.To4(), nil
		}
	}

	return nil, fmt.Errorf("no A record for %s", domain)
}

func (e *Engine) standaloneBlock(w dns.ResponseWriter, r *dns.Msg, blockedBy, appName string, startTime time.Time) {
	m := new(dns.Msg)
	m.SetReply(r)

	e.mu.Lock()
	responseType := e.responseType
	dynamicConfig := e.dynamicResponse
	e.mu.Unlock()
	responseType = e.dynamicBlocks.responseFor(strings.TrimSuffix(strings.ToLower(r.Question[0].Name), "."), dynamicConfig, responseType)
	switch responseType {
	case ResponseNXDomain:
		m.Rcode = dns.RcodeNameError
	case ResponseRefused:
		m.Rcode = dns.RcodeRefused
	case ResponseNoData:
		m.Rcode = dns.RcodeSuccess
	default:
		m.Rcode = dns.RcodeSuccess
		if r.Question[0].Qtype == dns.TypeA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 0.0.0.0", r.Question[0].Name))
			m.Answer = append(m.Answer, rr)
		} else if r.Question[0].Qtype == dns.TypeAAAA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN AAAA ::", r.Question[0].Name))
			m.Answer = append(m.Answer, rr)
		}
	}

	_ = w.WriteMsg(m)
	e.totalQueries.Add(1)
	e.blockedQueries.Add(1)
	elapsed := time.Since(startTime).Milliseconds()
	e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), true, r.Question[0].Qtype, elapsed, appName, "", blockedBy, "", false)
}

func (e *Engine) standaloneForward(w dns.ResponseWriter, r *dns.Msg, appName string, startTime time.Time, uid int) {
	raw, err := r.Pack()
	if err != nil {
		dns.HandleFailed(w, r)
		return
	}

	// Grab resolver snapshot under lock to avoid nil dereference during shutdown
	e.mu.Lock()
	resolver := e.resolver
	dnsCache := e.dnsCache
	e.mu.Unlock()
	if resolver == nil {
		dns.HandleFailed(w, r)
		return
	}

	var respRaw []byte
	var isCached bool
	if dnsCache != nil && dnsCache.isEnabled() {
		respRaw, isCached, err = dnsCache.singleFlight(raw, func() ([]byte, error) {
			return resolver.Resolve(raw)
		})
		if err != nil {
			_, _, staleEntry := dnsCache.get(raw)
			if staleEntry != nil {
				staleResp := dnsCache.buildStaleResponse(raw, staleEntry)
				if staleResp != nil {
					var respMsg dns.Msg
					if err := respMsg.Unpack(staleResp); err == nil {
						respMsg.Id = r.Id
						e.rememberAppAllowlistResponse(uid, &respMsg)
						_ = w.WriteMsg(&respMsg)
						e.totalQueries.Add(1)
						elapsed := time.Since(startTime).Milliseconds()
						e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, r.Question[0].Qtype, elapsed, appName, resolvedAddresses(staleResp), "", "", true)
						return
					}
				}
			}
		}
	} else {
		respRaw, err = resolver.Resolve(raw)
	}

	if err != nil {
		logf("DNS resolve failed standalone %s: %v", r.Question[0].Name, err)
		dns.HandleFailed(w, r)
		e.totalQueries.Add(1)
		elapsed := time.Since(startTime).Milliseconds()
		e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, r.Question[0].Qtype, elapsed, appName, "", "", err.Error(), false)
		return
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(respRaw); err != nil {
		dns.HandleFailed(w, r)
		e.totalQueries.Add(1)
		e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, r.Question[0].Qtype, time.Since(startTime).Milliseconds(), appName, "", "", err.Error(), false)
		return
	}

	if isUpstreamBlocked(respRaw) {
		e.totalQueries.Add(1)
		e.blockedQueries.Add(1)
		elapsed := time.Since(startTime).Milliseconds()
		e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), true, r.Question[0].Qtype, elapsed, appName, "", "upstream_dns", "", false)
	} else {
		e.totalQueries.Add(1)
		elapsed := time.Since(startTime).Milliseconds()
		e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, r.Question[0].Qtype, elapsed, appName, resolvedAddresses(respRaw), "", "", isCached)
	}

	respMsg.Id = r.Id
	e.rememberAppAllowlistResponse(uid, &respMsg)
	_ = w.WriteMsg(&respMsg)
}

func (e *Engine) standaloneRewrite(w dns.ResponseWriter, r *dns.Msg, target, appName string, startTime time.Time) bool {
	if len(r.Question) != 1 {
		return false
	}
	qtype := r.Question[0].Qtype
	if qtype != dns.TypeA && qtype != dns.TypeAAAA {
		return false
	}

	e.mu.Lock()
	resolver := e.resolver
	e.mu.Unlock()
	if resolver == nil {
		return false
	}

	targetQuery := new(dns.Msg)
	targetQuery.SetQuestion(dns.Fqdn(target), qtype)
	targetQuery.RecursionDesired = true
	rawQuery, err := targetQuery.Pack()
	if err != nil {
		return false
	}
	rawResponse, err := resolver.Resolve(rawQuery)
	if err != nil {
		logf("Rewrite target resolve failed for %s: %v", target, err)
		return false
	}
	resolved := new(dns.Msg)
	if err := resolved.Unpack(rawResponse); err != nil {
		return false
	}

	response := new(dns.Msg)
	response.SetReply(r)
	cname, err := dns.NewRR(fmt.Sprintf("%s 300 IN CNAME %s", r.Question[0].Name, dns.Fqdn(target)))
	if err != nil {
		return false
	}
	response.Answer = append(response.Answer, cname)
	resolvedIP := ""
	for _, rr := range resolved.Answer {
		switch record := rr.(type) {
		case *dns.A:
			if qtype == dns.TypeA {
				response.Answer = append(response.Answer, record)
				if resolvedIP == "" { resolvedIP = record.A.String() }
			}
		case *dns.AAAA:
			if qtype == dns.TypeAAAA {
				response.Answer = append(response.Answer, record)
				if resolvedIP == "" { resolvedIP = record.AAAA.String() }
			}
		}
	}
	if len(response.Answer) == 1 {
		return false
	}
	_ = w.WriteMsg(response)
	e.totalQueries.Add(1)
	e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, qtype, time.Since(startTime).Milliseconds(), appName, resolvedIP, "rewrite="+target, "", false)
	return true
}

// StartStandalone starts the engine in DNS-only standalone mode on 127.0.0.1:port
// It bypasses TUN and directly serves incoming UDP/TCP DNS queries.
func (e *Engine) StartStandalone(port int) error {
	e.mu.Lock()

	var oldUdp, oldTcp, oldUdp6, oldTcp6 *dns.Server
	var oldResolver *Resolver

	// If already running, capture pointers to release outside lock
	if e.running {
		oldUdp = e.standaloneUdp
		e.standaloneUdp = nil
		oldTcp = e.standaloneTcp
		e.standaloneTcp = nil
		oldUdp6 = e.standaloneUdp6
		e.standaloneUdp6 = nil
		oldTcp6 = e.standaloneTcp6
		e.standaloneTcp6 = nil
		oldResolver = e.resolver
		e.resolver = nil
		e.running = false
	}

	e.running = true
	e.totalQueries.Store(0)
	e.blockedQueries.Store(0)

	// Since we are not using a TUN interface, we don't need a SocketProtector
	// Root/Proxy mode traffic naturally avoids loops due to iptables owner UID matching.
	e.resolver = NewResolver(nil)
	e.resolver.SetRaceLogCallback(e.raceLogCallback)
	e.resolver.SetBootstrapLogCallback(e.bootstrapLogCallback)
	if e.dnsConfig != nil {
		e.resolver.UpdateBootstrap(e.dnsConfig.Bootstrap)
		if err := e.resolver.ConfigureProviders(e.dnsConfig.Mode, e.dnsConfig.Providers); err != nil {
			logf("StartStandalone: DNS snapshot rejected: %v", err)
		}
	} else {
		e.resolver.Configure(ParseProtocol(e.protocol), e.primaryDNS, e.fallbackDNS, e.dohURL)
	}
	e.mu.Unlock()

	// Shutdown old servers outside the lock
	if oldUdp != nil {
		oldUdp.Shutdown()
	}
	if oldTcp != nil {
		oldTcp.Shutdown()
	}
	if oldUdp6 != nil {
		oldUdp6.Shutdown()
	}
	if oldTcp6 != nil {
		oldTcp6.Shutdown()
	}
	if oldResolver != nil {
		oldResolver.Shutdown()
	}

	// Bind strictly to IPv4 AND IPv6 loopback separately for maximum security and proxy accuracy
	addr4 := fmt.Sprintf("127.0.0.1:%d", port)
	addr6 := fmt.Sprintf("[::1]:%d", port)

	udpServer := &dns.Server{Addr: addr4, Net: "udp", Handler: dns.HandlerFunc(e.ServeDNS)}
	tcpServer := &dns.Server{Addr: addr4, Net: "tcp", Handler: dns.HandlerFunc(e.ServeDNS)}
	
	udpServer6 := &dns.Server{Addr: addr6, Net: "udp6", Handler: dns.HandlerFunc(e.ServeDNS)}
	tcpServer6 := &dns.Server{Addr: addr6, Net: "tcp6", Handler: dns.HandlerFunc(e.ServeDNS)}

	e.mu.Lock()
	e.standaloneUdp = udpServer
	e.standaloneTcp = tcpServer
	e.standaloneUdp6 = udpServer6
	e.standaloneTcp6 = tcpServer6
	e.mu.Unlock()

	errChan := make(chan error, 4)

	go func() {
		if err := udpServer.ListenAndServe(); err != nil {
			logf("Standalone UDP IPv4 stopped: %v", err)
			errChan <- err
		}
	}()
	go func() {
		if err := tcpServer.ListenAndServe(); err != nil {
			logf("Standalone TCP IPv4 stopped: %v", err)
			errChan <- err
		}
	}()
	go func() {
		if err := udpServer6.ListenAndServe(); err != nil {
			logf("Standalone UDP IPv6 stopped: %v", err)
			// IPv6 might fail on v4-only kernels, ignore to prevent crashing the whole engine
		}
	}()
	go func() {
		if err := tcpServer6.ListenAndServe(); err != nil {
			logf("Standalone TCP IPv6 stopped: %v", err)
		}
	}()

	// Give servers a moment to bind
	time.Sleep(100 * time.Millisecond)

	// Check if IPv4 servers failed to start (critical error)
	select {
	case err := <-errChan:
		return fmt.Errorf("IPv4 Server failed to start: %v", err)
	default:
	}

	logf("Engine started in STANDALONE mode on %s and %s", addr4, addr6)
	return nil
}
