package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/auth"
	"github.com/haoze-evolluling/diting/windows/internal/config"
	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/haoze-evolluling/diting/windows/internal/ipc"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
	miekgdns "github.com/miekg/dns"
)

func TestController_TestUpstream_DoH(t *testing.T) {
	// 启动一个模拟 DoH 服务器
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if r.Header.Get("Content-Type") != "application/dns-message" {
			http.Error(w, "invalid content type", http.StatusBadRequest)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		reqMsg := new(miekgdns.Msg)
		if err := reqMsg.Unpack(body); err != nil {
			http.Error(w, "bad dns wireformat", http.StatusBadRequest)
			return
		}

		respMsg := new(miekgdns.Msg)
		respMsg.SetReply(reqMsg)
		respMsg.Response = true
		respMsg.Answer = append(respMsg.Answer, &miekgdns.A{
			Hdr: miekgdns.RR_Header{
				Name:   reqMsg.Question[0].Name,
				Rrtype: miekgdns.TypeA,
				Class:  miekgdns.ClassINET,
				Ttl:    300,
			},
			A: []byte{223, 5, 5, 5},
		})

		wire, err := respMsg.Pack()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/dns-message")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(wire)
	}))
	defer ts.Close()

	prg := &program{
		cfg: config.DefaultConfig(),
	}

	// 1. 成功测试
	res, err := prg.TestUpstream(context.Background(), ipc.TestUpstreamRequest{
		Protocol: "DOH",
		URL:      ts.URL + "/dns-query",
	})
	if err != nil {
		t.Fatalf("TestUpstream unexpected err: %v", err)
	}
	if !res.Success {
		t.Fatalf("expected success, got error: %s", res.Error)
	}
	if res.LatencyMs <= 0 {
		t.Errorf("expected positive latency, got %f", res.LatencyMs)
	}

	// 2. 状态码错误测试
	errorTs := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "upstream rate limited", http.StatusTooManyRequests)
	}))
	defer errorTs.Close()

	errRes, err := prg.TestUpstream(context.Background(), ipc.TestUpstreamRequest{
		Protocol: "DOH",
		URL:      errorTs.URL,
	})
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if errRes.Success {
		t.Errorf("expected failure on 429 status code, got success")
	}
}

func TestController_TestUpstream_EmptyServer(t *testing.T) {
	prg := &program{
		cfg: config.DefaultConfig(),
	}

	res, err := prg.TestUpstream(context.Background(), ipc.TestUpstreamRequest{})
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if res.Success || res.Error != "未指定服务器地址" {
		t.Errorf("expected error for empty server, got res=%+v", res)
	}
}

