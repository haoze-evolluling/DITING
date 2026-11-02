package main

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	ditingdns "github.com/haoze-evolluling/diting/server/internal/dns"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

func TestController_RewriteClientAndECS(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config.json")

	cfg := config.DefaultConfig()
	if err := config.SaveConfig(cfgPath, cfg); err != nil {
		t.Fatalf("save config failed: %v", err)
	}

	rewriteEngine := core.NewRewriteEngine(cfg.Rewrite)
	clientResolver := core.NewClientResolver(cfg.Client, rewriteEngine)
	ecsMgr := ditingdns.NewECSManager(cfg.ECS)

	prg := &program{
		cfg:            cfg,
		configPath:     cfgPath,
		rewriteEngine:  rewriteEngine,
		clientResolver: clientResolver,
		ecsMgr:         ecsMgr,
	}

	ctx := context.Background()

	// 1. 添加与读取 Rewrite 规则
	newRule := core.RewriteRule{
		Domain: "service.lan",
		IPs:    []string{"10.0.0.88"},
	}
	if err := prg.AddRewriteRule(ctx, newRule); err != nil {
		t.Fatalf("AddRewriteRule failed: %v", err)
	}

	rules, err := prg.GetRewriteRules(ctx)
	if err != nil || len(rules) != 1 || rules[0].Domain != "service.lan" {
		t.Fatalf("unexpected rules: %v, err: %v", rules, err)
	}

	// 2. 删除 Rewrite 规则
	if err := prg.DeleteRewriteRule(ctx, "service.lan"); err != nil {
		t.Fatalf("DeleteRewriteRule failed: %v", err)
	}
	rules, _ = prg.GetRewriteRules(ctx)
	if len(rules) != 0 {
		t.Fatalf("expected 0 rules after deletion")
	}

	// 3. 全局 ConfigureRewrite
	enabled := true
	ttl := uint32(300)
	bulkRules := []core.RewriteRule{
		{Domain: "*.home.arpa", IPs: []string{"192.168.1.1"}},
	}
	if err := prg.ConfigureRewrite(ctx, ipc.ConfigureRewriteRequest{
		Enabled: &enabled,
		TTL:     &ttl,
		Rules:   &bulkRules,
	}); err != nil {
		t.Fatalf("ConfigureRewrite failed: %v", err)
	}
	rules, _ = prg.GetRewriteRules(ctx)
	if len(rules) != 1 || rules[0].Domain != "*.home.arpa" {
		t.Fatalf("unexpected bulk rules: %v", rules)
	}

	// 4. ConfigureClientAlias 与 GetClients
	if err := prg.ConfigureClientAlias(ctx, ipc.ConfigureClientAliasRequest{
		IP:   "192.168.1.99",
		Name: "Smart-TV",
	}); err != nil {
		t.Fatalf("ConfigureClientAlias failed: %v", err)
	}
	clients, err := prg.GetClients(ctx)
	if err != nil {
		t.Fatalf("GetClients failed: %v", err)
	}
	foundTV := false
	for _, c := range clients {
		if c.IP == "192.168.1.99" && c.Name == "Smart-TV" {
			foundTV = true
			break
		}
	}
	if !foundTV {
		t.Fatalf("expected to find Smart-TV in clients list: %v", clients)
	}

	// 5. ConfigureECS
	strip := true
	customSubnet := "198.51.100.0/24"
	if err := prg.ConfigureECS(ctx, ipc.ConfigureECSRequest{
		Enabled:      &enabled,
		StripECS:     &strip,
		CustomSubnet: &customSubnet,
	}); err != nil {
		t.Fatalf("ConfigureECS failed: %v", err)
	}
	if !prg.cfg.ECS.Enabled || !prg.cfg.ECS.StripECS || prg.cfg.ECS.CustomSubnet != "198.51.100.0/24" {
		t.Fatalf("unexpected prg.cfg.ECS: %+v", prg.cfg.ECS)
	}
}
