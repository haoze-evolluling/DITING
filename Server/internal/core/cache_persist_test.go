package core

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/miekg/dns"
)

// persistTestResponse 构造一条 A 记录应答，TTL 由调用方指定
func persistTestResponse(domain string, ttl uint32, ip string) *dns.Msg {
	resp := new(dns.Msg)
	resp.Response = true
	resp.Rcode = dns.RcodeSuccess
	hdr := dns.RR_Header{Name: dns.Fqdn(domain), Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: ttl}
	resp.Answer = append(resp.Answer, &dns.A{Hdr: hdr, A: net.ParseIP(ip).To4()})
	return resp
}

func persistTestQuery(domain string, qtype uint16) *dns.Msg {
	req := new(dns.Msg)
	req.SetQuestion(dns.Fqdn(domain), qtype)
	return req
}

func newPersistTestCache(t *testing.T, mutate func(*CacheConfig)) *DNSCache {
	t.Helper()
	cfg := DefaultCacheConfig()
	cfg.Mode = "follow_dns_ttl"
	cfg.StaleFallbackEnabled = true
	cfg.StaleFallbackSeconds = 300
	if mutate != nil {
		mutate(&cfg)
	}
	return NewDNSCache(cfg)
}

func TestCachePersist_RoundTrip(t *testing.T) {
	cache := newPersistTestCache(t, nil)
	defer cache.Close()

	req := persistTestQuery("example.com", dns.TypeA)
	cache.Put(req, persistTestResponse("example.com", 600, "1.2.3.4"))

	path := filepath.Join(t.TempDir(), "cache.json")
	if err := cache.SaveToFile(path); err != nil {
		t.Fatalf("SaveToFile: %v", err)
	}

	fresh := newPersistTestCache(t, nil)
	defer fresh.Close()

	restored, err := fresh.LoadFromFile(path)
	if err != nil {
		t.Fatalf("LoadFromFile: %v", err)
	}
	if restored != 1 {
		t.Fatalf("restored = %d, want 1", restored)
	}

	resp, hit, _, _ := fresh.Get(req)
	if !hit || resp == nil {
		t.Fatal("the restored entry must serve a cache hit")
	}
	if len(resp.Answer) != 1 {
		t.Fatalf("answer count = %d, want 1", len(resp.Answer))
	}
	if a, ok := resp.Answer[0].(*dns.A); !ok || a.A.String() != "1.2.3.4" {
		t.Fatalf("unexpected answer payload: %v", resp.Answer[0])
	}
	// 恢复后的剩余 TTL 必须小于原始 TTL：超出部分说明落盘时丢了时间基准
	if resp.Answer[0].Header().Ttl >= 600 {
		t.Fatalf("restored TTL = %d, expected a decayed value", resp.Answer[0].Header().Ttl)
	}
}

func TestCachePersist_NegativeEntryRoundTrip(t *testing.T) {
	cache := newPersistTestCache(t, nil)
	defer cache.Close()

	req := persistTestQuery("nx.example", dns.TypeA)
	neg := new(dns.Msg)
	neg.SetRcode(req, dns.RcodeNameError)
	neg.Ns = append(neg.Ns, &dns.SOA{
		Hdr:     dns.RR_Header{Name: "example.", Rrtype: dns.TypeSOA, Class: dns.ClassINET, Ttl: 30},
		Ns:      "ns.example.",
		Mbox:    "hostmaster.example.",
		Minttl:  30,
		Serial:  1,
		Refresh: 3600,
		Retry:   600,
		Expire:  86400,
	})
	cache.Put(req, neg)

	path := filepath.Join(t.TempDir(), "cache.json")
	if err := cache.SaveToFile(path); err != nil {
		t.Fatalf("SaveToFile: %v", err)
	}

	fresh := newPersistTestCache(t, nil)
	defer fresh.Close()
	restored, err := fresh.LoadFromFile(path)
	if err != nil || restored != 1 {
		t.Fatalf("restored = %d, err = %v", restored, err)
	}

	resp, hit, _, _ := fresh.Get(req)
	if !hit || resp == nil {
		t.Fatal("negative entries must survive a restart")
	}
	if resp.Rcode != dns.RcodeNameError {
		t.Fatalf("rcode = %d, want NXDOMAIN", resp.Rcode)
	}
}

