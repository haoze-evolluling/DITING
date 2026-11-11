package core

// resizeCapacity 按新的总容量重算分片上限，超限分片就地按 LRU 收缩。
//
// 调低容量时立即淘汰超出的条目（而非等下一次写入才逐个挤掉），
// 这样 Stats 与内存占用在保存后立刻反映新上限。
func (c *DNSCache) resizeCapacity(maxEntries int) {
	if maxEntries <= 0 {
		maxEntries = DefaultMaxCacheEntries
	}
	perShard := maxEntries / NumDNSCacheShards
	if perShard <= 0 {
		perShard = 1
	}
	c.capacityMu.Lock()
	c.maxEntries = maxEntries
	c.capacityMu.Unlock()

	for _, shard := range c.shards {
		if shard == nil {
			continue
		}
		shard.mu.Lock()
		shard.maxEntries = perShard
		for len(shard.entries) > perShard {
			back := shard.lruList.Back()
			if back == nil {
				break
			}
			oldest := back.Value.(*cacheEntry)
			shard.lruList.Remove(back)
			if oldest != nil {
				oldest.elem = nil
				delete(shard.entries, oldest.key)
				c.evictions.Add(1)
			}
		}
		shard.mu.Unlock()
	}
}

// MaxEntries 返回当前生效的缓存容量上限。
func (c *DNSCache) MaxEntries() int {
	c.capacityMu.RLock()
	defer c.capacityMu.RUnlock()
	return c.maxEntries
}
