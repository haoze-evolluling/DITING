package core

import (
	"context"
	"fmt"
	"net"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func startMockDNSServer(t *testing.T, handler dns.HandlerFunc) (*dns.Server, string) {
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen mock udp packet failed: %v", err)
	}
	server := &dns.Server{
		PacketConn: pc,
		Handler:    handler,
	}
	go func() {
		_ = server.ActivateAndServe()
	}()
	return server, pc.LocalAddr().String()
}

func TestBootstrapIPHealth(t *testing.T) {
	h := newBootstrapHealth()
	now := time.Now()
	server := BootstrapServer{ID: "bs1", Name: "Server 1", Address: "1.1.1.1:53"}

	score := h.GetScore(server, now)
	if score.weight != 1.0 {
		t.Fatalf("expected initial weight 1.0, got %f", score.weight)
	}

	for i := 0; i < 5; i++ {
		h.RecordResult(true, 10, now)
	}
	fastScore := h.GetScore(server, now)
	if fastScore.weight <= 1.0 {
		t.Fatalf("expected weight > 1.0 for fast responses, got %f", fastScore.weight)
	}

	// 连续 3 次失败触发冷却
	h.RecordResult(false, 3000, now)
	h.RecordResult(false, 3000, now)
	h.RecordResult(false, 3000, now)

	failScore := h.GetScore(server, now)
	if !failScore.coolingDown {
		t.Fatalf("expected coolingDown to be true after 3 consecutive failures")
	}
	if failScore.weight >= 0.5 {
		t.Fatalf("expected penalty weight < 0.5 during cooldown, got %f", failScore.weight)
	}

	// 衰减逻辑测试
	future := now.Add(2 * time.Hour)
	decayedScore := h.GetScore(server, future)
	if decayedScore.sampleCount >= failScore.sampleCount {
		t.Fatalf("expected decayed sample count to decrease")
	}
}

func TestBootstrapPlanDistribution(t *testing.T) {
	br := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "fast", Name: "Fast Server", Address: "1.1.1.1:53", Weight: 1.0},
			{ID: "slow", Name: "Slow Server", Address: "2.2.2.2:53", Weight: 1.0},
		},
	})

	now := time.Now()
	fastH := br.getOrCreateHealth("fast")
	for i := 0; i < 10; i++ {
		fastH.RecordResult(true, 15, now)
	}

	slowH := br.getOrCreateHealth("slow")
	for i := 0; i < 10; i++ {
		slowH.RecordResult(true, 900, now)
	}

	fastCount := 0
	slowCount := 0
	for i := 0; i < 500; i++ {
		plan := br.choosePlan(br.servers, now)
		if plan.primary.ID == "fast" {
			fastCount++
		} else if plan.primary.ID == "slow" {
			slowCount++
		}
	}

	if fastCount <= slowCount {
		t.Fatalf("expected fast server to be chosen more than slow server (fast: %d, slow: %d)", fastCount, slowCount)
	}
}

func TestBootstrapResolveHost(t *testing.T) {
	// IP 直接返回
	br := NewBootstrapResolver(BootstrapConfig{Enabled: true})
	res, err := br.ResolveHost(context.Background(), "1.2.3.4")
	if err != nil || res != "1.2.3.4" {
		t.Fatalf("expected direct IP return, got: %s, err: %v", res, err)
	}

	// 空主机名返回错误
	_, err = br.ResolveHost(context.Background(), "")
	if err == nil {
		t.Fatalf("expected error on empty host")
	}

	// 未启用返回原始 host
	brDisabled := NewBootstrapResolver(BootstrapConfig{Enabled: false})
	resDisabled, err := brDisabled.ResolveHost(context.Background(), "dns.alidns.com")
	if err != nil || resDisabled != "dns.alidns.com" {
		t.Fatalf("expected host returned as is when disabled, got %s", resDisabled)
	}

	// 启动 mock 服务器 1 (返回 SERVFAIL)
	srv1, addr1 := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		m.Rcode = dns.RcodeServerFailure
		_ = w.WriteMsg(m)
	})
	defer srv1.Shutdown()

	// 启动 mock 服务器 2 (正常应答 A 记录)
	srv2, addr2 := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 223.5.5.5", r.Question[0].Name))
		m.Answer = append(m.Answer, rr)
		_ = w.WriteMsg(m)
	})
	defer srv2.Shutdown()

	brLive := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "srv1", Name: "Server 1", Address: addr1},
			{ID: "srv2", Name: "Server 2", Address: addr2},
		},
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	resolved, err := brLive.ResolveHost(ctx, "dns.alidns.com")
	if err != nil {
		t.Fatalf("expected resolve via srv2 fallback, got error: %v", err)
	}
	if resolved != "223.5.5.5" {
		t.Fatalf("expected resolved IP 223.5.5.5, got %s", resolved)
	}

	// 再次查询走缓存
	cached, err := brLive.ResolveHost(ctx, "dns.alidns.com")
	if err != nil || cached != "223.5.5.5" {
		t.Fatalf("expected cached IP 223.5.5.5, got %s", cached)
	}

	// ResetStats 清空缓存与统计
	brLive.ResetStats()
	if _, ok := brLive.getCached("dns.alidns.com"); ok {
		t.Fatalf("expected cache cleared after ResetStats")
	}
}