// 落盘时应跳过彻底过期的条目：写出去再读回来只会被立即丢弃
func TestCachePersist_ExpiredEntriesSkipped(t *testing.T) {
	cache := newPersistTestCache(t, func(c *CacheConfig) {
		c.StaleFallbackEnabled = false
		// 关闭最小 TTL 抬升，否则 1 秒的 TTL 会被抬到 60 秒而不会过期
		c.MinTTLEnabled = false
	})
	defer cache.Close()

	req := persistTestQuery("gone.example", dns.TypeA)
	cache.Put(req, persistTestResponse("gone.example", 1, "9.9.9.9"))
	time.Sleep(1100 * time.Millisecond)

	path := filepath.Join(t.TempDir(), "cache.json")
	if err := cache.SaveToFile(path); err != nil {
		t.Fatalf("SaveToFile: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	var payload cachePersistFile
	if err := json.Unmarshal(raw, &payload); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if payload.EntryCount != 0 || len(payload.Entries) != 0 {
		t.Fatalf("expected no entries, got %d", payload.EntryCount)
	}
	if payload.Version != cachePersistVersion {
		t.Fatalf("version = %d, want %d", payload.Version, cachePersistVersion)
	}
}

// 读回时越过陈旧宽限期的条目同样必须丢弃（文件可能已放置很久）
func TestCachePersist_StaleOnLoadDropped(t *testing.T) {
	cache := newPersistTestCache(t, nil)
	defer cache.Close()

	req := persistTestQuery("old.example", dns.TypeA)
	cache.Put(req, persistTestResponse("old.example", 60, "5.5.5.5"))

	path := filepath.Join(t.TempDir(), "cache.json")
	if err := cache.SaveToFile(path); err != nil {
		t.Fatalf("SaveToFile: %v", err)
	}

	// 手工把时间基准整体前移，模拟一份放置了远超宽限期的落盘文件
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	var payload cachePersistFile
	if err := json.Unmarshal(raw, &payload); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	past := time.Now().Add(-24 * time.Hour).UnixMilli()
	for i := range payload.Entries {
		payload.Entries[i].ExpiresAt = past
		payload.Entries[i].StaleUntil = past
	}
	patched, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if err := os.WriteFile(path, patched, 0o600); err != nil {
		t.Fatalf("write patch: %v", err)
	}

	fresh := newPersistTestCache(t, nil)
	defer fresh.Close()
	restored, err := fresh.LoadFromFile(path)
	if err != nil {
		t.Fatalf("LoadFromFile: %v", err)
	}
	if restored != 0 {
		t.Fatalf("restored = %d, want 0", restored)
	}
	if _, hit, _, _ := fresh.Get(req); hit {
		t.Fatal("an expired record must not be served")
	}
}

func TestCachePersist_VersionMismatchRejected(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "cache.json")
	payload := cachePersistFile{Version: cachePersistVersion + 1, SavedAt: time.Now().UnixMilli()}
	raw, _ := json.Marshal(payload)
	if err := os.WriteFile(path, raw, 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}

	cache := newPersistTestCache(t, nil)
	defer cache.Close()
	restored, err := cache.LoadFromFile(path)
	if err == nil {
		t.Fatal("a mismatched version must be reported, not silently accepted")
	}
	if restored != 0 {
		t.Fatalf("restored = %d, want 0", restored)
	}
}

func TestCachePersist_CorruptFileRejected(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cache.json")
	if err := os.WriteFile(path, []byte(`{"version":1,"entries":[`), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}

	cache := newPersistTestCache(t, nil)
	defer cache.Close()
	if _, err := cache.LoadFromFile(path); err == nil {
		t.Fatal("truncated JSON must be reported")
	}
}

// 首次启动：文件不存在是正常情形，不应报错
func TestCachePersist_MissingFileIsNotAnError(t *testing.T) {
	cache := newPersistTestCache(t, nil)
	defer cache.Close()

	restored, err := cache.LoadFromFile(filepath.Join(t.TempDir(), "absent.json"))
	if err != nil {
		t.Fatalf("missing file must not be an error: %v", err)
	}
	if restored != 0 {
		t.Fatalf("restored = %d, want 0", restored)
	}
}

// 容量上限在导入侧同样生效，避免一份被放大的文件撑爆内存
func TestCachePersist_RespectsMaxEntries(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cache.json")

	src := newPersistTestCache(t, nil)
	defer src.Close()
	for i := 0; i < 40; i++ {
		domain := "host" + string(rune('a'+i%26)) + string(rune('a'+i/26)) + ".example"
		req := persistTestQuery(domain, dns.TypeA)
		src.Put(req, persistTestResponse(domain, 600, "10.0.0.1"))
	}
	if err := src.SaveToFile(path); err != nil {
		t.Fatalf("SaveToFile: %v", err)
	}

	small := newPersistTestCache(t, func(c *CacheConfig) {
		c.MaxEntries = NumDNSCacheShards // 每分片恰好 1 条
	})
	defer small.Close()

	restored, err := small.LoadFromFile(path)
	if err != nil {
		t.Fatalf("LoadFromFile: %v", err)
	}
	if restored > NumDNSCacheShards {
		t.Fatalf("restored = %d, exceeding the configured capacity %d", restored, NumDNSCacheShards)
	}
}

func TestCachePersist_SaveCreatesParentDir(t *testing.T) {
	cache := newPersistTestCache(t, nil)
	defer cache.Close()

	path := filepath.Join(t.TempDir(), "nested", "deeper", "cache.json")
	if err := cache.SaveToFile(path); err != nil {
		t.Fatalf("SaveToFile must create the parent directory: %v", err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("stat: %v", err)
	}
	// 临时文件不应残留
	if _, err := os.Stat(path + ".tmp"); !os.IsNotExist(err) {
		t.Fatal("the temp file must be renamed away")
	}
}

// 落盘关闭时不得产生任何文件，也不得在退出时偷偷写盘
func TestCachePersist_DisabledWritesNothing(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "cache.json")

	cache := newPersistTestCache(t, func(c *CacheConfig) {
		c.PersistEnabled = false
		c.PersistPath = path
	})
	req := persistTestQuery("quiet.example", dns.TypeA)
	cache.Put(req, persistTestResponse("quiet.example", 600, "1.1.1.1"))
	cache.Close()

	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("persistence disabled must not write a file, even on shutdown")
	}
}

