package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

func TestClientMiddleware_SetClientName(t *testing.T) {
	clientResolver := core.NewClientResolver(core.ClientConfig{
		Enabled: true,
		Aliases: []core.ClientAlias{
			{IP: "192.168.1.55", Name: "Developer-Mac"},
		},
	})

	mw := NewClientMiddleware(clientResolver)

	// 1. 本地回环
	req := new(dns.Msg)
	req.SetQuestion("example.com.", dns.TypeA)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 53535}, "udp")

	called := false
	err := mw(dctx, func() error {
		called = true
		return nil
	})
	if err != nil || !called {
		t.Fatalf("expected next to be called, err: %v", err)
	}
	if dctx.ClientName != "localhost" {
		t.Fatalf("expected ClientName localhost, got %s", dctx.ClientName)
	}

	// 2. 静态别名
	dctx2 := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("192.168.1.55"), Port: 53535}, "udp")
	_ = mw(dctx2, func() error { return nil })
	if dctx2.ClientName != "Developer-Mac" {
		t.Fatalf("expected ClientName Developer-Mac, got %s", dctx2.ClientName)
	}
}