func TestBootstrapResolveAAAA(t *testing.T) {
	srv, addr := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		if len(r.Question) > 0 && r.Question[0].Qtype == dns.TypeAAAA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN AAAA 2400:3200::1", r.Question[0].Name))
			m.Answer = append(m.Answer, rr)
		}
		_ = w.WriteMsg(m)
	})
	defer srv.Shutdown()

	br := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "ipv6-srv", Name: "IPv6 Server", Address: addr},
		},
	})

	ip, err := br.ResolveHost(context.Background(), "ipv6.example.com")
	if err != nil {
		t.Fatalf("expected successful resolution of AAAA record: %v", err)
	}
	if ip != "2400:3200::1" {
		t.Fatalf("expected IPv6 address 2400:3200::1, got %s", ip)
	}
}

func TestBootstrap_CNAMEChaining(t *testing.T) {
	srv, addr := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		if len(r.Question) > 0 {
			q := r.Question[0]
			if q.Name == "cname.example.com." && q.Qtype == dns.TypeA {
				rr, _ := dns.NewRR("cname.example.com. 300 IN CNAME target.example.com.")
				m.Answer = append(m.Answer, rr)
			} else if q.Name == "target.example.com." && q.Qtype == dns.TypeA {
				rr, _ := dns.NewRR("target.example.com. 300 IN A 1.2.3.4")
				m.Answer = append(m.Answer, rr)
			}
		}
		_ = w.WriteMsg(m)
	})
	defer srv.Shutdown()

	br := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "cname-srv", Name: "CNAME Server", Address: addr},
		},
	})

	ip, err := br.ResolveHost(context.Background(), "cname.example.com")
	if err != nil {
		t.Fatalf("expected successful resolution of CNAME chain: %v", err)
	}
	if ip != "1.2.3.4" {
		t.Fatalf("expected resolved IP 1.2.3.4, got %s", ip)
	}
}

func TestBootstrap_TruncatedFallbackTCP(t *testing.T) {
	var tcpListener net.Listener
	var udpConn net.PacketConn
	var err error
	var addr string

	var discardedUDP []net.PacketConn
	defer func() {
		for _, c := range discardedUDP {
			_ = c.Close()
		}
	}()

	for attempt := 0; attempt < 50; attempt++ {
		udpConn, err = net.ListenPacket("udp", "127.0.0.1:0")
		if err != nil {
			continue
		}
		addr = udpConn.LocalAddr().String()
		tcpListener, err = net.Listen("tcp", addr)
		if err == nil {
			break
		}
		discardedUDP = append(discardedUDP, udpConn)
		udpConn = nil
	}
	if udpConn == nil || tcpListener == nil {
		t.Fatalf("listen mock dual server failed: %v", err)
	}

	udpSrv := &dns.Server{
		PacketConn: udpConn,
		Handler: dns.HandlerFunc(func(w dns.ResponseWriter, r *dns.Msg) {
			m := new(dns.Msg)
			m.SetReply(r)
			m.Truncated = true
			_ = w.WriteMsg(m)
		}),
	}
	tcpSrv := &dns.Server{
		Listener: tcpListener,
		Handler: dns.HandlerFunc(func(w dns.ResponseWriter, r *dns.Msg) {
			m := new(dns.Msg)
			m.SetReply(r)
			if len(r.Question) > 0 && r.Question[0].Qtype == dns.TypeA {
				rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 9.8.7.6", r.Question[0].Name))
				m.Answer = append(m.Answer, rr)
			}
			_ = w.WriteMsg(m)
		}),
	}

	go func() { _ = udpSrv.ActivateAndServe() }()
	go func() { _ = tcpSrv.ActivateAndServe() }()
	defer func() {
		_ = udpSrv.Shutdown()
		_ = tcpSrv.Shutdown()
	}()

	br := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "tc-srv", Name: "TC Server", Address: addr},
		},
	})

	ip, err := br.ResolveHost(context.Background(), "truncated.example.com")
	if err != nil {
		t.Fatalf("expected successful resolution via TCP fallback: %v", err)
	}
	if ip != "9.8.7.6" {
		t.Fatalf("expected resolved IP 9.8.7.6, got %s", ip)
	}
}
