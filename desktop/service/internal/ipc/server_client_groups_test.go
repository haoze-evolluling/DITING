package ipc

import (
	"context"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

func TestIPCServerAndClient_ClientGroups(t *testing.T) {
	mockCtrl := &mockController{
		clientGroups: &ClientGroupConfigResponse{
			Enabled: true,
			Groups:  []core.ClientGroup{{ID: "kids", Name: "儿童", Enabled: true, Clients: []string{"192.168.1.0/24"}}},
		},
	}
	token := "test-secret-token"
	server := NewServer("127.0.0.1:0", token, mockCtrl)
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() { _ = server.Shutdown(context.Background()) }()

	client := NewClient(server.Addr(), token)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// 1. 读取初始分组配置
	got, err := client.GetClientGroups(ctx)
	if err != nil {
		t.Fatalf("GetClientGroups failed: %v", err)
	}
	if !got.Enabled || len(got.Groups) != 1 || got.Groups[0].ID != "kids" {
		t.Fatalf("unexpected initial groups: %+v", got)
	}

	// 2. 更新分组配置（新增一个组）
	enabled := true
	groups := []core.ClientGroup{
		{ID: "kids", Name: "儿童", Enabled: true, Clients: []string{"192.168.1.0/24"}, RuleListIDs: []string{"list-ads"}},
		{ID: "guest", Name: "访客", Enabled: true, Clients: []string{"192.168.2.0/24"}, BlockMode: core.BlockModeNXDOMAIN},
	}
	if err := client.ConfigureClientGroups(ctx, ConfigureClientGroupsRequest{Enabled: &enabled, Groups: &groups}); err != nil {
		t.Fatalf("ConfigureClientGroups failed: %v", err)
	}

	after, err := client.GetClientGroups(ctx)
	if err != nil {
		t.Fatalf("GetClientGroups after configure failed: %v", err)
	}
	if len(after.Groups) != 2 || after.Groups[1].ID != "guest" {
		t.Fatalf("groups not updated: %+v", after)
	}
	if after.Groups[1].BlockMode != core.BlockModeNXDOMAIN {
		t.Fatalf("BlockMode override not persisted: %+v", after.Groups[1])
	}
}

func TestIPCServer_ClientGroupsMethodNotAllowed(t *testing.T) {
	mockCtrl := &mockController{}
	token := "test-secret-token"
	server := NewServer("127.0.0.1:0", token, mockCtrl)
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() { _ = server.Shutdown(context.Background()) }()

	client := NewClient(server.Addr(), token)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	var resp Response[any]
	// DELETE 不被支持，应返回 405 并 Success=false
	if err := client.doRequest(ctx, "DELETE", "/api/v1/clients/groups", nil, &resp); err != nil {
		t.Fatalf("doRequest 本身不应报错: %v", err)
	}
	if resp.Success || resp.Error == "" {
		t.Fatalf("expected Success=false on 405, got %+v", resp)
	}
}
