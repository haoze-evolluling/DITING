package core

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/miekg/dns"
)

func queryBootstrapDNS(ctx context.Context, serverAddr, host string) (string, error) {
	return queryBootstrapDNSRecursive(ctx, serverAddr, host, 0)
}

func queryBootstrapDNSRecursive(ctx context.Context, serverAddr, host string, depth int) (string, error) {
	if depth > 3 {
		return "", fmt.Errorf("bootstrap cname loop limit exceeded for %s", host)
	}

	addr := serverAddr
	if _, _, err := net.SplitHostPort(addr); err != nil {
		addr = net.JoinHostPort(strings.Trim(addr, "[]"), "53")
	}

	client := &dns.Client{
		Net:     "udp",
		Timeout: 1500 * time.Millisecond,
		UDPSize: dns.MaxMsgSize,
	}

	// 优先查询 A 记录
	msg := new(dns.Msg)
	msg.SetQuestion(dns.Fqdn(host), dns.TypeA)
	msg.RecursionDesired = true
	msg.Id = dns.Id()

	resp, _, err := client.ExchangeContext(ctx, msg, addr)
	if err == nil && resp != nil && resp.Truncated {
		tcpClient := &dns.Client{Net: "tcp", Timeout: 1500 * time.Millisecond}
		resp, _, err = tcpClient.ExchangeContext(ctx, msg, addr)
	}

	var cnameTarget string
	if err == nil && resp != nil {
		for _, rr := range resp.Answer {
			if a, ok := rr.(*dns.A); ok && a.A != nil {
				return a.A.String(), nil
			}
			if cn, ok := rr.(*dns.CNAME); ok && cn.Target != "" && cnameTarget == "" {
				cnameTarget = strings.TrimSuffix(cn.Target, ".")
			}
		}
	}

	// A 记录未返回则尝试 AAAA 记录
	msgAAAA := new(dns.Msg)
	msgAAAA.SetQuestion(dns.Fqdn(host), dns.TypeAAAA)
	msgAAAA.RecursionDesired = true
	msgAAAA.Id = dns.Id()

	respAAAA, _, errAAAA := client.ExchangeContext(ctx, msgAAAA, addr)
	if errAAAA == nil && respAAAA != nil && respAAAA.Truncated {
		tcpClient := &dns.Client{Net: "tcp", Timeout: 3 * time.Second}
		respAAAA, _, errAAAA = tcpClient.ExchangeContext(ctx, msgAAAA, addr)
	}

	if errAAAA == nil && respAAAA != nil {
		for _, rr := range respAAAA.Answer {
			if aaaa, ok := rr.(*dns.AAAA); ok && aaaa.AAAA != nil {
				return aaaa.AAAA.String(), nil
			}
			if cn, ok := rr.(*dns.CNAME); ok && cn.Target != "" && cnameTarget == "" {
				cnameTarget = strings.TrimSuffix(cn.Target, ".")
			}
		}
	}

	if cnameTarget != "" && !strings.EqualFold(cnameTarget, host) {
		return queryBootstrapDNSRecursive(ctx, serverAddr, cnameTarget, depth+1)
	}

	if err != nil {
		return "", fmt.Errorf("query bootstrap %s for %s: %w", addr, host, err)
	}
	return "", fmt.Errorf("no A/AAAA record for %s from %s", host, addr)
}
