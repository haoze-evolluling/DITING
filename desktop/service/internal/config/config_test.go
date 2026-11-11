package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

func TestDefaultConfig(t *testing.T) {
	cfg := DefaultConfig()
	if cfg.IPC.ListenAddress != "127.0.0.1:15353" {
		t.Errorf("unexpected IPC listen address: %s", cfg.IPC.ListenAddress)
	}
	if len(cfg.Upstream.Providers) != 2 {
		t.Errorf("expected 2 default providers, got %d", len(cfg.Upstream.Providers))
	}
	if !cfg.Upstream.Bootstrap.Enabled || len(cfg.Upstream.Bootstrap.Servers) == 0 {
		t.Errorf("expected default bootstrap to be enabled with servers")
	}
	if !cfg.QueryLog.Enabled || cfg.QueryLog.MaxEntries == 0 || cfg.QueryLog.DataDir == "" {
		t.Errorf("expected query log defaults to be populated: %+v", cfg.QueryLog)
	}
}

func TestSaveAndLoadConfig(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config.json")

	// 1. 不存在时 Load 应返回默认配置
	loadedDefault, err := LoadConfig(cfgPath)
	if err != nil {
		t.Fatalf("LoadConfig on nonexistent failed: %v", err)
	}
	if loadedDefault.IPC.ListenAddress != "127.0.0.1:15353" {
		t.Errorf("unexpected default IPC address: %s", loadedDefault.IPC.ListenAddress)
	}

	// 2. 修改并保存
	loadedDefault.IPC.AuthToken = "secret-token-123"
	loadedDefault.DNS.ReadTimeout = 10 * time.Second
	if err := SaveConfig(cfgPath, loadedDefault); err != nil {
		t.Fatalf("SaveConfig failed: %v", err)
	}

	// 3. 重新加载
	reloaded, err := LoadConfig(cfgPath)
	if err != nil {
		t.Fatalf("LoadConfig failed: %v", err)
	}
	if reloaded.IPC.AuthToken != "secret-token-123" {
		t.Errorf("AuthToken mismatch: %s", reloaded.IPC.AuthToken)
	}
	if reloaded.DNS.ReadTimeout != 10*time.Second {
		t.Errorf("ReadTimeout mismatch: %v", reloaded.DNS.ReadTimeout)
	}
}

func TestConfig_StringDuration(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config.json")

	rawJSON := `{
		"dns": {
			"readTimeout": "3s",
			"writeTimeout": "2500ms"
		}
	}`

	if err := os.WriteFile(cfgPath, []byte(rawJSON), 0644); err != nil {
		t.Fatalf("write config failed: %v", err)
	}

	cfg, err := LoadConfig(cfgPath)
	if err != nil {
		t.Fatalf("LoadConfig failed: %v", err)
	}

	if cfg.DNS.ReadTimeout != 3*time.Second {
		t.Errorf("expected ReadTimeout 3s, got %v", cfg.DNS.ReadTimeout)
	}
	if cfg.DNS.WriteTimeout != 2500*time.Millisecond {
		t.Errorf("expected WriteTimeout 2500ms, got %v", cfg.DNS.WriteTimeout)
	}
	// 缺失 querylog 键时，应自动补齐默认值
	if !cfg.QueryLog.Enabled || cfg.QueryLog.MaxEntries == 0 || cfg.QueryLog.DataDir == "" {
		t.Errorf("expected query log defaults backfilled for config: %+v", cfg.QueryLog)
	}
}

func TestCurrentConfigStructure(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config_full.json")

	cfg := DefaultConfig()
	// 定制当前版本代表性字段
	cfg.DNS.BlockECH = true
	cfg.DNS.BlockIPv6 = true
	cfg.DNS.EDNSPadding = 256
	cfg.Cache.PrefetchEnabled = true
	cfg.Filter.FilterResponse = true
	cfg.Filter.AllowlistOnly = true
	cfg.SafeSearch.Enabled = true
	cfg.SafeSearch.Disabled = []string{"bing"}
	cfg.Web.Background.Type = "url"
	cfg.Web.Background.URL = "https://example.com/bg.png"
	cfg.Web.Background.Opacity = 60
	cfg.Web.Background.Blur = 8
	cfg.Rewrite.Enabled = true
	cfg.Rewrite.TTL = 120
	cfg.Rewrite.Rules = []core.RewriteRule{
		{Domain: "example.lan", IPs: []string{"192.168.1.100"}},
	}

	if err := SaveConfig(cfgPath, cfg); err != nil {
		t.Fatalf("SaveConfig failed: %v", err)
	}

	loaded, err := LoadConfig(cfgPath)
	if err != nil {
		t.Fatalf("LoadConfig failed: %v", err)
	}

	if !loaded.DNS.BlockECH || !loaded.DNS.BlockIPv6 || loaded.DNS.EDNSPadding != 256 {
		t.Errorf("DNS config mismatch: %+v", loaded.DNS)
	}
	if !loaded.Cache.PrefetchEnabled {
		t.Errorf("Cache prefetch not preserved")
	}
	if !loaded.Filter.FilterResponse || !loaded.Filter.AllowlistOnly {
		t.Errorf("Filter config mismatch: %+v", loaded.Filter)
	}
	if !loaded.SafeSearch.Enabled || len(loaded.SafeSearch.Disabled) != 1 || loaded.SafeSearch.Disabled[0] != "bing" {
		t.Errorf("SafeSearch config mismatch: %+v", loaded.SafeSearch)
	}
	if loaded.Web.Background.Type != "url" || loaded.Web.Background.Opacity != 60 || loaded.Web.Background.Blur != 8 {
		t.Errorf("Web background mismatch: %+v", loaded.Web.Background)
	}
	if !loaded.Rewrite.Enabled || loaded.Rewrite.TTL != 120 || len(loaded.Rewrite.Rules) != 1 {
		t.Errorf("Rewrite config mismatch: %+v", loaded.Rewrite)
	}
}