// 开启落盘时，正常关闭会写一次，且不依赖定时器
func TestCachePersist_ShutdownFlush(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cache.json")
	cache := newPersistTestCache(t, func(c *CacheConfig) {
		c.PersistEnabled = true
		c.PersistPath = path
		c.PersistIntervalSeconds = 3600 // 定时器远未触发
	})

	req := persistTestQuery("flush.example", dns.TypeA)
	cache.Put(req, persistTestResponse("flush.example", 600, "2.2.2.2"))
	cache.Close()

	if _, err := os.Stat(path); err != nil {
		t.Fatalf("shutdown must flush once: %v", err)
	}

	restoredCache := newPersistTestCache(t, nil)
	defer restoredCache.Close()
	restored, err := restoredCache.LoadFromFile(path)
	if err != nil || restored != 1 {
		t.Fatalf("restored = %d, err = %v", restored, err)
	}
}

// persistLoopRunning 反映定时落盘协程是否在运行（仅测试使用）
func (c *DNSCache) persistLoopRunning() bool {
	c.persistMu.Lock()
	defer c.persistMu.Unlock()
	return c.persistStop != nil
}

// 运行时切换落盘开关必须立刻作用于定时器，而不是等下一次重启。
//
// 这里不等待定时器真正触发：落盘间隔下限被刻意设为 30s 以保护磁盘，
// 拿它做实时等待只会让测试变得又慢又脆。协程的启停状态才是这段逻辑的契约。
func TestCachePersist_RuntimeToggleStartsLoop(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cache.json")
	cache := newPersistTestCache(t, func(c *CacheConfig) {
		c.PersistEnabled = false
		c.PersistPath = ""
	})
	defer cache.Close()

	if cache.persistLoopRunning() {
		t.Fatal("the loop must not run while persistence is disabled")
	}

	cfg := cache.GetConfig()
	cfg.PersistEnabled = true
	cfg.PersistPath = path
	cfg.PersistIntervalSeconds = 60
	cache.UpdateConfig(cfg)
	if !cache.persistLoopRunning() {
		t.Fatal("enabling persistence at runtime must start the loop")
	}

	// 关闭后不仅定时器要停，退出时也不能再写盘
	cfg.PersistEnabled = false
	cache.UpdateConfig(cfg)
	if cache.persistLoopRunning() {
		t.Fatal("disabling persistence at runtime must stop the loop")
	}

	req := persistTestQuery("runtime.example", dns.TypeA)
	cache.Put(req, persistTestResponse("runtime.example", 600, "4.4.4.4"))
	cache.Close()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("a disabled cache must not write on shutdown")
	}
}

