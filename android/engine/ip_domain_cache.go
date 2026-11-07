// ip_domain_cache.go remembers which domain resolved to which address, so a flow that dials a
// hard-coded IP can still be labelled with a hostname in the MITM passthrough path.
//
// The LRU itself lives in the Rust kernel (rust/diting-ipcache-core): the map, the recency order,
// the in-place update + move-to-front, eviction of the least-recently-written entry and the
// default capacity. `get` never promotes. Go keeps only the handle; a missing kernel disables the
// hints (every lookup misses), which never changes an answer.

package tunnel

// ipDomainCache owns one kernel handle.
type ipDomainCache struct {
	kernel *nativeIPDomainCache
}

func newIPDomainCache(maxSize int) *ipDomainCache {
	cache := &ipDomainCache{}
	if kernel, err := newNativeIPDomainCache(maxSize); err == nil {
		cache.kernel = kernel
	}
	return cache
}

func (c *ipDomainCache) put(ip string, domain string) {
	if c == nil || c.kernel == nil {
		return
	}
	c.kernel.put(ip, domain)
}

func (c *ipDomainCache) get(ip string) string {
	if c == nil || c.kernel == nil {
		return ""
	}
	return c.kernel.get(ip)
}

// size reports the current entry count (test/telemetry helper).
func (c *ipDomainCache) size() int {
	if c == nil || c.kernel == nil {
		return 0
	}
	return c.kernel.len()
}
