package tunnel

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/url"
	"strings"
	"sync"
	"time"
)

type dnsProviderConfig struct {
	ID       string `json:"id"`
	Protocol string `json:"protocol"`
	Server   string `json:"server"`
	URL      string `json:"url"`
	Weight   int    `json:"weight,omitempty"`
}

type dynamicBlockConfig struct {
	Enabled          bool `json:"enabled"`
	RequestThreshold int  `json:"requestThreshold"`
	WindowSeconds    int  `json:"windowSeconds"`
	NXDomainSeconds  int  `json:"nxDomainDurationSeconds"`
}

type dnsEngineConfig struct {
	Mode            string              `json:"mode"`
	Providers       []dnsProviderConfig `json:"providers"`
	BlockResponse   string              `json:"blockResponse"`
	DynamicResponse dynamicBlockConfig  `json:"dynamicResponse"`
	Cache           dnsCacheConfig      `json:"cache"`
	Bootstrap       bootstrapConfig     `json:"bootstrap"`
}

type dynamicBlockEntry struct {
	windowStarted time.Time
	requestCount  int
	nxDomainUntil time.Time
}

type dynamicBlockTracker struct {
	mu      sync.Mutex
	entries map[string]*dynamicBlockEntry
}

func (t *dynamicBlockTracker) reset() {
	t.mu.Lock()
	t.entries = make(map[string]*dynamicBlockEntry)
	t.mu.Unlock()
}

func (t *dynamicBlockTracker) responseFor(domain string, cfg dynamicBlockConfig, fallback ResponseType) ResponseType {
	if !cfg.Enabled {
		return fallback
	}
	now := time.Now()
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.entries == nil {
		t.entries = make(map[string]*dynamicBlockEntry)
	}
	entry := t.entries[domain]
	if entry != nil && now.Before(entry.nxDomainUntil) {
		return ResponseNXDomain
	}
	window := time.Duration(cfg.WindowSeconds) * time.Second
	if entry == nil || now.Sub(entry.windowStarted) >= window {
		entry = &dynamicBlockEntry{windowStarted: now, requestCount: 1}
		t.entries[domain] = entry
	} else {
		entry.requestCount++
	}
	if entry.requestCount > cfg.RequestThreshold {
		entry.nxDomainUntil = now.Add(time.Duration(cfg.NXDomainSeconds) * time.Second)
		return ResponseNXDomain
	}
	if len(t.entries) > 4096 {
		for key := range t.entries {
			delete(t.entries, key)
			break
		}
	}
	return ResponseNoData
}

func canonicalDNSMode(mode string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "single":
		return "single", nil
	case "primary_backup":
		return "primary_backup", nil
	case "parallel_race", "race", "brute_force_parallel":
		return "parallel_race", nil
	case "smart_prediction", "prediction":
		return "smart_prediction", nil
	default:
		return "", fmt.Errorf("unsupported DNS mode %q", mode)
	}
}

// ApplyDNSConfig atomically applies the complete Android DNS configuration.
// The JSON form keeps the gomobile API stable as fields are added.
func (e *Engine) ApplyDNSConfig(configJSON string) error {
	var cfg dnsEngineConfig
	decoder := json.NewDecoder(strings.NewReader(configJSON))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&cfg); err != nil {
		return fmt.Errorf("parse DNS config: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("parse DNS config: trailing data")
	}
	if cfg.DynamicResponse.RequestThreshold < 1 {
		cfg.DynamicResponse.RequestThreshold = 5
	}
	if cfg.DynamicResponse.WindowSeconds < 1 {
		cfg.DynamicResponse.WindowSeconds = 60
	}
	if cfg.DynamicResponse.NXDomainSeconds < 1 {
		cfg.DynamicResponse.NXDomainSeconds = 300
	}

	canonMode, err := canonicalDNSMode(cfg.Mode)
	if err != nil {
		return err
	}
	cfg.Mode = canonMode

	e.mu.Lock()
	e.responseType = ParseResponseType(strings.ToUpper(cfg.BlockResponse))
	e.dynamicResponse = cfg.DynamicResponse
	resolver := e.resolver
	e.mu.Unlock()
	e.dynamicBlocks.reset()

	if len(cfg.Providers) == 0 {
		return fmt.Errorf("DNS config has no providers")
	}
	if cfg.Mode == "single" && len(cfg.Providers) != 1 {
		return fmt.Errorf("single DNS mode requires exactly one provider")
	}
	for i := range cfg.Providers {
		cfg.Providers[i].Protocol = strings.ToUpper(cfg.Providers[i].Protocol)
		if err := validateDNSProvider(cfg.Providers[i]); err != nil {
			return fmt.Errorf("provider %d: %w", i, err)
		}
	}
	if resolver != nil {
		resolver.UpdateBootstrap(cfg.Bootstrap)
		if err := resolver.ConfigureProviders(cfg.Mode, cfg.Providers); err != nil {
			return err
		}
	}
	if e.dnsCache != nil {
		e.dnsCache.updatePolicy(cfg.Cache)
	}
	e.mu.Lock()
	e.dnsConfig = &cfg
	e.mu.Unlock()
	return nil
}

func validateDNSProvider(cfg dnsProviderConfig) error {
	switch cfg.Protocol {
	case "PLAIN", "DOT":
		if _, _, err := net.SplitHostPort(cfg.Server); err != nil {
			return fmt.Errorf("invalid %s endpoint %q: %w", cfg.Protocol, cfg.Server, err)
		}
	case "DOH":
		u, err := url.ParseRequestURI(cfg.URL)
		if err != nil || u.Scheme != "https" || u.Host == "" {
			return fmt.Errorf("invalid DOH URL %q", cfg.URL)
		}
	case "DOQ":
		host, port := parseDoQURL(cfg.URL)
		if host == "" || port == "" {
			return fmt.Errorf("invalid DOQ URL %q", cfg.URL)
		}
	default:
		return fmt.Errorf("unsupported protocol %q", cfg.Protocol)
	}
	return nil
}
