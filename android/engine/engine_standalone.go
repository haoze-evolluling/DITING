// engine_standalone.go implements standalone DNS server capabilities (root and proxy modes),
// allowing the engine to operate without an active Android VPN TUN device.
//
// Core Standalone Mechanisms:
// - Direct socket binding on IPv4 and IPv6 loopback interfaces with iptables REDIRECT support,
//   preserving original client source ports for /proc/net/udp UID and package attribution.
// - Discovery of Designated Resolvers (DDR, RFC 9462) mitigation: returns NXDOMAIN for
//   _dns.resolver.arpa to prevent clients (Android 13+, Chrome) from bypassing local filtering.
// - Priority evaluation: Firewall checks -> CNAME rewrites -> PolicyEngine -> Upstream.
// - lookupIP fallback: provides dedicated, direct public DNS resolution for internal engine
//   components (such as the MITM proxy), bypassing fragile Android system resolver stubs.

package tunnel

import (
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/miekg/dns"
)

func (e *Engine) ServeDNS(w dns.ResponseWriter, r *dns.Msg) {
	e.serveDNS(w, r, "", UIDUnknown)
}

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

	if domain == LocalAssetHost {
		m := new(dns.Msg)
		m.SetReply(r)
		if queryType == dns.TypeA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A %s", r.Question[0].Name, localAssetSynthIP.String()))
			m.Answer = append(m.Answer, rr)
		}
		// AAAA queries fall through: the empty NOERROR reply advertises no
		// IPv6 address for the local asset host.
		_ = w.WriteMsg(m)
		e.totalQueries.Add(1)
		return
	}

	appName := "RootProxy"

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

				if host, portStr, err := net.SplitHostPort(addr.String()); err == nil {
					if p, err2 := fmt.Sscanf(portStr, "%d", &srcPort); p == 1 && err2 == nil {
						if parsed := net.ParseIP(host); parsed != nil {
							srcIP = parsed
						}
					}
				}
			}

			if srcPort > 0 {

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

	if domain == "_dns.resolver.arpa" || strings.HasSuffix(domain, "._dns.resolver.arpa") {
		m := new(dns.Msg)
		m.SetReply(r)
		m.Rcode = dns.RcodeNameError
		_ = w.WriteMsg(m)
		e.totalQueries.Add(1)
		e.blockedQueries.Add(1)
		e.notifyLog(domain, true, queryType, time.Since(startTime).Milliseconds(), appName, "", "ddr_blocked", "", false)
		return
	}

	if e.firewallChecker != nil && appName != "" && appName != "RootProxy" {
		if e.firewallChecker.ShouldBlock(appName) {
			e.standaloneBlock(w, r, "firewall", appName, startTime)
			return
		}
	}

	if queryType == dns.TypeA || queryType == dns.TypeAAAA {
		if ip := e.rewriteIP(domain, queryType == dns.TypeA); ip != nil {
			response := new(dns.Msg)
			response.SetReply(r)
			response.RecursionAvailable = true
			response.Answer = append(response.Answer, rewriteAnswerRecord(r.Question[0], ip))
			_ = w.WriteMsg(response)
			e.totalQueries.Add(1)
			e.notifyLog(domain, false, queryType, time.Since(startTime).Milliseconds(), appName, ip.String(), "rewrite="+ip.String(), "", false)
			return
		}
	}

	if target := e.rewriteCNAME(domain); target != "" {
		if e.standaloneRewrite(w, r, target, appName, startTime) {
			return
		}
	}

	// "启用域名过滤" must gate the whole filtering pipeline, exactly like the
	// full-tunnel path does in handleDNSQuery. Without this guard the standalone
	// server kept evaluating the policy engine while the
	// user had filtering switched off.
	if !e.filterDNS.Load() {
		e.standaloneForward(w, r, appName, startTime, uid)
		return
	}

	if e.policyEngine != nil && e.policyEngine.isActive() && e.policyEngine.hasRules() {
		if blocked, reason := e.policyEngine.evaluate(domain, appName, queryType); blocked {
			e.standaloneBlock(w, r, reason, appName, startTime)
			return
		}
	}

	e.standaloneForward(w, r, appName, startTime, uid)
}

