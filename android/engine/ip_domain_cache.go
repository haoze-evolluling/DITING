package tunnel

import (
	"container/list"
	"sync"
)

type ipDomainEntry struct {
	ip     string
	domain string
}

type ipDomainCache struct {
	mu      sync.RWMutex
	entries map[string]*list.Element
	lru     *list.List
	maxSize int
}

func newIPDomainCache(maxSize int) *ipDomainCache {
	if maxSize <= 0 {
		maxSize = 2048
	}
	return &ipDomainCache{
		entries: make(map[string]*list.Element, maxSize),
		lru:     list.New(),
		maxSize: maxSize,
	}
}

func (c *ipDomainCache) put(ip string, domain string) {
	if c == nil || ip == "" || domain == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()

	if elem, exists := c.entries[ip]; exists {
		elem.Value.(*ipDomainEntry).domain = domain
		c.lru.MoveToFront(elem)
		return
	}

	if c.lru.Len() >= c.maxSize {
		back := c.lru.Back()
		if back != nil {
			c.lru.Remove(back)
			delete(c.entries, back.Value.(*ipDomainEntry).ip)
		}
	}

	elem := c.lru.PushFront(&ipDomainEntry{ip: ip, domain: domain})
	c.entries[ip] = elem
}

func (c *ipDomainCache) get(ip string) string {
	if c == nil || ip == "" {
		return ""
	}
	c.mu.RLock()
	defer c.mu.RUnlock()

	if elem, exists := c.entries[ip]; exists {
		return elem.Value.(*ipDomainEntry).domain
	}
	return ""
}