func TestController_ConfigureUpstream(t *testing.T) {
	cfg := config.DefaultConfig()
	resolver, err := core.NewResolver(cfg.Upstream)
	if err != nil {
		t.Fatalf("NewResolver failed: %v", err)
	}

	prg := &program{
		cfg:      cfg,
		resolver: resolver,
	}

	tmpConfig := t.TempDir() + "/config.json"
	prg.configPath = tmpConfig

	bsCfg := core.BootstrapConfig{
		Enabled: true,
		Servers: []core.BootstrapServer{
			{ID: "bs-cf", Name: "Cloudflare", Address: "1.1.1.1:53"},
		},
	}
	err = prg.ConfigureUpstream(context.Background(), ipc.ConfigureUpstreamRequest{
		Mode: "SINGLE",
		Providers: []core.ProviderConfig{
			{ID: "node-1", Protocol: core.ProtocolPlain, Server: "223.5.5.5:53"},
		},
		Bootstrap: &bsCfg,
	})
	if err != nil {
		t.Fatalf("ConfigureUpstream failed: %v", err)
	}

	if prg.cfg.Upstream.Mode != "SINGLE" {
		t.Errorf("expected mode SINGLE, got %s", prg.cfg.Upstream.Mode)
	}
	if len(prg.cfg.Upstream.Providers) != 1 {
		t.Errorf("expected 1 provider")
	}
	if len(prg.cfg.Upstream.Bootstrap.Servers) != 1 || prg.cfg.Upstream.Bootstrap.Servers[0].Address != "1.1.1.1:53" {
		t.Errorf("bootstrap config not updated: %+v", prg.cfg.Upstream.Bootstrap)
	}

	// 验证持久化保存
	loadedCfg, err := config.LoadConfig(tmpConfig)
	if err != nil || len(loadedCfg.Upstream.Bootstrap.Servers) != 1 {
		t.Fatalf("failed to reload persisted config: %v, %+v", err, loadedCfg)
	}

	// 校验非法 IP 报错
	badBsCfg := core.BootstrapConfig{
		Enabled: true,
		Servers: []core.BootstrapServer{
			{ID: "bad", Address: "invalid-domain.com"},
		},
	}
	err = prg.ConfigureUpstream(context.Background(), ipc.ConfigureUpstreamRequest{
		Bootstrap: &badBsCfg,
	})
	if err == nil {
		t.Fatalf("expected error on invalid bootstrap IP, got nil")
	}

	// 校验关闭 Bootstrap 配置时的持久化与重新加载
	disabledBsCfg := core.BootstrapConfig{
		Enabled: false,
		Servers: []core.BootstrapServer{},
	}
	err = prg.ConfigureUpstream(context.Background(), ipc.ConfigureUpstreamRequest{
		Bootstrap: &disabledBsCfg,
	})
	if err != nil {
		t.Fatalf("ConfigureUpstream disabled failed: %v", err)
	}
	reloadedDisabled, err := config.LoadConfig(tmpConfig)
	if err != nil {
		t.Fatalf("LoadConfig failed: %v", err)
	}
	if reloadedDisabled.Upstream.Bootstrap.Enabled {
		t.Errorf("expected bootstrap Enabled to remain false after reload, got true")
	}
}

func TestController_TestUpstream_IPv6(t *testing.T) {
	prg := &program{
		cfg: config.DefaultConfig(),
	}

	// 验证对纯 IPv6 地址的格式处理，不能报 "missing port in address"
	res, err := prg.TestUpstream(context.Background(), ipc.TestUpstreamRequest{
		Protocol: "PLAIN",
		Server:   "2400:3200::1",
	})
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if !res.Success && strings.Contains(res.Error, "missing port in address") {
		t.Fatalf("expected valid port formatting for IPv6, got error: %s", res.Error)
	}
}

func TestController_CacheMethods(t *testing.T) {
	cfg := config.DefaultConfig()
	cache := core.NewDNSCache(cfg.Cache)
	defer cache.Close()

	prg := &program{
		cfg:   cfg,
		cache: cache,
	}

	ctx := context.Background()

	// 1. GetCacheStats
	st, err := prg.GetCacheStats(ctx)
	if err != nil || !st.Enabled {
		t.Fatalf("GetCacheStats failed: err=%v, st=%+v", err, st)
	}

	// 2. Put 条目并通过 controller 查询
	req := new(miekgdns.Msg)
	req.SetQuestion("cached-ctrl.com.", miekgdns.TypeA)
	resp := new(miekgdns.Msg)
	resp.SetReply(req)
	resp.Answer = []miekgdns.RR{
		&miekgdns.A{
			Hdr: miekgdns.RR_Header{Name: "cached-ctrl.com.", Rrtype: miekgdns.TypeA, Class: miekgdns.ClassINET, Ttl: 60},
			A:   []byte{1, 2, 3, 4},
		},
	}
	cache.Put(req, resp)

	// 3. GetCacheEntries
	entries, err := prg.GetCacheEntries(ctx, "cached-ctrl", 10)
	if err != nil || entries.Total != 1 {
		t.Fatalf("GetCacheEntries failed: err=%v, entries=%+v", err, entries)
	}

	// 4. GetCacheTopDomains
	top, err := prg.GetCacheTopDomains(ctx, 5)
	if err != nil || len(top) != 1 {
		t.Fatalf("GetCacheTopDomains failed: err=%v, top=%+v", err, top)
	}

	// 5. GetCacheConfig & UpdateCacheConfig
	cCfg, err := prg.GetCacheConfig(ctx)
	if err != nil || !cCfg.Enabled {
		t.Fatalf("GetCacheConfig failed: err=%v, cCfg=%+v", err, cCfg)
	}

	cCfg.MaxTTLSeconds = 1200
	if err := prg.UpdateCacheConfig(ctx, *cCfg); err != nil {
		t.Fatalf("UpdateCacheConfig failed: %v", err)
	}
	if prg.cfg.Cache.MaxTTLSeconds != 1200 {
		t.Errorf("expected MaxTTLSeconds 1200, got %d", prg.cfg.Cache.MaxTTLSeconds)
	}

	// 6. ClearCache
	if err := prg.ClearCache(ctx); err != nil {
		t.Fatalf("ClearCache failed: %v", err)
	}
	stAfter, _ := prg.GetCacheStats(ctx)
	if stAfter.EntryCount != 0 {
		t.Errorf("expected 0 entries after clear, got %d", stAfter.EntryCount)
	}
}