func (e *Engine) standaloneBlock(w dns.ResponseWriter, r *dns.Msg, blockedBy, appName string, startTime time.Time) {
	m := new(dns.Msg)
	m.SetReply(r)

	switch e.effectiveBlockResponseType(r.Question[0].Name) {
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

	resolver := e.currentResolver()
	dnsCache := e.dnsCache
	if resolver == nil {
		dns.HandleFailed(w, r)
		return
	}

	var respRaw []byte
	var resolvedMsg *dns.Msg
	var isCached bool
	if dnsCache != nil && dnsCache.isEnabled() {
		cachedResp, hit, targets, ipList, resolvedIPs, isNegative, staleCandidate := dnsCache.getFast(raw)
		if hit {
			if len(targets) > 0 {
				if chainBlocked, chainReason := e.checkResponseChainTargets(targets, appName, r.Question[0].Qtype); chainBlocked {
					e.standaloneBlock(w, r, chainReason, appName, startTime)
					return
				}
			}
			_, _ = w.Write(cachedResp)
			e.totalQueries.Add(1)
			if !isNegative && len(ipList) > 0 {
				e.rememberResolvedIPList(r.Question[0].Name, ipList)
			}
			// The cached wire bytes are the only DNS answer this flow will see,
			// so the app-allowlist IP grant has to be derived from them here;
			// the upstream path does it from respMsg below.
			e.rememberAppAllowlistWire(uid, cachedResp)
			elapsed := time.Since(startTime).Milliseconds()
			e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, r.Question[0].Qtype, elapsed, appName, resolvedIPs, "", "", true)
			return
		}

		if staleCandidate != nil && dnsCache.isStaleFallbackEnabled() {
			staleResp := dnsCache.buildStaleResponse(raw, staleCandidate)
			if staleResp != nil {
				if len(staleCandidate.chainTargets) > 0 {
					if chainBlocked, chainReason := e.checkResponseChainTargets(staleCandidate.chainTargets, appName, r.Question[0].Qtype); chainBlocked {
						e.standaloneBlock(w, r, chainReason, appName, startTime)
						return
					}
				}
				_, _ = w.Write(staleResp)
				e.totalQueries.Add(1)
				if !staleCandidate.isNegative && len(staleCandidate.ipList) > 0 {
					e.rememberResolvedIPList(r.Question[0].Name, staleCandidate.ipList)
				}
				// Same as the fresh-hit branch: the stale wire response is the
				// only answer handed to the client, so grant from it as well.
				e.rememberAppAllowlistWire(uid, staleResp)
				elapsed := time.Since(startTime).Milliseconds()
				e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, r.Question[0].Qtype, elapsed, appName, staleCandidate.resolvedIPs, "", "", true)

				// One background refresh per stale entry: a burst of stale hits
				// would otherwise spawn a goroutine and copy the query for each.
				if staleCandidate.refreshing.CompareAndSwap(false, true) {
					go func() {
						defer staleCandidate.refreshing.Store(false)
						_, _, _ = dnsCache.singleFlight(raw, func() ([]byte, error) {
							return resolver.Resolve(raw)
						})
					}()
				}
				return
			}
		}

		respRaw, resolvedMsg, isCached, err = dnsCache.singleFlightMsg(raw, func() ([]byte, *dns.Msg, error) {
			return resolver.ResolveMsg(raw)
		})
	} else {
		respRaw, resolvedMsg, err = resolver.ResolveMsg(raw)
	}


	if err != nil {
		logf("DNS resolve failed standalone %s: %v", r.Question[0].Name, err)
		dns.HandleFailed(w, r)
		e.totalQueries.Add(1)
		elapsed := time.Since(startTime).Milliseconds()
		e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, r.Question[0].Qtype, elapsed, appName, "", "", err.Error(), false)
		return
	}

	// resolvedMsg is owned by this call (see singleFlightMsg), so mutating its
	// Id below is safe; otherwise unpack a private copy.
	respMsg := resolvedMsg
	if respMsg == nil {
		respMsg = new(dns.Msg)
	}
	if err := unpackIfNeeded(respMsg, resolvedMsg != nil, respRaw); err != nil {
		dns.HandleFailed(w, r)
		e.totalQueries.Add(1)
		e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, r.Question[0].Qtype, time.Since(startTime).Milliseconds(), appName, "", "", err.Error(), false)
		return
	}

	if isUpstreamBlockedMsg(respMsg) {
		e.totalQueries.Add(1)
		e.blockedQueries.Add(1)
		elapsed := time.Since(startTime).Milliseconds()
		e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), true, r.Question[0].Qtype, elapsed, appName, "", "upstream_dns", "", false)
	} else {
		if chainBlocked, chainReason := e.checkResponseChain(respMsg, appName); chainBlocked {
			e.standaloneBlock(w, r, chainReason, appName, startTime)
			return
		}
		e.totalQueries.Add(1)
		elapsed := time.Since(startTime).Milliseconds()
		e.notifyLog(strings.TrimSuffix(r.Question[0].Name, "."), false, r.Question[0].Qtype, elapsed, appName, resolvedAddressesMsg(respMsg), "", "", isCached)
		e.rememberResolvedIPs(r.Question[0].Name, respMsg)
	}

	respMsg.Id = r.Id
	e.rememberAppAllowlistResponse(uid, respMsg)
	_ = w.WriteMsg(respMsg)
}

