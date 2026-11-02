package core

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/miekg/dns"
)

// cachePersistVersion 为落盘格式版本。
//
// 读取时严格比对：版本不符即整体丢弃并当作空缓存。
// 与其猜测旧字段的语义做兼容，不如让冷启动少一次命中——
// 猜测错误会以"缓存里躺着错误的应答"这种最难排查的形式暴露出来。
const cachePersistVersion = 1

// cachePersistFile 为落盘的顶层结构
type cachePersistFile struct {
	Version    int                  `json:"version"`
	SavedAt    int64                `json:"savedAt"`
	EntryCount int                  `json:"entryCount"`
	MaxEntries int                  `json:"maxEntries"`
	ConfigHash string               `json:"configHash,omitempty"`
	Entries    []cachePersistRecord `json:"entries"`
}

// cachePersistRecord 为单条缓存条目的落盘形态
type cachePersistRecord struct {
	// Key 为完整的缓存键（含客户端分组后缀），落盘后无需重新推导
	Key         string   `json:"key"`
	Domain      string   `json:"domain"`
	QType       uint16   `json:"qtype"`
	QClass      uint16   `json:"qclass"`
	Message     []byte   `json:"message"`
	OriginalTTL uint32   `json:"originalTtl"`
	ExpiresAt   int64    `json:"expiresAt"`
	StaleUntil  int64    `json:"staleUntil"`
	IsNegative  bool     `json:"isNegative"`
	Rcode       int      `json:"rcode"`
	IPList      []string `json:"ipList,omitempty"`
	HitCount    uint64   `json:"hitCount"`
	LastHitAt   int64    `json:"lastHitAt"`
}

// SaveToFile 把当前缓存原子化落盘。
//
// 采用「临时文件 + rename」：进程在写入中途被杀只会留下一个临时文件，
// 不会让主文件处于半截状态——冷启动时读到一个截断的 JSON
// 会让整份缓存被丢弃，而这恰恰是该功能最需要可靠的时刻。
func (c *DNSCache) SaveToFile(path string) error {
	if c == nil || path == "" {
		return fmt.Errorf("cache persist: empty path")
	}

	records := c.snapshotForPersist()
	payload := cachePersistFile{
		Version:    cachePersistVersion,
		SavedAt:    time.Now().UnixMilli(),
		EntryCount: len(records),
		MaxEntries: c.MaxEntries(),
		Entries:    records,
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("cache persist: marshal: %w", err)
	}

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("cache persist: create dir: %w", err)
	}

	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return fmt.Errorf("cache persist: write temp: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("cache persist: rename: %w", err)
	}
	return nil
}

// LoadFromFile 从落盘文件恢复缓存。
//
// 返回恢复的条目数。文件不存在不算错误（首次启动的正常情形）；
// 文件损坏或版本不符时返回 0 与一个说明性错误，调用方据此决定是否继续启动。
func (c *DNSCache) LoadFromFile(path string) (int, error) {
	if c == nil || path == "" {
		return 0, fmt.Errorf("cache load: empty path")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, nil
		}
		return 0, fmt.Errorf("cache load: read: %w", err)
	}

	var payload cachePersistFile
	if err := json.Unmarshal(data, &payload); err != nil {
		return 0, fmt.Errorf("cache load: unmarshal: %w", err)
	}
	if payload.Version != cachePersistVersion {
		return 0, fmt.Errorf("cache load: unsupported version %d (want %d)", payload.Version, cachePersistVersion)
	}

	now := time.Now()
	limit := c.MaxEntries()
	if limit <= 0 {
		limit = DefaultMaxCacheEntries
	}

	restored := 0
	// 按记录顺序导入，超出容量时由分片 LRU 自然淘汰最早写入者
	for _, rec := range payload.Entries {
		if restored >= limit {
			break
		}
		entry, ok := c.entryFromRecord(rec, now)
		if !ok {
			continue
		}
		if c.insertEntry(entry) {
			restored++
		}
	}
	return restored, nil
}