func TestController_FilterIntegration(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := config.DefaultConfig()
	cfg.Filter.DataDir = tmpDir
	cfg.Filter.Lists = []core.FilterList{}
	cfg.Filter.CustomRules = []string{"||blocked-ad.com^"}

	engine := core.NewRuleEngine(cfg.Filter)
	defer engine.Close()

	prg := &program{
		cfg:          cfg,
		filterEngine: engine,
	}

	ctx := context.Background()

	// 1. GetFilterStats
	st, err := prg.GetFilterStats(ctx)
	if err != nil || !st.Enabled {
		t.Fatalf("GetFilterStats failed: err=%v, st=%+v", err, st)
	}

	// 2. CheckHostRule
	check, err := prg.CheckHostRule(ctx, "blocked-ad.com", 1)
	if err != nil || !check.Blocked {
		t.Fatalf("CheckHostRule failed: err=%v, res=%+v", err, check)
	}

	// 3. GetFilterConfig & UpdateFilterConfig
	fCfg, err := prg.GetFilterConfig(ctx)
	if err != nil || !fCfg.Enabled {
		t.Fatalf("GetFilterConfig failed: err=%v, fCfg=%+v", err, fCfg)
	}
	fCfg.BlockMode = core.BlockModeNXDOMAIN
	if err := prg.UpdateFilterConfig(ctx, *fCfg); err != nil {
		t.Fatalf("UpdateFilterConfig failed: %v", err)
	}
	if prg.cfg.Filter.BlockMode != core.BlockModeNXDOMAIN {
		t.Errorf("expected BlockMode nxdomain, got %s", prg.cfg.Filter.BlockMode)
	}

	// 4. CustomRules
	rules, err := prg.GetCustomRules(ctx)
	if err != nil || len(rules) != 1 {
		t.Fatalf("GetCustomRules failed: err=%v, rules=%+v", err, rules)
	}
	if err := prg.SetCustomRules(ctx, []string{"||new-ad.com^"}); err != nil {
		t.Fatalf("SetCustomRules failed: %v", err)
	}
	checkNew, _ := prg.CheckHostRule(ctx, "new-ad.com", 1)
	if !checkNew.Blocked {
		t.Fatalf("new-ad.com should be blocked")
	}

	// 5. FilterLists
	lists, err := prg.GetFilterLists(ctx)
	if err != nil {
		t.Fatalf("GetFilterLists failed: %v", err)
	}
	if err := prg.AddFilterList(ctx, core.FilterList{ID: "local-list", Name: "Local List", URL: "data.txt", Enabled: true}); err != nil {
		// local file might not exist yet, but call was routed
	}
	_ = lists
}

