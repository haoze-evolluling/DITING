package ipc

import (
	"context"
	"testing"
)

func TestIPC_LANEndpoints(t *testing.T) {
	mockCtrl := &mockController{}
	token := "lan-token-secret"
	server := NewServer("127.0.0.1:0", token, mockCtrl)
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() { _ = server.Shutdown(context.Background()) }()

	client := NewClient(server.Addr(), token)
	ctx := context.Background()

	// 1. 测试获取局域网状态
	lanStatus, err := client.GetLANStatus(ctx)
	if err != nil {
		t.Fatalf("GetLANStatus failed: %v", err)
	}
	if !lanStatus.AllowLAN || len(lanStatus.LANAddresses) == 0 {
		t.Errorf("unexpected LAN status: %+v", lanStatus)
	}

	// 2. 测试配置局域网服务
	if err := client.ConfigureLAN(ctx, ConfigureLANRequest{AllowLAN: true, ConfigureFirewall: true}); err != nil {
		t.Fatalf("ConfigureLAN failed: %v", err)
	}

	// 3. 测试防火墙控制接口
	if err := client.ConfigureFirewall(ctx, true); err != nil {
		t.Fatalf("ConfigureFirewall failed: %v", err)
	}
}
