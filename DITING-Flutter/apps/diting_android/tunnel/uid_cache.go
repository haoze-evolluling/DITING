// uid_cache.go memoizes the JNI-backed flow-owner and package lookups.
//
// Why it exists:
// - One TCP flow used to cross the JNI boundary for the same 5-tuple up to 4-6 times (stack dispatch,
//   flow handler, connection log, app-name lookup, every MITM HTTP event). Each crossing allocated two
//   IP strings in Go plus an InetAddress parse and a data-class key in Kotlin.
// - The flow cache is keyed by a value-type 5-tuple, so a hit allocates nothing. TTLs are short (the
//   Kotlin side keeps its own longer cache) so port reuse cannot leak an owner across flows in practice.
// - Package names are cached per UID; empty answers are never cached, matching the Kotlin cache.

package tunnel

import (
	"net/netip"
	"sync"
	"time"
)

const (
	flowUIDCacheTTL         = 2 * time.Second
	flowUIDNegativeCacheTTL = 500 * time.Millisecond
	flowUIDCacheMaxEntries  = 1024

	uidPackageCacheTTL        = 60 * time.Second
	uidPackageCacheMaxEntries = 256
)

type flowUIDKey struct {
	appIP      netip.Addr
	serverIP   netip.Addr
	appPort    uint16
	serverPort uint16
	protocol   uint8
}

type cachedFlowUID struct {
	uid     int
	expires time.Time
}

// cachingUIDResolver wraps the platform UIDResolver. resolveFlowUID recognises it and takes the
// allocation-free path; direct ResolveUID calls pass straight through.
type cachingUIDResolver struct {
	inner   UIDResolver
	mu      sync.Mutex
	entries map[flowUIDKey]cachedFlowUID
}

func newCachingUIDResolver(inner UIDResolver) UIDResolver {
	if inner == nil {
		return nil
	}
	if c, ok := inner.(*cachingUIDResolver); ok {
		return c
	}
	return &cachingUIDResolver{inner: inner, entries: make(map[flowUIDKey]cachedFlowUID)}
}

func (c *cachingUIDResolver) ResolveUID(protocol int, localIP string, localPort int, remoteIP string, remotePort int) int {
	return c.inner.ResolveUID(protocol, localIP, localPort, remoteIP, remotePort)
}

func (c *cachingUIDResolver) resolveFlow(protocol int, id flowID) int {
	appAddr, okApp := netip.AddrFromSlice(id.appIP)
	serverAddr, okServer := netip.AddrFromSlice(id.serverIP)
	if !okApp || !okServer {
		return c.inner.ResolveUID(protocol, id.appIP.String(), id.appPort, id.serverIP.String(), id.serverPort)
	}
	key := flowUIDKey{
		appIP:      appAddr,
		serverIP:   serverAddr,
		appPort:    uint16(id.appPort),
		serverPort: uint16(id.serverPort),
		protocol:   uint8(protocol),
	}

	now := time.Now()
	c.mu.Lock()
	if entry, ok := c.entries[key]; ok && now.Before(entry.expires) {
		c.mu.Unlock()
		return entry.uid
	}
	c.mu.Unlock()

	uid := c.inner.ResolveUID(protocol, id.appIP.String(), id.appPort, id.serverIP.String(), id.serverPort)

	ttl := flowUIDCacheTTL
	if uid == UIDUnknown || uid <= 0 {
		ttl = flowUIDNegativeCacheTTL
	}
	c.mu.Lock()
	if len(c.entries) >= flowUIDCacheMaxEntries {
		c.pruneLocked(now)
	}
	c.entries[key] = cachedFlowUID{uid: uid, expires: now.Add(ttl)}
	c.mu.Unlock()
	return uid
}

// pruneLocked drops expired entries; if every entry is still live the map is reset, which only costs
// one extra JNI lookup per active flow.
func (c *cachingUIDResolver) pruneLocked(now time.Time) {
	for k, v := range c.entries {
		if !now.Before(v.expires) {
			delete(c.entries, k)
		}
	}
	if len(c.entries) >= flowUIDCacheMaxEntries {
		c.entries = make(map[flowUIDKey]cachedFlowUID)
	}
}

type cachedPackage struct {
	name    string
	expires time.Time
}

// cachingAppUidResolver memoizes UID -> package name lookups.
type cachingAppUidResolver struct {
	inner   AppUidResolver
	mu      sync.Mutex
	entries map[int]cachedPackage
}

func newCachingAppUidResolver(inner AppUidResolver) AppUidResolver {
	if inner == nil {
		return nil
	}
	if c, ok := inner.(*cachingAppUidResolver); ok {
		return c
	}
	return &cachingAppUidResolver{inner: inner, entries: make(map[int]cachedPackage)}
}

func (c *cachingAppUidResolver) PackageForUid(uid int) string {
	now := time.Now()
	c.mu.Lock()
	if entry, ok := c.entries[uid]; ok && now.Before(entry.expires) {
		c.mu.Unlock()
		return entry.name
	}
	c.mu.Unlock()

	name := c.inner.PackageForUid(uid)
	if name == "" {
		return name
	}
	c.mu.Lock()
	if len(c.entries) >= uidPackageCacheMaxEntries {
		c.entries = make(map[int]cachedPackage)
	}
	c.entries[uid] = cachedPackage{name: name, expires: now.Add(uidPackageCacheTTL)}
	c.mu.Unlock()
	return name
}
