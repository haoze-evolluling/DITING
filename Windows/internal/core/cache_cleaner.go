package core

import "time"

func (c *DNSCache) startCleaner() {
	ticker := time.NewTicker(30 * time.Second)
	go func() {
		for {
			select {
			case <-c.stopCleaner:
				ticker.Stop()
				return
			case now := <-ticker.C:
				c.cleanupExpired(now)
			}
		}
	}()
}

func (c *DNSCache) cleanupExpired(now time.Time) {
	for _, shard := range c.shards {
		shard.mu.Lock()
		for key, entry := range shard.entries {
			if entry != nil && now.After(entry.staleUntil) {
				delete(shard.entries, key)
				if entry.elem != nil {
					shard.lruList.Remove(entry.elem)
					entry.elem = nil
				}
				c.evictions.Add(1)
			}
		}
		shard.mu.Unlock()
	}
}
