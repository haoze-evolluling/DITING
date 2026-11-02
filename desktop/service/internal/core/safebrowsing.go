package core

import (
	"container/list"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
	"golang.org/x/net/publicsuffix"
)

// 哈希前缀查询的固定参数，与 AdGuard 的服务端约定一致。
const (
	// hashPrefixLen 前缀字节数；查询名由每个前缀的十六进制形式拼成标签
	hashPrefixLen = 2
	// hashSize SHA-256 摘要长度
	hashSize = sha256.Size
	// hashHexSize 摘要的十六进制长度，也是应答 TXT 内容的合法长度
	hashHexSize = hashSize * 2
	// hashSubDomainNum 参与哈希的子域层数上限（含 eTLD+1 自身）
	hashSubDomainNum = 4

	// SafeBrowsingSuffix 恶意网址库的 TXT 查询后缀
	SafeBrowsingSuffix = "sb.dns.adguard.com."
	// ParentalControlSuffix 家长控制的 TXT 查询后缀
	ParentalControlSuffix = "pc.dns.adguard.com."

	// ReasonSafeBrowsing 查询日志中的命中原由
	ReasonSafeBrowsing = "SAFE_BROWSING"
	// ReasonParentalControl 查询日志中的命中原由
	ReasonParentalControl = "PARENTAL_CONTROL"
)

// 声誉查询的默认参数
const (
	DefaultSafeBrowsingTimeoutMs = 3000
	DefaultSafeBrowsingCacheSize = 10000
	DefaultSafeBrowsingCacheTTL  = 600 // 秒
)

// SafeBrowsingConfig 恶意网址库与家长控制配置
type SafeBrowsingConfig struct {
	// Enabled 恶意网址库（Safe Browsing）
	Enabled bool `json:"enabled"`
	// ParentalEnabled 家长控制（色情/暴力等成人内容分类）
	ParentalEnabled bool `json:"parentalEnabled"`
	// TimeoutMs 单次哈希前缀查询的超时（毫秒）
	TimeoutMs int `json:"timeoutMs"`
	// CacheSize 哈希前缀缓存条目数上限
	CacheSize int `json:"cacheSize"`
	// CacheTTLSeconds 缓存有效期（秒）
	CacheTTLSeconds int `json:"cacheTTLSeconds"`
}

// DefaultSafeBrowsingConfig 返回默认配置（默认全部关闭）
//
// 关闭是刻意的：开启后每一次新域名的解析都会附带一次发往第三方的
// 哈希前缀查询，是否接受这一隐私代价应当由用户自己决定。
func DefaultSafeBrowsingConfig() SafeBrowsingConfig {
	return SafeBrowsingConfig{
		Enabled:         false,
		ParentalEnabled: false,
		TimeoutMs:       DefaultSafeBrowsingTimeoutMs,
		CacheSize:       DefaultSafeBrowsingCacheSize,
		CacheTTLSeconds: DefaultSafeBrowsingCacheTTL,
	}
}

// NormalizeSafeBrowsingConfig 校验与修补配置默认值
func NormalizeSafeBrowsingConfig(cfg *SafeBrowsingConfig) {
	if cfg == nil {
		return
	}
	if cfg.TimeoutMs < 100 || cfg.TimeoutMs > 30000 {
		cfg.TimeoutMs = DefaultSafeBrowsingTimeoutMs
	}
	if cfg.CacheSize < 0 {
		cfg.CacheSize = 0
	}
	if cfg.CacheTTLSeconds <= 0 {
		cfg.CacheTTLSeconds = DefaultSafeBrowsingCacheTTL
	}
}

// SafeBrowsingVerdict 一次声誉查询的结论。
//
// Blocked 与 Failed 必须分开看：前者是「查到了，确实该拦」，
// 后者是「没查到，因为根本问不到」。把失败当成命中会让上游一抖动
// 就整网断解析；当成未命中又会让攻击者靠制造失败来绕过。
// 本项目的取舍是失败即放行（fail-open），并如实记录。
type SafeBrowsingVerdict struct {
	Blocked bool
	Service string
	Failed  bool
	Err     error
}

// SafeBrowsingStats 声誉查询的累计统计
type SafeBrowsingStats struct {
	CacheHits   int64 `json:"cacheHits"`
	CacheMisses int64 `json:"cacheMisses"`
	Lookups     int64 `json:"lookups"`
	Failures    int64 `json:"failures"`
	Blocked     int64 `json:"blocked"`
}

// hostnameHash 单个域名的 SHA-256 摘要
type hostnameHash [hashSize]byte

// hashPrefix 摘要的前缀，也是缓存与查询名的键
type hashPrefix [hashPrefixLen]byte