// entryFromRecord 把一条落盘记录还原为内存条目；已彻底过期者返回 false
func (c *DNSCache) entryFromRecord(rec cachePersistRecord, now time.Time) (*cacheEntry, bool) {
	if rec.Key == "" || len(rec.Message) == 0 {
		return nil, false
	}

	expiresAt := time.UnixMilli(rec.ExpiresAt)
	staleUntil := time.UnixMilli(rec.StaleUntil)
	// 连陈旧宽限期都已越过：这条记录再也派不上用场
	if !now.Before(staleUntil) {
		return nil, false
	}

	msg := new(dns.Msg)
	if err := msg.Unpack(rec.Message); err != nil {
		return nil, false
	}

	effectiveTTL := time.Duration(rec.OriginalTTL) * time.Second
	if rec.OriginalTTL == 0 {
		effectiveTTL = time.Until(expiresAt)
	}

	entry := &cacheEntry{
		key:          rec.Key,
		domain:       rec.Domain,
		qtype:        rec.QType,
		qclass:       rec.QClass,
		msg:          msg,
		originalTTL:  rec.OriginalTTL,
		effectiveTTL: effectiveTTL,
		createdAt:    now,
		expiresAt:    expiresAt,
		staleUntil:   staleUntil,
		isNegative:   rec.IsNegative,
		rcode:        rec.Rcode,
		ipList:       rec.IPList,
	}
	entry.hitCount.Store(rec.HitCount)
	entry.lastHitAt.Store(rec.LastHitAt)
	return entry, true
}

// snapshotForPersist 采集当前全部有效条目（调用方无需持锁）
func (c *DNSCache) snapshotForPersist() []cachePersistRecord {
	now := time.Now()
	out := make([]cachePersistRecord, 0, 256)

	for _, shard := range c.shards {
		if shard == nil {
			continue
		}
		shard.mu.RLock()
		for _, entry := range shard.entries {
			if entry == nil || entry.msg == nil {
				continue
			}
			// 跳过已过期的条目：落盘再读回来只会被立即丢弃
			if !now.Before(entry.staleUntil) {
				continue
			}
			raw, err := entry.msg.Pack()
			if err != nil {
				continue
			}
			out = append(out, cachePersistRecord{
				Key:         entry.key,
				Domain:      entry.domain,
				QType:       entry.qtype,
				QClass:      entry.qclass,
				Message:     raw,
				OriginalTTL: entry.originalTTL,
				ExpiresAt:   entry.expiresAt.UnixMilli(),
				StaleUntil:  entry.staleUntil.UnixMilli(),
				IsNegative:  entry.isNegative,
				Rcode:       entry.rcode,
				IPList:      entry.ipList,
				HitCount:    entry.hitCount.Load(),
				LastHitAt:   entry.lastHitAt.Load(),
			})
		}
		shard.mu.RUnlock()
	}
	return out
}

// insertEntry 把还原出的条目写回对应分片，与 Put 共用同一套 LRU 淘汰规则
func (c *DNSCache) insertEntry(entry *cacheEntry) bool {
	if entry == nil {
		return false
	}

	// 落盘文件可能早于当前排除规则生成。这里补一次判定，
	// 否则"被排除的域名仍占着缓存容量"会绕过中间件短路重新出现。
	if c.IsExcluded(entry.domain) {
		return false
	}

	shard := c.shard(entry.key)
	shard.mu.Lock()
	defer shard.mu.Unlock()

	if old, exists := shard.entries[entry.key]; exists {
		if old.elem != nil {
			shard.lruList.Remove(old.elem)
			old.elem = nil
		}
		delete(shard.entries, entry.key)
	} else if len(shard.entries) >= shard.maxEntries {
		back := shard.lruList.Back()
		if back != nil {
			oldest := back.Value.(*cacheEntry)
			shard.lruList.Remove(back)
			if oldest != nil {
				oldest.elem = nil
				delete(shard.entries, oldest.key)
				c.evictions.Add(1)
			}
		}
	}

	entry.elem = shard.lruList.PushFront(entry)
	shard.entries[entry.key] = entry
	return true
}

// CachePersistPath 返回默认的缓存落盘路径。
//
// 放在数据目录而非配置目录：它是可再生的运行态数据，删除后仅损失一次冷启动命中。
func CachePersistPath(dataDir string) string {
	if dataDir == "" {
		return ""
	}
	return filepath.Join(dataDir, DefaultCachePersistFileName)
}

// DefaultCachePersistFileName 默认缓存落盘文件名
const DefaultCachePersistFileName = "dns_cache.json"
