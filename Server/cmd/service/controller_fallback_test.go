package main

import (
	"context"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

func newFallbackTestProgram(t *testing.T) *program {
	t.Helper()
	cfg := config.DefaultConfig()
	resolver, err := core.NewResolver(cfg.Upstream)
	if err != nil {
		t.Fatalf("NewResolver failed: %v", err)
	}
	return &program{
		configPath: t.TempDir() + "/config.json",
		cfg:        cfg,
		resolver:   resolver,
	}
}

func intPtr(v int) *int         { return &v }
func boolPtr(v bool) *bool      { return &v }
func rcodesPtr(v ...int) *[]int { return &v }

func TestController_FallbackValidation(t *testing.T) {
	prg := newFallbackTestProgram(t)
	ctx := context.Background()

	// 回退链中的非法协议必须被拒绝，且错误信息标明归属
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		FallbackProviders: []core.ProviderConfig{
			{ID: "fb1", Protocol: core.ProtocolDoH, URL: "http://insecure.example/dns-query"},
		},
	}); err == nil {
		t.Fatal("expected an invalid fallback DoH URL to be rejected")
	}

	// 回退节点 ID 与主链路重复必须被拒绝：
	// 统计指标按 ID 归集，重名会让两条链的健康记录互相污染
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		Providers: []core.ProviderConfig{
			{ID: "shared-id", Protocol: core.ProtocolPlain, Server: "1.1.1.1:53"},
		},
		FallbackProviders: []core.ProviderConfig{
			{ID: "shared-id", Protocol: core.ProtocolPlain, Server: "9.9.9.9:53"},
		},
	}); err == nil {
		t.Fatal("expected a fallback provider ID colliding with the main chain to be rejected")
	}

	// 回退链内部的重复 ID 同样拒绝
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		FallbackProviders: []core.ProviderConfig{
			{ID: "fb-dup", Protocol: core.ProtocolPlain, Server: "9.9.9.9:53"},
			{ID: "fb-dup", Protocol: core.ProtocolPlain, Server: "8.8.8.8:53"},
		},
	}); err == nil {
		t.Fatal("expected duplicate fallback provider IDs to be rejected")
	}
}

func TestController_FallbackLifecycle(t *testing.T) {
	prg := newFallbackTestProgram(t)
	ctx := context.Background()

	// 配置一条回退链
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		FallbackProviders: []core.ProviderConfig{
			{ID: "fb-1", Protocol: core.ProtocolPlain, Server: "9.9.9.9:53"},
			{ID: "fb-2", Protocol: core.ProtocolDoT, Server: "dns.example:853"},
		},
		FallbackTimeoutMs: intPtr(1500),
		FallbackOnRcode:   rcodesPtr(2, 5),
		FallbackOnError:   boolPtr(true),
	}); err != nil {
		t.Fatalf("configure fallback: %v", err)
	}

	got, err := prg.GetUpstreamConfig(ctx)
	if err != nil {
		t.Fatalf("get config: %v", err)
	}
	if len(got.FallbackProviders) != 2 {
		t.Fatalf("expected 2 fallback providers, got %d", len(got.FallbackProviders))
	}
	if got.FallbackProviders[0].ID != "fb-1" {
		t.Fatalf("unexpected fallback order: %+v", got.FallbackProviders)
	}
	if got.FallbackTimeoutMs != 1500 {
		t.Fatalf("timeout = %d, want 1500", got.FallbackTimeoutMs)
	}
	if len(got.FallbackOnRcode) != 2 || got.FallbackOnRcode[0] != 2 {
		t.Fatalf("onRcode = %v", got.FallbackOnRcode)
	}

	// 只调整超时：回退链必须原样保留（nil 字段表示保持现状）
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		FallbackTimeoutMs: intPtr(3000),
	}); err != nil {
		t.Fatalf("update timeout: %v", err)
	}
	got, _ = prg.GetUpstreamConfig(ctx)
	if len(got.FallbackProviders) != 2 {
		t.Fatalf("a timeout-only update must not drop the fallback chain, got %d", len(got.FallbackProviders))
	}
	if got.FallbackTimeoutMs != 3000 {
		t.Fatalf("timeout = %d, want 3000", got.FallbackTimeoutMs)
	}
}

// 取消全部响应码勾选必须被持久化为空集合，而不是静默恢复默认。
func TestController_FallbackEmptyRcodeSetPersists(t *testing.T) {
	prg := newFallbackTestProgram(t)
	ctx := context.Background()

	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		FallbackProviders: []core.ProviderConfig{
			{ID: "fb-1", Protocol: core.ProtocolPlain, Server: "9.9.9.9:53"},
		},
		FallbackOnRcode: rcodesPtr(),
	}); err != nil {
		t.Fatalf("configure: %v", err)
	}

	got, _ := prg.GetUpstreamConfig(ctx)
	if got.FallbackOnRcode == nil {
		t.Fatal("explicit empty rcode set must not degrade to nil (which means 'use defaults')")
	}
	if len(got.FallbackOnRcode) != 0 {
		t.Fatalf("expected an empty set, got %v", got.FallbackOnRcode)
	}
}

// 传入空回退链即关闭该功能，这是唯一的关闭途径。
func TestController_FallbackDisabledByEmptySlice(t *testing.T) {
	prg := newFallbackTestProgram(t)
	ctx := context.Background()

	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		FallbackProviders: []core.ProviderConfig{
			{ID: "fb-1", Protocol: core.ProtocolPlain, Server: "9.9.9.9:53"},
		},
	}); err != nil {
		t.Fatalf("configure: %v", err)
	}
	if got, _ := prg.GetUpstreamConfig(ctx); len(got.FallbackProviders) != 1 {
		t.Fatal("setup failed")
	}

	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		FallbackProviders: []core.ProviderConfig{},
	}); err != nil {
		t.Fatalf("disable: %v", err)
	}
	got, _ := prg.GetUpstreamConfig(ctx)
	if len(got.FallbackProviders) != 0 {
		t.Fatalf("expected the fallback chain to be cleared, got %+v", got.FallbackProviders)
	}
}
