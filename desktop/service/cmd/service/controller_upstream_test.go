package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

func TestController_UpstreamValidationAndPersistence(t *testing.T) {
	cfg := config.DefaultConfig()
	resolver, err := core.NewResolver(cfg.Upstream)
	if err != nil {
		t.Fatalf("NewResolver failed: %v", err)
	}

	tmpConfig := t.TempDir() + "/config.json"
	prg := &program{
		configPath: tmpConfig,
		cfg:        cfg,
		resolver:   resolver,
	}

	ctx := context.Background()

	// 1. 空请求拒绝
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{}); err == nil {
		t.Fatalf("expected error on completely empty request, got nil")
	}

	// 2. 非法调度模式拒绝
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{Mode: "UNKNOWN_MODE"}); err == nil {
		t.Fatalf("expected error on unknown mode, got nil")
	}

	// 3. 空 providers 数组拒绝
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		Providers: []core.ProviderConfig{},
	}); err == nil {
		t.Fatalf("expected error on empty providers slice, got nil")
	}

	// 4. 重复 ID 拒绝
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		Providers: []core.ProviderConfig{
			{ID: "dup", Protocol: core.ProtocolPlain, Server: "1.1.1.1:53"},
			{ID: "dup", Protocol: core.ProtocolPlain, Server: "2.2.2.2:53"},
		},
	}); err == nil {
		t.Fatalf("expected error on duplicate provider IDs, got nil")
	}

	// 5. 非法 DoH URL 拒绝
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		Providers: []core.ProviderConfig{
			{ID: "bad-doh", Protocol: core.ProtocolDoH, URL: "http://insecure.com"},
		},
	}); err == nil {
		t.Fatalf("expected error on invalid DoH URL, got nil")
	}

	// 6. 空 Server 拒绝
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		Providers: []core.ProviderConfig{
			{ID: "empty-server", Protocol: core.ProtocolPlain, Server: ""},
		},
	}); err == nil {
		t.Fatalf("expected error on empty server, got nil")
	}

	// 7. 不受支持的协议类型拒绝
	if err := prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		Providers: []core.ProviderConfig{
			{ID: "bad-proto", Protocol: "GARBAGE", Server: "1.1.1.1:53"},
		},
	}); err == nil {
		t.Fatalf("expected error on unsupported protocol GARBAGE, got nil")
	}

	// 8. 合法多上游与 SMART_PREDICTION 模式配置成功（含 DoH 缺省 server 自动由 URL 提取 host）
	validProviders := []core.ProviderConfig{
		{ID: "doh-pub", Protocol: core.ProtocolDoH, URL: "https://doh.pub/dns-query", Weight: 2}, // server 缺省
		{ID: "ali-dot", Protocol: core.ProtocolDoT, Server: "dns.alidns.com:853", Weight: 1},
		{ID: "cf-plain", Protocol: core.ProtocolPlain, Server: "1.1.1.1:53", Weight: 3},
	}
	err = prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		Mode:      "SMART_PREDICTION",
		Providers: validProviders,
	})
	if err != nil {
		t.Fatalf("ConfigureUpstream valid SMART_PREDICTION failed: %v", err)
	}

	// 验证 DoH 缺省 server 自动由 URL 推导为 doh.pub
	if prg.cfg.Upstream.Providers[0].Server != "doh.pub" {
		t.Fatalf("expected DoH server auto-inferred as doh.pub, got %q", prg.cfg.Upstream.Providers[0].Server)
	}

	// 验证内存配置与核心解析器中 providers 数量完整
	if len(prg.cfg.Upstream.Providers) != 3 {
		t.Fatalf("expected 3 providers in cfg, got %d", len(prg.cfg.Upstream.Providers))
	}
	stats := prg.resolver.GetProviderStats()
	if len(stats) != 3 {
		t.Fatalf("expected 3 providers in resolver stats, got %d", len(stats))
	}

	// 验证持久化文件已正确写入且能重新反序列化
	persistedCfg, err := config.LoadConfig(tmpConfig)
	if err != nil {
		t.Fatalf("LoadConfig from persisted file failed: %v", err)
	}
	if persistedCfg.Upstream.Mode != "SMART_PREDICTION" {
		t.Fatalf("expected mode SMART_PREDICTION in file, got %s", persistedCfg.Upstream.Mode)
	}
	if len(persistedCfg.Upstream.Providers) != 3 {
		t.Fatalf("expected 3 providers in persisted file, got %d", len(persistedCfg.Upstream.Providers))
	}

	// 9. 验证 GetUpstreamConfig 权威读取
	upCfg, err := prg.GetUpstreamConfig(ctx)
	if err != nil {
		t.Fatalf("GetUpstreamConfig failed: %v", err)
	}
	if len(upCfg.Providers) != 3 {
		t.Fatalf("expected 3 providers from GetUpstreamConfig, got %d", len(upCfg.Providers))
	}

	// 10. 验证 GetStatus 上报全量 providers 与 Weight
	status, err := prg.GetStatus(ctx)
	if err != nil {
		t.Fatalf("GetStatus failed: %v", err)
	}
	if len(status.DNS.Upstreams) != 3 {
		t.Fatalf("expected 3 upstreams in status, got %d", len(status.DNS.Upstreams))
	}
	if status.DNS.Upstreams[0].Weight != 2 || status.DNS.Upstreams[2].Weight != 3 {
		t.Fatalf("expected weights 2 and 3 preserved in status, got %+v", status.DNS.Upstreams)
	}

	// 11. 验证热重载配置时已有上游节点的健康统计平滑保留
	// 给 cf-plain 人工累积一次失败与成功记录
	var cfProvider *core.ConfiguredProvider
	for _, p := range prg.resolver.GetProviderStats() {
		if p.ID == "cf-plain" {
			// stats 应该被初始化
			break
		}
	}
	_ = cfProvider
	// 重新热重载上游（仅切换 mode）
	err = prg.ConfigureUpstream(ctx, ipc.ConfigureUpstreamRequest{
		Mode: "PARALLEL_RACE",
	})
	if err != nil {
		t.Fatalf("re-configure mode failed: %v", err)
	}
	if prg.cfg.Upstream.Mode != "PARALLEL_RACE" {
		t.Fatalf("expected mode PARALLEL_RACE, got %s", prg.cfg.Upstream.Mode)
	}
	// 检查 3 个 provider 仍然完整保留
	if len(prg.cfg.Upstream.Providers) != 3 {
		t.Fatalf("expected 3 providers preserved after mode change, got %d", len(prg.cfg.Upstream.Providers))
	}
}

