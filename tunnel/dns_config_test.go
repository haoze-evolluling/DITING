package tunnel

import (
	"testing"
)

func TestCanonicalDNSMode(t *testing.T) {
	tests := []struct {
		input    string
		expected string
		wantErr  bool
	}{
		{"single", "single", false},
		{"SINGLE", "single", false},
		{"primary_backup", "primary_backup", false},
		{"PRIMARY_BACKUP", "primary_backup", false},
		{"parallel_race", "parallel_race", false},
		{"race", "parallel_race", false},
		{"brute_force_parallel", "parallel_race", false},
		{"smart_prediction", "smart_prediction", false},
		{"prediction", "smart_prediction", false},
		{"unknown_mode", "", true},
		{"", "", true},
	}

	for _, tt := range tests {
		got, err := canonicalDNSMode(tt.input)
		if (err != nil) != tt.wantErr {
			t.Errorf("canonicalDNSMode(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			continue
		}
		if got != tt.expected {
			t.Errorf("canonicalDNSMode(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}

func TestValidateDNSProvider(t *testing.T) {
	tests := []struct {
		name    string
		cfg     dnsProviderConfig
		wantErr bool
	}{
		{
			name: "Valid PLAIN",
			cfg: dnsProviderConfig{
				Protocol: "PLAIN",
				Server:   "8.8.8.8:53",
			},
			wantErr: false,
		},
		{
			name: "Invalid PLAIN without port",
			cfg: dnsProviderConfig{
				Protocol: "PLAIN",
				Server:   "8.8.8.8",
			},
			wantErr: true,
		},
		{
			name: "Valid DOT",
			cfg: dnsProviderConfig{
				Protocol: "DOT",
				Server:   "1.1.1.1:853",
			},
			wantErr: false,
		},
		{
			name: "Valid DOH",
			cfg: dnsProviderConfig{
				Protocol: "DOH",
				URL:      "https://dns.google/dns-query",
			},
			wantErr: false,
		},
		{
			name: "Invalid DOH http",
			cfg: dnsProviderConfig{
				Protocol: "DOH",
				URL:      "http://dns.google/dns-query",
			},
			wantErr: true,
		},
		{
			name: "Valid DOQ",
			cfg: dnsProviderConfig{
				Protocol: "DOQ",
				URL:      "quic://dns.adguard.com:853",
			},
			wantErr: false,
		},
		{
			name: "Unknown protocol",
			cfg: dnsProviderConfig{
				Protocol: "DNSCRYPT",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateDNSProvider(tt.cfg)
			if (err != nil) != tt.wantErr {
				t.Errorf("validateDNSProvider() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestApplyDNSConfig_Modes(t *testing.T) {
	engine := NewEngine()

	singleJSON := `{
		"mode": "single",
		"blockResponse": "CUSTOM_IP",
		"dynamicResponse": {"enabled": false},
		"providers": [
			{"id": "p1", "protocol": "PLAIN", "server": "8.8.8.8:53", "url": ""}
		]
	}`
	if err := engine.ApplyDNSConfig(singleJSON); err != nil {
		t.Fatalf("ApplyDNSConfig single failed: %v", err)
	}

	singleInvalidJSON := `{
		"mode": "single",
		"blockResponse": "CUSTOM_IP",
		"dynamicResponse": {"enabled": false},
		"providers": [
			{"id": "p1", "protocol": "PLAIN", "server": "8.8.8.8:53", "url": ""},
			{"id": "p2", "protocol": "PLAIN", "server": "1.1.1.1:53", "url": ""}
		]
	}`
	if err := engine.ApplyDNSConfig(singleInvalidJSON); err == nil {
		t.Errorf("ApplyDNSConfig single with 2 providers should fail, got nil")
	}

	raceJSON := `{
		"mode": "parallel_race",
		"blockResponse": "NXDOMAIN",
		"dynamicResponse": {"enabled": false},
		"providers": [
			{"id": "p1", "protocol": "PLAIN", "server": "8.8.8.8:53", "url": ""},
			{"id": "p2", "protocol": "PLAIN", "server": "1.1.1.1:53", "url": ""}
		]
	}`
	if err := engine.ApplyDNSConfig(raceJSON); err != nil {
		t.Fatalf("ApplyDNSConfig parallel_race failed: %v", err)
	}

	predJSON := `{
		"mode": "smart_prediction",
		"blockResponse": "REFUSED",
		"dynamicResponse": {"enabled": false},
		"providers": [
			{"id": "p1", "protocol": "PLAIN", "server": "8.8.8.8:53", "url": ""},
			{"id": "p2", "protocol": "DOH", "server": "", "url": "https://dns.google/dns-query"}
		]
	}`
	if err := engine.ApplyDNSConfig(predJSON); err != nil {
		t.Fatalf("ApplyDNSConfig smart_prediction failed: %v", err)
	}
}
