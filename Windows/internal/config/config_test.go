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
