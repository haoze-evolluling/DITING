// dns_cache_types.go keeps the Go-visible shapes of the cache: the JSON configuration the Android
// layer sends, the statistics and snapshot models it reads back, and the chain target the engine
// uses to filter CNAME/SVCB answers. The entries themselves live in
// rust/diting-dns-cache-core.

package tunnel

// dnsCacheABIVersion must match `ABI_VERSION` in rust/diting-dns-cache-core/src/ffi.rs.
const dnsCacheABIVersion = 2

// dnsCachePayloadLayoutVersion must match `LAYOUT_VERSION` in
// rust/diting-dns-cache-core/src/payload.rs.
const dnsCachePayloadLayoutVersion = 2

// maxCacheKeyLen bounds a wire-built key: a 255-byte name plus ":65535:65535".
const maxCacheKeyLen = 256 + 12

// Flag bits of the config payload; must match `FLAG_*` in the crate's policy.rs.
const (
	dnsCacheFlagEnabled       = 1 << 0
	dnsCacheFlagMinTTL        = 1 << 1
	dnsCacheFlagStaleFallback = 1 << 2
	dnsCacheFlagNegativeTTL   = 1 << 3
)

// `diting_dns_cache_get` results; must match the crate's ffi.rs.
const (
	dnsCacheGetMiss   = 0
	dnsCacheGetFresh  = 1
	dnsCacheGetStale  = 2
	dnsCacheGetFailed = 3
)

type dnsCacheConfig struct {
	Enabled              bool   `json:"enabled"`
	Mode                 string `json:"mode"`
	MaxTTLSeconds        int64  `json:"maxTtlSeconds"`
	FixedTTLSeconds      int64  `json:"fixedTtlSeconds"`
	MinTTLEnabled        bool   `json:"minTtlEnabled"`
	MinTTLSeconds        int64  `json:"minTtlSeconds"`
	StaleFallbackEnabled bool   `json:"staleFallbackEnabled"`
	StaleFallbackSeconds int64  `json:"staleFallbackSeconds"`
	NegativeTTLEnabled   bool   `json:"negativeTtlEnabled"`
	NegativeTTLSeconds   int64  `json:"negativeTtlSeconds"`
}

type chainTarget struct {
	domain string
	kind   string
}

type dnsCacheStats struct {
	Enabled       bool    `json:"enabled"`
	TotalHits     uint64  `json:"totalHits"`
	TotalMisses   uint64  `json:"totalMisses"`
	StaleHits     uint64  `json:"staleHits"`
	NegativeHits  uint64  `json:"negativeHits"`
	HitRatio      float64 `json:"hitRatio"`
	EntryCount    int     `json:"entryCount"`
	MaxEntries    int     `json:"maxEntries"`
	EvictionCount uint64  `json:"evictionCount"`
}
