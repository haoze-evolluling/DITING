// dns_config.go parses and models DNS configuration JSON payloads received from Android Kotlin,
// translating user settings into structured DNSProtocol types, provider endpoints, and fallback configurations.

package tunnel

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"
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

// ApplyDNSConfig decodes one settings snapshot and, when rust/diting-config-core accepts it,
// publishes it. The kernel owns the mode aliases, the dynamic-block defaults and the endpoint rules,
// and it reports the first problem in the order this function used to check them (mode, provider
// count, then each provider), so the error text and its precedence are unchanged.
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

	normalized, err := normalizeDNSConfig(cfg.Mode, cfg.BlockResponse, cfg.DynamicResponse, cfg.Providers)
	if err != nil {
		return err
	}
	cfg.Mode = normalized.mode
	cfg.Providers = normalized.providers
	cfg.DynamicResponse = normalized.dynamic

	e.mu.Lock()
	resolver := e.resolver
	e.mu.Unlock()

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
	e.storeBlockResponseType(normalized.blockResponse)
	e.mu.Lock()
	e.dynamicResponse = cfg.DynamicResponse
	dyn := cfg.DynamicResponse
	e.dynamicRespView.Store(&dyn)
	e.dnsConfig = &cfg
	e.mu.Unlock()
	e.dynamicBlocks.reset()
	return nil
}