func (e *Engine) StartStandalone(port int) error {
	e.mu.Lock()

	var oldUdp, oldTcp, oldUdp6, oldTcp6 *dns.Server
	var oldResolver *Resolver

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
		e.setResolverLocked(nil)
		e.running = false
	}

	e.running = true
	e.totalQueries.Store(0)
	e.blockedQueries.Store(0)

	e.setResolverLocked(NewResolver(nil))
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

	addr4 := fmt.Sprintf("0.0.0.0:%d", port)
	addr6 := fmt.Sprintf("[::]:%d", port)

	udpConn4, err := net.ListenPacket("udp4", addr4)
	if err != nil {
		return fmt.Errorf("IPv4 UDP Server failed to bind %s: %w", addr4, err)
	}
	tcpListener4, err := net.Listen("tcp4", addr4)
	if err != nil {
		_ = udpConn4.Close()
		return fmt.Errorf("IPv4 TCP Server failed to bind %s: %w", addr4, err)
	}

	udpServer := &dns.Server{PacketConn: udpConn4, Handler: dns.HandlerFunc(e.ServeDNS)}
	tcpServer := &dns.Server{Listener: tcpListener4, Handler: dns.HandlerFunc(e.ServeDNS)}

	var udpServer6, tcpServer6 *dns.Server
	if udpConn6, err := net.ListenPacket("udp6", addr6); err == nil {
		udpServer6 = &dns.Server{PacketConn: udpConn6, Handler: dns.HandlerFunc(e.ServeDNS)}
	} else {
		logf("Standalone UDP IPv6 not available: %v", err)
	}
	if tcpListener6, err := net.Listen("tcp6", addr6); err == nil {
		tcpServer6 = &dns.Server{Listener: tcpListener6, Handler: dns.HandlerFunc(e.ServeDNS)}
	} else {
		logf("Standalone TCP IPv6 not available: %v", err)
	}

	e.mu.Lock()
	e.standaloneUdp = udpServer
	e.standaloneTcp = tcpServer
	e.standaloneUdp6 = udpServer6
	e.standaloneTcp6 = tcpServer6
	e.mu.Unlock()

	go func() {
		if err := udpServer.ActivateAndServe(); err != nil {
			logf("Standalone UDP IPv4 stopped: %v", err)
		}
	}()
	go func() {
		if err := tcpServer.ActivateAndServe(); err != nil {
			logf("Standalone TCP IPv4 stopped: %v", err)
		}
	}()
	if udpServer6 != nil {
		go func() {
			if err := udpServer6.ActivateAndServe(); err != nil {
				logf("Standalone UDP IPv6 stopped: %v", err)
			}
		}()
	}
	if tcpServer6 != nil {
		go func() {
			if err := tcpServer6.ActivateAndServe(); err != nil {
				logf("Standalone TCP IPv6 stopped: %v", err)
			}
		}()
	}

	logf("Engine started in STANDALONE mode on %s and %s", addr4, addr6)
	return nil
}

func (e *Engine) StopStandalone() {
	e.mu.Lock()
	e.running = false
	oldUdp := e.standaloneUdp
	e.standaloneUdp = nil
	oldTcp := e.standaloneTcp
	e.standaloneTcp = nil
	oldUdp6 := e.standaloneUdp6
	e.standaloneUdp6 = nil
	oldTcp6 := e.standaloneTcp6
	e.standaloneTcp6 = nil
	oldResolver := e.resolver
	e.setResolverLocked(nil)
	e.mu.Unlock()

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
	logf("Engine standalone server stopped")
}

func unpackIfNeeded(msg *dns.Msg, alreadyUnpacked bool, raw []byte) error {
	if alreadyUnpacked {
		return nil
	}
	return msg.Unpack(raw)
}