// 缺省或非法的间隔统一落到默认值，不应出现"开启落盘却从不写盘"
func TestCachePersist_ZeroIntervalFallsBackToDefault(t *testing.T) {
	cache := newPersistTestCache(t, func(c *CacheConfig) {
		c.PersistEnabled = true
		c.PersistPath = filepath.Join(t.TempDir(), "cache.json")
		c.PersistIntervalSeconds = 0
	})
	defer cache.Close()

	if got := cache.GetConfig().PersistIntervalSeconds; got != defaultPersistIntervalSeconds {
		t.Fatalf("interval = %d, want the default %d", got, defaultPersistIntervalSeconds)
	}
	if !cache.persistLoopRunning() {
		t.Fatal("enabling persistence must start the loop even with a zero interval")
	}
}

// 间隔被钳制在 [30, 86400]，避免频繁写盘或形同虚设
func TestCachePersist_IntervalClamped(t *testing.T) {
	cases := map[int64]int64{
		1:      minPersistIntervalSeconds,
		30:     minPersistIntervalSeconds,
		300:    300,
		999999: maxPersistIntervalSeconds,
		-5:     defaultPersistIntervalSeconds,
	}
	for input, want := range cases {
		cache := newPersistTestCache(t, func(c *CacheConfig) {
			c.PersistEnabled = true
			c.PersistPath = filepath.Join(t.TempDir(), "cache.json")
			c.PersistIntervalSeconds = input
		})
		if got := cache.GetConfig().PersistIntervalSeconds; got != want {
			t.Errorf("interval %d clamped to %d, want %d", input, got, want)
		}
		cache.Close()
	}
}

// 落盘文件可能早于当前排除规则生成；恢复时必须重新判定，
// 否则被排除的域名会借着"读回文件"重新占住缓存容量。
func TestCachePersist_SkipsExcludedOnLoad(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cache.json")

	src := newPersistTestCache(t, nil)
	defer src.Close()
	keepReq := persistTestQuery("keep.example", dns.TypeA)
	skipReq := persistTestQuery("skip.example", dns.TypeA)
	src.Put(keepReq, persistTestResponse("keep.example", 600, "1.1.1.1"))
	src.Put(skipReq, persistTestResponse("skip.example", 600, "2.2.2.2"))
	if err := src.SaveToFile(path); err != nil {
		t.Fatalf("SaveToFile: %v", err)
	}

	dst := newPersistTestCache(t, func(c *CacheConfig) {
		c.ExcludePatterns = []string{`^skip\.`}
	})
	defer dst.Close()

	restored, err := dst.LoadFromFile(path)
	if err != nil {
		t.Fatalf("LoadFromFile: %v", err)
	}
	if restored != 1 {
		t.Fatalf("restored = %d, want 1 (the excluded entry must be dropped)", restored)
	}
	if _, hit, _, _ := dst.Get(keepReq); !hit {
		t.Fatal("a non-excluded entry must still be restored")
	}
	if _, hit, _, _ := dst.Get(skipReq); hit {
		t.Fatal("an excluded domain must not come back through the persist file")
	}
}

func TestCachePersist_PathHelper(t *testing.T) {
	if got := CachePersistPath(""); got != "" {
		t.Fatalf("empty data dir must yield an empty path, got %q", got)
	}
	got := CachePersistPath(filepath.Join("var", "data"))
	want := filepath.Join("var", "data", DefaultCachePersistFileName)
	if got != want {
		t.Fatalf("CachePersistPath = %q, want %q", got, want)
	}
}

// 分组键必须原样保留：落盘再读回不能把分组隔离抹平
func TestCachePersist_GroupKeysPreserved(t *testing.T) {
	cache := newPersistTestCache(t, nil)
	defer cache.Close()

	req := persistTestQuery("grouped.example", dns.TypeA)
	cache.PutForGroup(req, persistTestResponse("grouped.example", 600, "3.3.3.3"), "kids")

	path := filepath.Join(t.TempDir(), "cache.json")
	if err := cache.SaveToFile(path); err != nil {
		t.Fatalf("SaveToFile: %v", err)
	}

	fresh := newPersistTestCache(t, nil)
	defer fresh.Close()
	if _, err := fresh.LoadFromFile(path); err != nil {
		t.Fatalf("LoadFromFile: %v", err)
	}

	if _, hit, _, _ := fresh.GetForGroup(req, "kids"); !hit {
		t.Fatal("the group-scoped entry must be restorable")
	}
	if _, hit, _, _ := fresh.GetForGroup(req, DefaultClientGroupID); hit {
		t.Fatal("reloading must not leak a group-scoped entry into the default group")
	}
}
