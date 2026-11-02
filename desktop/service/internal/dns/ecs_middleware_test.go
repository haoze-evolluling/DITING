package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

func TestECSMiddleware_StripAndCustom(t *testing.T) {
	// 1. 测试 StripECS
	mgr := NewECSManager(core.ECSConfig{
		Enabled:      true,
		StripECS:     true,
		CustomSubnet: "",
	})
	mw := NewECSMiddleware(mgr)

	req := new(dns.Msg)
	req.SetQuestion("example.com.", dns.TypeA)
	// 附加原始客户端子网
	_ = SetECS(req, "192.0.2.0/24")

	if opt := GetEdns0Option[*dns.EDNS0_SUBNET](req); opt == nil {
		t.Fatalf("expected EDNS0_SUBNET before middleware")
	}

	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("192.0.2.1"), Port: 1234}, "udp")
	called := false
	err := mw(dctx, func() error {
		called = true
		return nil
	})
	if err != nil || !called {
		t.Fatalf("expected next to run")
	}

	if opt := GetEdns0Option[*dns.EDNS0_SUBNET](req); opt != nil {
		t.Fatalf("expected EDNS0_SUBNET to be stripped, but found: %v", opt)
	}

	// 2. 测试 CustomSubnet 注入
	mgr.Configure(core.ECSConfig{
		Enabled:      true,
		StripECS:     false,
		CustomSubnet: "203.0.113.0/24",
	})

	req2 := new(dns.Msg)
	req2.SetQuestion("example.com.", dns.TypeA)
	dctx2 := NewDNSContext(context.Background(), req2, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 1234}, "udp")

	_ = mw(dctx2, func() error { return nil })

	opt := GetEdns0Option[*dns.EDNS0_SUBNET](req2)
	if opt == nil {
		t.Fatalf("expected EDNS0_SUBNET to be injected")
	}
	if opt.Family != 1 || opt.SourceNetmask != 24 || !opt.Address.Equal(net.ParseIP("203.0.113.0")) {
		t.Fatalf("unexpected injected subnet: %v", opt)
	}

	// 3. 测试 StripECS 为 true 时配置 CustomSubnet，先剥离再注入设定子网
	mgr.Configure(core.ECSConfig{
		Enabled:      true,
		StripECS:     true,
		CustomSubnet: "198.51.100.0/24",
	})
	req3 := new(dns.Msg)
	req3.SetQuestion("example.com.", dns.TypeA)
	_ = SetECS(req3, "192.0.2.0/24") // 传入原生子网
	dctx3 := NewDNSContext(context.Background(), req3, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 1234}, "udp")

	_ = mw(dctx3, func() error { return nil })

	opt3 := GetEdns0Option[*dns.EDNS0_SUBNET](req3)
	if opt3 == nil {
		t.Fatalf("expected EDNS0_SUBNET to be replaced with custom subnet")
	}
	if !opt3.Address.Equal(net.ParseIP("198.51.100.0")) {
		t.Fatalf("expected 198.51.100.0, got %v", opt3.Address)
	}
}
