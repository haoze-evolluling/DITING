// Package tunnel provides standalone rewrite and lookup helpers.
package tunnel

import (
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/miekg/dns"
)

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
				if resolvedIP == "" {
					resolvedIP = record.A.String()
				}
			}
		case *dns.AAAA:
			if qtype == dns.TypeAAAA {
				response.Answer = append(response.Answer, record)
				if resolvedIP == "" {
					resolvedIP = record.AAAA.String()
				}
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