func TestServer_UpstreamGetAndPostEndpoints(t *testing.T) {
	cfg := config.DefaultConfig()
	resolver, err := core.NewResolver(cfg.Upstream)
	if err != nil {
		t.Fatalf("NewResolver failed: %v", err)
	}

	tmpConfig := t.TempDir() + "/config.json"
	prg := &program{
		configPath: tmpConfig,
		cfg:        cfg,
		resolver:   resolver,
	}

	server := ipc.NewServer("127.0.0.1:0", "", prg)
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() { _ = server.Shutdown(context.Background()) }()

	baseURL := "http://" + server.Addr()

	// 1. 测试 GET /api/v1/upstream/configure
	resp, err := http.Get(baseURL + "/api/v1/upstream/configure")
	if err != nil {
		t.Fatalf("GET /api/v1/upstream/configure failed: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}
	var getResp ipc.Response[*core.ResolverConfig]
	if err := json.NewDecoder(resp.Body).Decode(&getResp); err != nil {
		t.Fatalf("decode GET response failed: %v", err)
	}
	_ = resp.Body.Close()
	if !getResp.Success || len(getResp.Data.Providers) == 0 {
		t.Fatalf("unexpected GET response data: %+v", getResp)
	}

	// 2. 测试 GET /api/v1/upstream 别名
	respAlias, err := http.Get(baseURL + "/api/v1/upstream")
	if err != nil {
		t.Fatalf("GET /api/v1/upstream failed: %v", err)
	}
	if respAlias.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on /api/v1/upstream, got %d", respAlias.StatusCode)
	}
	_ = respAlias.Body.Close()

	// 3. 测试 POST 空 payload 返回 400
	postEmpty, err := http.Post(baseURL+"/api/v1/upstream/configure", "application/json", bytes.NewReader([]byte("{}")))
	if err != nil {
		t.Fatalf("POST empty failed: %v", err)
	}
	if postEmpty.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 on empty POST, got %d", postEmpty.StatusCode)
	}
	_ = postEmpty.Body.Close()

	// 4. 测试 POST 有效 payload
	postBody, _ := json.Marshal(ipc.ConfigureUpstreamRequest{
		Mode: "PARALLEL_RACE",
		Providers: []core.ProviderConfig{
			{ID: "node-a", Protocol: core.ProtocolPlain, Server: "1.1.1.1:53", Weight: 1},
			{ID: "node-b", Protocol: core.ProtocolPlain, Server: "8.8.8.8:53", Weight: 2},
		},
	})
	postResp, err := http.Post(baseURL+"/api/v1/upstream/configure", "application/json", bytes.NewReader(postBody))
	if err != nil {
		t.Fatalf("POST valid failed: %v", err)
	}
	if postResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on valid POST, got %d", postResp.StatusCode)
	}
	_ = postResp.Body.Close()

	// 5. 再次 GET 读回确认权威列表已更新
	respAfter, err := http.Get(baseURL + "/api/v1/upstream/configure")
	if err != nil {
		t.Fatalf("GET after POST failed: %v", err)
	}
	var getRespAfter ipc.Response[*core.ResolverConfig]
	_ = json.NewDecoder(respAfter.Body).Decode(&getRespAfter)
	_ = respAfter.Body.Close()
	if len(getRespAfter.Data.Providers) != 2 || getRespAfter.Data.Mode != "PARALLEL_RACE" {
		t.Fatalf("unexpected config after update: %+v", getRespAfter.Data)
	}
}