// SafeBrowsingEngine 恶意网址库与家长控制引擎。
//
// 机制与 AdGuard Home 的 hashprefix 插件相同：把域名及其各级父域做
// SHA-256，取前 2 字节的十六进制拼成查询名发往第三方权威服务器，
// 对方返回命中的完整摘要；本地再与请求过的摘要逐一比对。
// 传输过程中第三方只看到 2 字节前缀，无法还原完整域名。
type SafeBrowsingEngine struct {
	mu       sync.RWMutex
	enabled  bool
	parental bool
	timeout  time.Duration
	resolver Resolver

	sb *hashChecker
	pc *hashChecker

	statsMu    sync.Mutex
	cacheHits  int64
	cacheMiss  int64
	lookups    int64
	failures   int64
	blockedCnt int64
}

// hashChecker 单个服务（恶意网址库或家长控制）的前缀检查器
type hashChecker struct {
	// service 用于查询日志与统计归属
	service string
	// suffix 该服务的 TXT 查询后缀
	suffix string
	cache  *hashCache
}

// NewSafeBrowsingEngine 创建声誉查询引擎
//
// resolver 用于发出哈希前缀查询；为 nil 时引擎始终返回失败（即放行），
// 这样在上游尚未装配完成的启动阶段不会误拦。
func NewSafeBrowsingEngine(cfg SafeBrowsingConfig, resolver Resolver) *SafeBrowsingEngine {
	NormalizeSafeBrowsingConfig(&cfg)
	cacheSize := cfg.CacheSize
	ttl := time.Duration(cfg.CacheTTLSeconds) * time.Second

	return &SafeBrowsingEngine{
		enabled:  cfg.Enabled,
		parental: cfg.ParentalEnabled,
		timeout:  time.Duration(cfg.TimeoutMs) * time.Millisecond,
		resolver: resolver,
		sb: &hashChecker{
			service: ReasonSafeBrowsing,
			suffix:  SafeBrowsingSuffix,
			cache:   newHashCache(cacheSize, ttl),
		},
		pc: &hashChecker{
			service: ReasonParentalControl,
			suffix:  ParentalControlSuffix,
			cache:   newHashCache(cacheSize, ttl),
		},
	}
}

// IsEnabled 检查是否有任一服务处于启用状态
func (e *SafeBrowsingEngine) IsEnabled() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.enabled || e.parental
}

// Configure 更新配置
//
// 缓存容量与有效期变化时整体重建缓存：存量条目按旧规则写入，
// 沿用它们会让新旧 TTL 混在一起，不如清空后重新收敛。
func (e *SafeBrowsingEngine) Configure(cfg SafeBrowsingConfig) {
	NormalizeSafeBrowsingConfig(&cfg)

	e.mu.Lock()
	defer e.mu.Unlock()

	ttl := time.Duration(cfg.CacheTTLSeconds) * time.Second
	if e.sb.cache.size != cfg.CacheSize || e.sb.cache.ttl != ttl {
		e.sb.cache = newHashCache(cfg.CacheSize, ttl)
		e.pc.cache = newHashCache(cfg.CacheSize, ttl)
	}
	e.enabled = cfg.Enabled
	e.parental = cfg.ParentalEnabled
	e.timeout = time.Duration(cfg.TimeoutMs) * time.Millisecond
}

// SetResolver 装配上游解析器（启动顺序上解析器可能晚于本引擎就绪）
func (e *SafeBrowsingEngine) SetResolver(resolver Resolver) {
	e.mu.Lock()
	e.resolver = resolver
	e.mu.Unlock()
}

// Stats 返回累计统计
func (e *SafeBrowsingEngine) Stats() SafeBrowsingStats {
	e.statsMu.Lock()
	defer e.statsMu.Unlock()
	return SafeBrowsingStats{
		CacheHits:   e.cacheHits,
		CacheMisses: e.cacheMiss,
		Lookups:     e.lookups,
		Failures:    e.failures,
		Blocked:     e.blockedCnt,
	}
}

// Check 查询该域名是否被任一启用的服务标记。
//
// 先查恶意网址库再查家长控制：两者命中都会拦截，但前者更严重，
// 日志里优先归因于它更有诊断价值。
func (e *SafeBrowsingEngine) Check(ctx context.Context, host string) SafeBrowsingVerdict {
	e.mu.RLock()
	sbOn := e.enabled
	pcOn := e.parental
	sb := e.sb
	pc := e.pc
	timeout := e.timeout
	resolver := e.resolver
	e.mu.RUnlock()

	if !sbOn && !pcOn {
		return SafeBrowsingVerdict{}
	}

	host = normalizeCheckHost(host)
	if host == "" {
		return SafeBrowsingVerdict{}
	}
	if resolver == nil {
		e.recordFailure()
		return SafeBrowsingVerdict{Failed: true, Err: fmt.Errorf("上游解析器尚未就绪")}
	}

	hashes := hostnameToHashes(host)
	if len(hashes) == 0 {
		return SafeBrowsingVerdict{}
	}

	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	if sbOn {
		if v := e.checkWith(ctx, sb, resolver, hashes); v.Blocked || v.Failed {
			return v
		}
	}
	if pcOn {
		return e.checkWith(ctx, pc, resolver, hashes)
	}
	return SafeBrowsingVerdict{}
}