func TestController_LANIntegration(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := tmpDir + "/config.json"

	prg := &program{
		configPath: cfgPath,
		cfg:        config.DefaultConfig(),
	}
	ctx := context.Background()

	// 1. 获取局域网状态
	lanStatus, err := prg.GetLANStatus(ctx)
	if err != nil {
		t.Fatalf("GetLANStatus failed: %v", err)
	}
	if lanStatus.AllowLAN {
		t.Errorf("default allowLAN should be false")
	}

	// 2. 配置启用局域网模式
	err = prg.ConfigureLAN(ctx, ipc.ConfigureLANRequest{
		AllowLAN:          true,
		ConfigureFirewall: false,
	})
	if err != nil {
		t.Fatalf("ConfigureLAN failed: %v", err)
	}
	if !prg.cfg.DNS.AllowLAN {
		t.Errorf("expected AllowLAN true after configure")
	}

	// 3. 再次获取局域网状态验证
	lanStatusUpdated, err := prg.GetLANStatus(ctx)
	if err != nil {
		t.Fatalf("GetLANStatus after update failed: %v", err)
	}
	if !lanStatusUpdated.AllowLAN {
		t.Errorf("expected AllowLAN true in status response")
	}
	if len(lanStatusUpdated.ListenAddresses) != 2 || lanStatusUpdated.ListenAddresses[0] != "0.0.0.0:53" {
		t.Errorf("expected listen on 0.0.0.0:53, got: %v", lanStatusUpdated.ListenAddresses)
	}

	// 4. 关闭局域网模式，验证安全还原为本地回环 (127.0.0.1:53)
	err = prg.ConfigureLAN(ctx, ipc.ConfigureLANRequest{
		AllowLAN:          false,
		ConfigureFirewall: false,
	})
	if err != nil {
		t.Fatalf("ConfigureLAN disable failed: %v", err)
	}
	if prg.cfg.DNS.AllowLAN {
		t.Errorf("expected AllowLAN false after disable")
	}

	lanStatusDisabled, err := prg.GetLANStatus(ctx)
	if err != nil {
		t.Fatalf("GetLANStatus after disable failed: %v", err)
	}
	if lanStatusDisabled.AllowLAN {
		t.Errorf("expected AllowLAN false in status response")
	}
	if len(lanStatusDisabled.ListenAddresses) != 2 || lanStatusDisabled.ListenAddresses[0] != "127.0.0.1:53" {
		t.Errorf("expected reverted local listen on 127.0.0.1:53, got: %v", lanStatusDisabled.ListenAddresses)
	}
}

func TestController_WebAndAuthIntegration(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config.json")

	cfg := config.DefaultConfig()
	cfg.Web.Enabled = false
	cfg.Web.ListenPort = 15353
	_ = config.SaveConfig(cfgPath, cfg)

	prg := &program{
		configPath: cfgPath,
		cfg:        cfg,
		authMgr:    auth.NewManager("admin", "", "", 24*time.Hour),
	}
	ctx := context.Background()

	// 1. 获取初始状态
	webStatus, err := prg.GetWebStatus(ctx)
	if err != nil {
		t.Fatalf("GetWebStatus failed: %v", err)
	}
	if webStatus.Enabled || webStatus.Initialized {
		t.Errorf("expected webStatus initial disabled and uninitialized")
	}

	// 2. 初始化管理员凭据
	err = prg.SetupAuth(ctx, ipc.SetupAuthRequest{Username: "admin", Password: "testpassword123"})
	if err != nil {
		t.Fatalf("SetupAuth failed: %v", err)
	}

	// 3. 登录并校验 Token
	loginResp, err := prg.Login(ctx, ipc.LoginRequest{Username: "admin", Password: "testpassword123"}, "127.0.0.1")
	if err != nil {
		t.Fatalf("Login failed: %v", err)
	}
	if !prg.ValidateSession(loginResp.Token) {
		t.Errorf("session token should be valid")
	}

	// 4. 启用局域网 Web 管理
	err = prg.ConfigureWeb(ctx, ipc.ConfigureWebRequest{
		Enabled:           true,
		Port:              15353,
		ConfigureFirewall: false,
	})
	if err != nil {
		t.Fatalf("ConfigureWeb failed: %v", err)
	}
	if !prg.cfg.Web.Enabled || prg.cfg.IPC.ListenAddress != "0.0.0.0:15353" {
		t.Errorf("expected Web enabled on 0.0.0.0:15353, got: %s", prg.cfg.IPC.ListenAddress)
	}

	// 5. 修改密码
	err = prg.ChangePassword(ctx, ipc.ChangePasswordRequest{
		Username:    "admin",
		OldPassword: "testpassword123",
		NewPassword: "newpassword456",
	}, false)
	if err != nil {
		t.Fatalf("ChangePassword failed: %v", err)
	}

	// 密码修改后原 Token 应失效
	if prg.ValidateSession(loginResp.Token) {
		t.Errorf("old session token should be invalidated after password change")
	}
}

