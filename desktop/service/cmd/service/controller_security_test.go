package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

func TestController_SecurityAndTransitionConfig(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config.json")

	cfg := config.DefaultConfig()
	if err := config.SaveConfig(cfgPath, cfg); err != nil {
		t.Fatalf("save config failed: %v", err)
	}

	ac, _ := core.NewAccessControl(cfg.Access)
	limiter := core.NewRateLimiter(context.Background(), cfg.RateLimit)
	synth, _ := core.NewDNS64Synthesizer(cfg.DNS64)

	prg := &program{
		cfg:           cfg,
		configPath:    cfgPath,
		accessControl: ac,
		rateLimiter:   limiter,
		dns64Synth:    synth,
	}

	ctx := context.Background()

	// 1. 测试 ConfigureAccess
	accessReq := ipc.ConfigureAccessRequest{
		AllowedClients: []string{"192.168.1.0/24", "10.0.0.1"},
		BlockedClients: []string{"192.168.1.250"},
	}
	if err := prg.ConfigureAccess(ctx, accessReq); err != nil {
		t.Fatalf("ConfigureAccess failed: %v", err)
	}
	if len(prg.cfg.Access.AllowedClients) != 2 || len(prg.cfg.Access.BlockedClients) != 1 {
		t.Errorf("unexpected access config: %+v", prg.cfg.Access)
	}

	// 2. 测试 ConfigureRateLimit
	rateReq := ipc.ConfigureRateLimitRequest{
		Enabled:    true,
		Rate:       20.0,
		Burst:      40,
		IPv4Prefix: 24,
		IPv6Prefix: 56,
		ExemptIPs:  []string{"127.0.0.1", "192.168.1.1"},
	}
	if err := prg.ConfigureRateLimit(ctx, rateReq); err != nil {
		t.Fatalf("ConfigureRateLimit failed: %v", err)
	}
	if !prg.cfg.RateLimit.Enabled || prg.cfg.RateLimit.Rate != 20.0 || prg.cfg.RateLimit.Burst != 40 {
		t.Errorf("unexpected rate limit config: %+v", prg.cfg.RateLimit)
	}

	// 3. 测试 ConfigureDNS64
	dns64Req := ipc.ConfigureDNS64Request{
		Enabled:  true,
		Prefixes: []string{"64:ff9b::/96", "2001:db8:1234::/64"},
	}
	if err := prg.ConfigureDNS64(ctx, dns64Req); err != nil {
		t.Fatalf("ConfigureDNS64 failed: %v", err)
	}
	if !prg.cfg.DNS64.Enabled || len(prg.cfg.DNS64.Prefixes) != 2 {
		t.Errorf("unexpected dns64 config: %+v", prg.cfg.DNS64)
	}

	// 4. 测试 ConfigureBlockUnqualified
	unqualReq := ipc.ConfigureBlockUnqualifiedRequest{
		BlockUnqualified: true,
	}
	if err := prg.ConfigureBlockUnqualified(ctx, unqualReq); err != nil {
		t.Fatalf("ConfigureBlockUnqualified failed: %v", err)
	}
	if !prg.cfg.DNS.BlockUnqualified {
		t.Errorf("expected BlockUnqualified to be true")
	}

	// 5. 测试 ConfigurePrivacy (BlockPrivatePTR, BlockIPv6, BlockECH, EDNSPadding)
	bTrue := true
	bFalse := false
	pad256 := 256
	privReq := ipc.ConfigurePrivacyRequest{
		BlockPrivatePTR: &bFalse,
		BlockIPv6:       &bTrue,
		BlockECH:        &bTrue,
		EDNSPadding:     &pad256,
	}
	if err := prg.ConfigurePrivacy(ctx, privReq); err != nil {
		t.Fatalf("ConfigurePrivacy failed: %v", err)
	}
	if prg.cfg.DNS.BlockPrivatePTR != false || !prg.cfg.DNS.BlockIPv6 || !prg.cfg.DNS.BlockECH || prg.cfg.DNS.EDNSPadding != 256 {
		t.Errorf("unexpected DNS privacy config: %+v", prg.cfg.DNS)
	}
	if prg.cfg.Upstream.EDNSPadding != 256 {
		t.Errorf("expected upstream EDNSPadding to be 256, got %d", prg.cfg.Upstream.EDNSPadding)
	}

	// 6. 测试 ConfigurePrivacy 的 ANY 最小化字段
	anyMode := config.ANYModeRFC8482
	anyReq := ipc.ConfigurePrivacyRequest{
		BlockANY:     &bTrue,
		BlockANYMode: &anyMode,
	}
	if err := prg.ConfigurePrivacy(ctx, anyReq); err != nil {
		t.Fatalf("ConfigurePrivacy (ANY) failed: %v", err)
	}
	if !prg.cfg.DNS.BlockANY || prg.cfg.DNS.BlockANYMode != config.ANYModeRFC8482 {
		t.Errorf("unexpected ANY config: %+v", prg.cfg.DNS)
	}

	// 未知模式必须回落到 notimp，而不能原样写入一个下游无法识别的取值
	bogusMode := "rfc8482-typo"
	prg.ConfigurePrivacy(ctx, ipc.ConfigurePrivacyRequest{BlockANYMode: &bogusMode})
	if prg.cfg.DNS.BlockANYMode != config.ANYModeNotImp {
		t.Errorf("unknown mode must fall back to notimp, got %q", prg.cfg.DNS.BlockANYMode)
	}
	// 只回传模式时不得顺带改写开关
	if !prg.cfg.DNS.BlockANY {
		t.Error("BlockANY must stay untouched when the request omits it")
	}
	prg.ConfigurePrivacy(ctx, ipc.ConfigurePrivacyRequest{BlockANYMode: &anyMode})

	// 验证磁盘配置文件持久化是否正确写入
	reloaded, err := config.LoadConfig(cfgPath)
	if err != nil {
		t.Fatalf("reload config failed: %v", err)
	}
	if !reloaded.DNS.BlockUnqualified || !reloaded.DNS64.Enabled || !reloaded.RateLimit.Enabled {
		t.Errorf("persisted config mismatch: %+v", reloaded)
	}
	if reloaded.DNS.BlockPrivatePTR != false || !reloaded.DNS.BlockIPv6 || !reloaded.DNS.BlockECH || reloaded.DNS.EDNSPadding != 256 {
		t.Errorf("persisted privacy config mismatch: %+v", reloaded.DNS)
	}
	if !reloaded.DNS.BlockANY || reloaded.DNS.BlockANYMode != config.ANYModeRFC8482 {
		t.Errorf("persisted ANY config mismatch: %+v", reloaded.DNS)
	}
	_ = os.RemoveAll(tmpDir)
}