// checkWith 用单个服务核对一组摘要
func (e *SafeBrowsingEngine) checkWith(ctx context.Context, c *hashChecker, resolver Resolver, hashes []hostnameHash) SafeBrowsingVerdict {
	found, blocked, needQuery := c.cache.lookup(hashes)
	if found {
		e.record(true, blocked)
		if blocked {
			return SafeBrowsingVerdict{Blocked: true, Service: c.service}
		}
		return SafeBrowsingVerdict{}
	}

	resp, err := resolver.Exchange(ctx, buildHashQuestion(needQuery, c.suffix))
	if err != nil {
		e.recordFailure()
		return SafeBrowsingVerdict{Failed: true, Err: err}
	}

	received := collectHashes(resp)
	c.cache.store(needQuery, received)

	blocked = matchesAny(needQuery, received)
	e.record(false, blocked)
	if blocked {
		return SafeBrowsingVerdict{Blocked: true, Service: c.service}
	}
	return SafeBrowsingVerdict{}
}

// record 记账一次结论；fromCache 与 blocked 分开传，是因为
// 「命中缓存」与「判定为拦截」是两件互不蕴含的事。
func (e *SafeBrowsingEngine) record(fromCache, blocked bool) {
	e.statsMu.Lock()
	if fromCache {
		e.cacheHits++
	} else {
		e.cacheMiss++
	}
	e.lookups++
	if blocked {
		e.blockedCnt++
	}
	e.statsMu.Unlock()
}

func (e *SafeBrowsingEngine) recordFailure() {
	e.statsMu.Lock()
	e.failures++
	e.statsMu.Unlock()
}

// normalizeCheckHost 归一化待检查的主机名；无效时返回空串
func normalizeCheckHost(host string) string {
	host = strings.ToLower(strings.TrimSpace(host))
	host = strings.Trim(host, ".")
	if host == "" {
		return ""
	}
	if _, ok := dns.IsDomainName(dns.Fqdn(host)); !ok {
		return ""
	}
	return host
}

// hostnameToHashes 计算需要核对的摘要集合。
//
// 覆盖 eTLD+1 及其之上最多 4 层子域：太少会漏掉「整站被封但子域未被
// 单独收录」的情况，太多则每查一个域名都要多带几个前缀标签，浪费报文。
// 公共后缀本身不参与——封 .com 没有意义，服务端也不收录。
func hostnameToHashes(host string) []hostnameHash {
	// 非 ICANN 后缀（如 dyndns.org 这类私有后缀）无法界定注册域，
	// 退化为按标签逐级上溯，检查整个私有域空间。
	pubSuf, icann := publicsuffix.PublicSuffix(host)
	if !icann {
		pubSuf = ""
	}

	// 先截到末尾 4 个标签，避免长域名把查询名拖到超出 DNS 长度限制
	nDots := 0
	if i := strings.LastIndexFunc(host, func(r rune) bool {
		if r == '.' {
			nDots++
		}
		return nDots == hashSubDomainNum
	}); i != -1 {
		host = host[i+1:]
	}

	var hashes []hostnameHash
	for _, sub := range domainSuffixes(host) {
		if sub == pubSuf {
			break
		}
		hashes = append(hashes, hostnameHash(sha256.Sum256([]byte(sub))))
	}
	return hashes
}

// domainSuffixes 由长到短列出各级后缀，直到单标签的顶级域
//
// "3.sub.host.com" -> ["3.sub.host.com" "sub.host.com" "host.com" "com"]
func domainSuffixes(host string) []string {
	labels := strings.Split(host, ".")
	out := make([]string, 0, len(labels))
	for i := range labels {
		out = append(out, strings.Join(labels[i:], "."))
	}
	return out
}

// buildHashQuestion 把多个前缀拼成一个 TXT 查询
func buildHashQuestion(hashes []hostnameHash, suffix string) *dns.Msg {
	var b strings.Builder
	for _, h := range hashes {
		b.WriteString(hex.EncodeToString(h[:hashPrefixLen]))
		b.WriteByte('.')
	}
	b.WriteString(suffix)

	req := new(dns.Msg)
	req.SetQuestion(b.String(), dns.TypeTXT)
	req.RecursionDesired = true
	return req
}