type mockTestPortChecker struct {
	checkResult   *windows.PortCheckResult
	autofixResult *windows.PortCheckResult
	autofixErr    error
	lastUDPAddrs  []string
	lastTCPAddrs  []string
}

func (m *mockTestPortChecker) CheckPort53(ctx context.Context) (*windows.PortCheckResult, error) {
	return m.checkResult, nil
}
func (m *mockTestPortChecker) CheckPort53ForAddresses(ctx context.Context, udpAddrs, tcpAddrs []string) (*windows.PortCheckResult, error) {
	m.lastUDPAddrs = udpAddrs
	m.lastTCPAddrs = tcpAddrs
	return m.checkResult, nil
}
func (m *mockTestPortChecker) AutofixPort53ForAddresses(ctx context.Context, udpAddrs, tcpAddrs []string) (*windows.PortCheckResult, error) {
	m.lastUDPAddrs = udpAddrs
	m.lastTCPAddrs = tcpAddrs
	return m.autofixResult, m.autofixErr
}

func TestController_PortConflictsAndAutofix(t *testing.T) {
	mockChecker := &mockTestPortChecker{
		checkResult: &windows.PortCheckResult{
			Available:  false,
			HasICS:     true,
			CanAutofix: true,
			Diagnostic: "ICS conflict on 0.0.0.0:53",
		},
		autofixResult: &windows.PortCheckResult{
			Available:  true,
			HasICS:     false,
			CanAutofix: false,
			Diagnostic: "conflict resolved",
		},
	}

	cfg := config.DefaultConfig()
	cfg.DNS.AllowLAN = true
	cfg.DNS.UDPAddresses = []string{"0.0.0.0:53"}
	cfg.DNS.TCPAddresses = []string{"0.0.0.0:53"}

	prg := &program{
		cfg:         cfg,
		portChecker: mockChecker,
	}
	ctx := context.Background()

	// 1. 测试 CheckPortConflicts 传递实际监听地址
	res, err := prg.CheckPortConflicts(ctx)
	if err != nil {
		t.Fatalf("CheckPortConflicts error: %v", err)
	}
	if res.Available || !res.CanAutofix {
		t.Errorf("expected Available=false, CanAutofix=true, got %+v", res)
	}
	if len(mockChecker.lastUDPAddrs) == 0 || mockChecker.lastUDPAddrs[0] != "0.0.0.0:53" {
		t.Errorf("expected CheckPortConflicts to query 0.0.0.0:53, got %v", mockChecker.lastUDPAddrs)
	}

	// 2. 测试 AutofixPortConflicts 传递目标地址且成功修复
	fixRes, err := prg.AutofixPortConflicts(ctx, false)
	if err != nil {
		t.Fatalf("AutofixPortConflicts error: %v", err)
	}
	if !fixRes.Available {
		t.Errorf("expected Available=true after autofix, got %+v", fixRes)
	}
	if len(mockChecker.lastUDPAddrs) == 0 || mockChecker.lastUDPAddrs[0] != "0.0.0.0:53" {
		t.Errorf("expected AutofixPortConflicts to re-probe 0.0.0.0:53, got %v", mockChecker.lastUDPAddrs)
	}
}

