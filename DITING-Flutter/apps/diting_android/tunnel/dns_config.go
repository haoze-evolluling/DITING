// dns_config.go parses and models DNS configuration JSON payloads received from Android Kotlin,
// translating user settings into structured DNSProtocol types, provider endpoints, and fallback configurations.

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
	RaceMaxParallel int                 `json:"raceMaxParallel,omitempty"`
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
	resolver := e.resolver
	e.mu.Unlock()

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
		if err := resolver.ConfigureProvidersWithOptions(cfg.Mode, cfg.Providers, cfg.RaceMaxParallel); err != nil {
			return err
		}
	}
	if e.dnsCache != nil {
		e.dnsCache.updatePolicy(cfg.Cache)
	}

	// Publish the new policy only after every validation step above has passed.
	// The block response mode and the dynamic block config used to be applied
	// before the provider checks, so a rejected snapshot still changed how
	// blocks were answered while the caller saw an error.
	e.storeBlockResponseType(ParseResponseType(strings.ToUpper(cfg.BlockResponse)))
	e.mu.Lock()
	e.dynamicResponse = cfg.DynamicResponse
	dyn := cfg.DynamicResponse
	e.dynamicRespView.Store(&dyn)
	e.dnsConfig = &cfg
	e.mu.Unlock()
	e.dynamicBlocks.reset()
	return nil
}

func validateDNSProvider(cfg dnsProviderConfig) error {
	switch cfg.Protocol {
	case "PLAIN", "DOT":
		host, _, err := net.SplitHostPort(cfg.Server)
		if err != nil {
			return fmt.Errorf("invalid %s endpoint %q: %w", cfg.Protocol, cfg.Server, err)
		}
		// SplitHostPort accepts "[1.1.1.1:53]:53" as host "1.1.1.1:53". Only a
		// real IPv6 literal may contain a colon after splitting, so anything
		// else means the address itself had a port appended and cannot dial.
		if host == "" || (strings.Contains(host, ":") && net.ParseIP(host) == nil) {
			return fmt.Errorf("invalid %s endpoint %q: host is not a valid IP literal", cfg.Protocol, cfg.Server)
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
