package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"
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