func TestNormalizeConfigDefaults(t *testing.T) {
	cfg := &Config{}
	cfg.DNS.EDNSPadding = -5
	cfg.Upstream.EDNSPadding = -10
	normalizeConfig(cfg)

	if cfg.DNS.EDNSPadding != 0 {
		t.Errorf("expected DNS EDNSPadding to clamp to 0, got %d", cfg.DNS.EDNSPadding)
	}
	if cfg.Upstream.EDNSPadding != 0 {
		t.Errorf("expected Upstream EDNSPadding to clamp to 0, got %d", cfg.Upstream.EDNSPadding)
	}
	if cfg.Rewrite.TTL != core.DefaultRewriteTTL {
		t.Errorf("expected Rewrite.TTL to default to %d, got %d", core.DefaultRewriteTTL, cfg.Rewrite.TTL)
	}
	if cfg.Rewrite.Rules == nil {
		t.Errorf("expected Rewrite.Rules to be non-nil slice")
	}
}

func TestNormalizeConfig_BlockANYMode(t *testing.T) {
	for _, tc := range []struct {
		name string
		in   string
		want string
	}{
		{"未知取值回落到 notimp", "typo", ANYModeNotImp},
		{"空值回落到 notimp", "", ANYModeNotImp},
		{"已知取值保持不变", ANYModeRFC8482, ANYModeRFC8482},
	} {
		t.Run(tc.name, func(t *testing.T) {
			cfg := &Config{}
			cfg.DNS.BlockANYMode = tc.in
			normalizeConfig(cfg)
			if cfg.DNS.BlockANYMode != tc.want {
				t.Fatalf("BlockANYMode = %q, want %q", cfg.DNS.BlockANYMode, tc.want)
			}
		})
	}
}

func TestDefaultConfig_BlockANY(t *testing.T) {
	cfg := DefaultConfig()
	// 合法诊断工具仍会用到 ANY，默认必须关闭，且模式要有确定取值
	if cfg.DNS.BlockANY {
		t.Error("BlockANY must default to off")
	}
	if cfg.DNS.BlockANYMode != ANYModeNotImp {
		t.Errorf("BlockANYMode = %q, want %q", cfg.DNS.BlockANYMode, ANYModeNotImp)
	}
}

func TestEffectiveListenAddresses(t *testing.T) {
	// 默认本地回环模式
	dnsCfg := DNSConfig{
		UDPAddresses: []string{"127.0.0.1:53", "[::1]:53"},
		TCPAddresses: []string{"127.0.0.1:53", "[::1]:53"},
		AllowLAN:     false,
	}
	udp, tcp := dnsCfg.EffectiveListenAddresses()
	if len(udp) != 2 || udp[0] != "127.0.0.1:53" {
		t.Errorf("expected local udp, got %v", udp)
	}
	if len(tcp) != 2 || tcp[0] != "127.0.0.1:53" {
		t.Errorf("expected local tcp, got %v", tcp)
	}

	// 启用局域网模式
	dnsCfg.AllowLAN = true
	udpLan, tcpLan := dnsCfg.EffectiveListenAddresses()
	if len(udpLan) != 2 || udpLan[0] != "0.0.0.0:53" || udpLan[1] != "[::]:53" {
		t.Errorf("expected lan udp 0.0.0.0 and [::], got %v", udpLan)
	}
	if len(tcpLan) != 2 || tcpLan[0] != "0.0.0.0:53" || tcpLan[1] != "[::]:53" {
		t.Errorf("expected lan tcp 0.0.0.0 and [::], got %v", tcpLan)
	}

	// 自定义端口局域网模式
	dnsCfgPort := DNSConfig{
		UDPAddresses: []string{"127.0.0.1:5353"},
		AllowLAN:     true,
	}
	udpPort, _ := dnsCfgPort.EffectiveListenAddresses()
	if udpPort[0] != "0.0.0.0:5353" || udpPort[1] != "[::]:5353" {
		t.Errorf("expected custom port lan addresses, got %v", udpPort)
	}

	// 局域网模式关闭且原配置残留通配地址时，应安全降级还原为回环地址
	dnsCfgWildcardDisabled := DNSConfig{
		UDPAddresses: []string{"0.0.0.0:53", "[::]:53"},
		TCPAddresses: []string{"0.0.0.0:53", "[::]:53"},
		AllowLAN:     false,
	}
	udpReverted, tcpReverted := dnsCfgWildcardDisabled.EffectiveListenAddresses()
	if len(udpReverted) != 2 || udpReverted[0] != "127.0.0.1:53" || udpReverted[1] != "[::1]:53" {
		t.Errorf("expected sanitized local addresses, got %v", udpReverted)
	}
	if len(tcpReverted) != 2 || tcpReverted[0] != "127.0.0.1:53" || tcpReverted[1] != "[::1]:53" {
		t.Errorf("expected sanitized local addresses, got %v", tcpReverted)
	}
}