// collectHashes 从应答中提取 64 位十六进制 TXT 内容
//
// 长度或内容不符的条目直接忽略：那是服务端的多余输出或格式变更，
// 当成摘要参与比对只会制造莫名其妙的拦截。
func collectHashes(resp *dns.Msg) []hostnameHash {
	if resp == nil {
		return nil
	}
	var out []hostnameHash
	for _, rr := range resp.Answer {
		txt, ok := rr.(*dns.TXT)
		if !ok {
			continue
		}
		for _, t := range txt.Txt {
			if len(t) != hashHexSize {
				continue
			}
			buf, err := hex.DecodeString(t)
			if err != nil || len(buf) != hashSize {
				continue
			}
			var h hostnameHash
			copy(h[:], buf)
			out = append(out, h)
		}
	}
	return out
}

// matchesAny 判断 a 中是否存在与 b 相同的摘要
func matchesAny(a, b []hostnameHash) bool {
	if len(a) == 0 || len(b) == 0 {
		return false
	}
	set := make(map[hostnameHash]struct{}, len(b))
	for _, h := range b {
		set[h] = struct{}{}
	}
	for _, h := range a {
		if _, ok := set[h]; ok {
			return true
		}
	}
	return false
}

// hashCacheEntry 缓存中的一个前缀及其命中的摘要
type hashCacheEntry struct {
	prefix    hashPrefix
	hashes    []hostnameHash
	expiresAt time.Time
}

// hashCache 按前缀索引的 LRU 缓存。
//
// 键是 2 字节前缀而非完整域名：同一前缀下的所有域名共享一次网络查询，
// 这正是哈希前缀机制本身的粒度，缓存没有理由比它更细。
type hashCache struct {
	mu    sync.Mutex
	size  int
	ttl   time.Duration
	ll    *list.List
	items map[hashPrefix]*list.Element
}

func newHashCache(size int, ttl time.Duration) *hashCache {
	if size <= 0 {
		size = DefaultSafeBrowsingCacheSize
	}
	if ttl <= 0 {
		ttl = DefaultSafeBrowsingCacheTTL * time.Second
	}
	return &hashCache{
		size:  size,
		ttl:   ttl,
		ll:    list.New(),
		items: make(map[hashPrefix]*list.Element, size),
	}
}

// lookup 检查这些摘要是否已有结论。
//
// found=true 表示所有前缀都有未过期的缓存，blocked 即最终结论；
// found=false 时 needQuery 给出仍需查询的前缀（已缓存的不会重复带上）。
func (c *hashCache) lookup(hashes []hostnameHash) (found, blocked bool, needQuery []hostnameHash) {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	found = true
	seen := make(map[hashPrefix]struct{}, len(hashes))

	for _, h := range hashes {
		prefix := hashPrefixOf(h)
		if _, dup := seen[prefix]; dup {
			continue
		}
		seen[prefix] = struct{}{}

		el, ok := c.items[prefix]
		if !ok {
			found = false
			needQuery = append(needQuery, h)
			continue
		}
		entry := el.Value.(*hashCacheEntry)
		if now.After(entry.expiresAt) {
			c.removeElement(el)
			found = false
			needQuery = append(needQuery, h)
			continue
		}
		c.ll.MoveToFront(el)
		if matchesAny([]hostnameHash{h}, entry.hashes) {
			blocked = true
		}
	}

	if found && blocked {
		return true, true, nil
	}
	if found {
		return true, false, nil
	}
	return false, false, needQuery
}

// store 写入本次查询覆盖到的每个前缀的命中摘要
func (c *hashCache) store(queried []hostnameHash, received []hostnameHash) {
	if len(queried) == 0 {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()

	expiresAt := time.Now().Add(c.ttl)
	for _, h := range queried {
		prefix := hashPrefixOf(h)
		var hit []hostnameHash
		for _, r := range received {
			if hashPrefixOf(r) == prefix {
				hit = append(hit, r)
			}
		}
		// hit 为空也要写入：否则这个前缀会被反复查询，
		// 每次都问同一个没有答案的问题
		if el, ok := c.items[prefix]; ok {
			entry := el.Value.(*hashCacheEntry)
			entry.hashes = hit
			entry.expiresAt = expiresAt
			c.ll.MoveToFront(el)
			continue
		}
		el := c.ll.PushFront(&hashCacheEntry{prefix: prefix, hashes: hit, expiresAt: expiresAt})
		c.items[prefix] = el
	}

	for c.ll.Len() > c.size {
		if el := c.ll.Back(); el != nil {
			c.removeElement(el)
		}
	}
}

func (c *hashCache) removeElement(el *list.Element) {
	c.ll.Remove(el)
	delete(c.items, el.Value.(*hashCacheEntry).prefix)
}

func hashPrefixOf(h hostnameHash) hashPrefix {
	var p hashPrefix
	copy(p[:], h[:hashPrefixLen])
	return p
}
