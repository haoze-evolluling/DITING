package ipc

import (
	"context"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
)

func TestIPC_ConfigureBootstrap(t *testing.T) {
	mock := &mockController{}
	server := NewServer("127.0.0.1:0", "test-token", mock)
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start: %v", err)
	}
	defer func() { _ = server.Shutdown(context.Background()) }()

	client := NewClient(server.Addr(), "test-token")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// 1. 测试独立 ConfigureBootstrap 接口
	enabled := true
	bsReq := ConfigureBootstrapRequest{
		Enabled: &enabled,
		Servers: []core.BootstrapServer{
			{ID: "bs-ali", Name: "AliDNS", Address: "223.5.5.5:53"},
			{ID: "bs-dnspod", Name: "DNSPod", Address: "119.29.29.29:53"},
		},
	}
	if err := client.ConfigureBootstrap(ctx, bsReq); err != nil {
		t.Fatalf("ConfigureBootstrap failed: %v", err)
	}

	// 2. 测试通过 ConfigureUpstream 携带 Bootstrap
	upReq := ConfigureUpstreamRequest{
		Mode: "PRIMARY_BACKUP",
		Bootstrap: &core.BootstrapConfig{
			Enabled: true,
			Servers: []core.BootstrapServer{
				{ID: "bs-cf", Name: "Cloudflare", Address: "1.1.1.1:53"},
			},
		},
	}
	if err := client.ConfigureUpstream(ctx, upReq); err != nil {
		t.Fatalf("ConfigureUpstream with Bootstrap failed: %v", err)
	}

	// 3. 测试未授权访问 /api/v1/bootstrap/configure
	unauthClient := NewClient(server.Addr(), "invalid-token")
	if err := unauthClient.ConfigureBootstrap(ctx, bsReq); err == nil {
		t.Fatalf("expected unauthorized error for ConfigureBootstrap, got nil")
	}
}
