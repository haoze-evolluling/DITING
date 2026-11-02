package core

import (
	"fmt"
	"log"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
)

// zone 文件的资源上限。
//
// 区内容是用户直接粘贴的文本，没有任何天然的规模约束；不设上限就等于把
// 解析耗时与内存交给输入决定。三个上限分别对应「多少个区」「多少条记录」
// 「单段文本多大」，$GENERATE 这类指令的膨胀也由此兜住。
const (
	// MaxZoneCount 允许配置的区数量上限
	MaxZoneCount = 32
	// MaxZoneRecords 全部区合计的记录条数上限
	MaxZoneRecords = 10000
	// MaxZoneContentBytes 单个区内容的字节上限（1 MiB）
	MaxZoneContentBytes = 1 << 20
	// DefaultZoneTTL 未显式声明 TTL 时的默认生存期（秒）
	DefaultZoneTTL uint32 = 300
)

// ZoneEntry 单个本地权威区
type ZoneEntry struct {
	ID      string `json:"id"`
	Origin  string `json:"origin"`  // 区顶点，如 "lan."、"intra.example.com"
	Content string `json:"content"` // RFC 1035 区文件文本
	Enabled bool   `json:"enabled"`
}

// ZoneConfig 本地权威区配置
type ZoneConfig struct {
	Enabled bool        `json:"enabled"`
	TTL     uint32      `json:"ttl"` // 默认生存期，区文件内显式 TTL 优先
	Zones   []ZoneEntry `json:"zones"`
}

// DefaultZoneConfig 返回默认配置（默认关闭，避免影响既有解析路径）
func DefaultZoneConfig() ZoneConfig {
	return ZoneConfig{
		Enabled: false,
		TTL:     DefaultZoneTTL,
		Zones:   []ZoneEntry{},
	}
}

// NormalizeZoneConfig 校验与修补区配置默认值。
//
// 有意不在此处截断超出上限的区：归一化的结果会被持久化，静默丢弃等于
// 直接删掉用户输入。超限由引擎在构建期记录为错误状态，界面据此提示。
func NormalizeZoneConfig(cfg *ZoneConfig) {
	if cfg == nil {
		return
	}
	if cfg.TTL == 0 {
		cfg.TTL = DefaultZoneTTL
	}
	if cfg.Zones == nil {
		cfg.Zones = []ZoneEntry{}
	}
	for i := range cfg.Zones {
		cfg.Zones[i].Origin = strings.TrimSpace(cfg.Zones[i].Origin)
		cfg.Zones[i].ID = strings.TrimSpace(cfg.Zones[i].ID)
		if cfg.Zones[i].ID == "" {
			cfg.Zones[i].ID = fmt.Sprintf("zone-%d-%d", time.Now().UnixNano(), i)
		}
	}
}

// ZoneState 单个区的构建结果，供界面展示
type ZoneState struct {
	ID      string `json:"id"`
	Origin  string `json:"origin"`
	Records int    `json:"records"`
	Loaded  bool   `json:"loaded"`
	Error   string `json:"error,omitempty"`
}

// zoneBuild 单个区解析后的索引
type zoneBuild struct {
	origin  string
	records map[string]map[uint16][]dns.RR
	soa     *dns.SOA
	count   int
	trunc   bool
}

// ZoneEngine 本地权威区引擎。
//
// 与 hosts / rewrite 的区别在于「权威范围」：区顶点及其以下的所有名字都由
// 本地负责，缺失的名字返回权威 NODATA 而不是继续向上游查询。这正是内网
// 域名最常见的诉求（*禁止* 泄漏到公网），也意味着顶点要由用户显式声明。
type ZoneEngine struct {
	mu         sync.RWMutex
	enabled    bool
	defaultTTL uint32
	entries    []ZoneEntry

	// records 全局名字索引：小写 FQDN -> 类型 -> 记录
	records map[string]map[uint16][]dns.RR
	// owner 名字 -> 其所属区的顶点，用于 NODATA 时挑选 SOA
	owner map[string]string
	// origins 全部区顶点，按标签数降序，最长后缀优先匹配
	origins []string
	// soaByOrigin 区顶点 -> 该区 SOA
	soaByOrigin map[string]*dns.SOA
	// states 各区的构建结果（含失败原因）
	states []ZoneState
}

// NewZoneEngine 创建并构建本地权威区引擎
func NewZoneEngine(cfg ZoneConfig) *ZoneEngine {
	ttl := cfg.TTL
	if ttl == 0 {
		ttl = DefaultZoneTTL
	}
	e := &ZoneEngine{defaultTTL: ttl}
	e.build(cfg)
	return e
}

// IsEnabled 检查区引擎当前是否启用
func (e *ZoneEngine) IsEnabled() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.enabled
}

// Configure 整体更新区配置并重建索引
func (e *ZoneEngine) Configure(cfg ZoneConfig) {
	e.build(cfg)
}

// GetConfig 返回当前生效的配置（含区文本，供界面回填）
func (e *ZoneEngine) GetConfig() ZoneConfig {
	e.mu.RLock()
	defer e.mu.RUnlock()

	zones := make([]ZoneEntry, len(e.entries))
	copy(zones, e.entries)
	return ZoneConfig{Enabled: e.enabled, TTL: e.defaultTTL, Zones: zones}
}

// States 返回各区的构建结果
func (e *ZoneEngine) States() []ZoneState {
	e.mu.RLock()
	defer e.mu.RUnlock()

	res := make([]ZoneState, len(e.states))
	copy(res, e.states)
	return res
}

// RecordCount 返回当前已加载的记录总数
func (e *ZoneEngine) RecordCount() int {
	e.mu.RLock()
	defer e.mu.RUnlock()

	return len(e.owner)
}

// build 按新配置全量重建索引。
//
// 解析在锁外进行（耗时随文本规模增长），因此先把当前默认 TTL 取到本地变量，
// 不直接读 e.defaultTTL —— 那会与另一个 Configure 的写入构成数据竞争。
func (e *ZoneEngine) build(cfg ZoneConfig) {
	ttl := cfg.TTL
	if ttl == 0 {
		e.mu.RLock()
		ttl = e.defaultTTL
		e.mu.RUnlock()
	}
	if ttl == 0 {
		ttl = DefaultZoneTTL
	}

	records := make(map[string]map[uint16][]dns.RR)
	owner := make(map[string]string)
	soaByOrigin := make(map[string]*dns.SOA)
	states := make([]ZoneState, 0, len(cfg.Zones))

	budget := MaxZoneRecords
	var origins []string

	for i, entry := range cfg.Zones {
		state := ZoneState{ID: entry.ID, Origin: entry.Origin}

		if i >= MaxZoneCount {
			state.Error = fmt.Sprintf("超出区数量上限 %d，未加载", MaxZoneCount)
			states = append(states, state)
			continue
		}
		if !entry.Enabled {
			state.Error = "已停用"
			states = append(states, state)
			continue
		}
		if len(entry.Content) > MaxZoneContentBytes {
			state.Error = fmt.Sprintf("区文本 %d 字节超出上限 %d 字节", len(entry.Content), MaxZoneContentBytes)
			states = append(states, state)
			continue
		}
		if budget <= 0 {
			state.Error = fmt.Sprintf("已达记录总数上限 %d，未加载", MaxZoneRecords)
			states = append(states, state)
			continue
		}

		built, err := parseZoneEntry(entry, ttl, budget)
		if err != nil {
			state.Error = err.Error()
			states = append(states, state)
			log.Printf("[Zone] 区 %s 解析失败: %v", entry.Origin, err)
			continue
		}

		state.Records = built.count
		state.Loaded = true
		if built.trunc {
			state.Error = fmt.Sprintf("记录数达到上限 %d，已截断", MaxZoneRecords)
		}

		e.mergeZone(records, owner, built)
		if built.soa != nil {
			soaByOrigin[built.origin] = built.soa
		}
		origins = append(origins, built.origin)
		budget -= built.count
		states = append(states, state)
	}

	sort.SliceStable(origins, func(i, j int) bool {
		return dns.CountLabel(origins[i]) > dns.CountLabel(origins[j])
	})

	entries := make([]ZoneEntry, len(cfg.Zones))
	copy(entries, cfg.Zones)

	e.mu.Lock()
	e.enabled = cfg.Enabled
	if cfg.TTL > 0 {
		e.defaultTTL = cfg.TTL
	}
	e.entries = entries
	e.records = records
	e.owner = owner
	e.origins = origins
	e.soaByOrigin = soaByOrigin
	e.states = states
	e.mu.Unlock()

	if cfg.Enabled {
		log.Printf("[Zone] 本地权威区构建完毕：%d 个区、%d 个名字", len(origins), len(owner))
	}
}

// mergeZone 把单个区的索引并入全局索引
func (e *ZoneEngine) mergeZone(records map[string]map[uint16][]dns.RR, owner map[string]string, built *zoneBuild) {
	for name, byType := range built.records {
		dst, ok := records[name]
		if !ok {
			dst = make(map[uint16][]dns.RR, len(byType))
			records[name] = dst
		}
		for rrtype, rrs := range byType {
			dst[rrtype] = append(dst[rrtype], rrs...)
		}
		owner[name] = built.origin
	}
}

// parseZoneEntry 解析单个区文本。
//
// budget 为该区可占用的记录条数余量，超出即停止解析并标记截断——
// $GENERATE 用一行文本就能展开出任意多条记录，字节上限挡不住它。
func parseZoneEntry(entry ZoneEntry, defaultTTL uint32, budget int) (*zoneBuild, error) {
	origin := strings.ToLower(strings.TrimSpace(entry.Origin))
	if origin == "" {
		return nil, fmt.Errorf("区顶点不能为空")
	}
	origin = dns.Fqdn(origin)
	if _, ok := dns.IsDomainName(origin); !ok {
		return nil, fmt.Errorf("区顶点 %q 不是合法域名", entry.Origin)
	}

	built := &zoneBuild{
		origin:  origin,
		records: make(map[string]map[uint16][]dns.RR),
	}
	if strings.TrimSpace(entry.Content) == "" {
		return built, nil
	}

	name := entry.ID
	if name == "" {
		name = entry.Origin
	}
	zp := dns.NewZoneParser(strings.NewReader(entry.Content), origin, name)
	// 安全必需：$INCLUDE 会按区文本里写的路径读取宿主机文件，
	// 并把文件内容通过报错信息回显出来，等于给了输入一条读文件的通道。
	zp.SetIncludeAllowed(false)
	zp.SetDefaultTTL(defaultTTL)

	for rr, ok := zp.Next(); ok; rr, ok = zp.Next() {
		if built.count >= budget {
			built.trunc = true
			break
		}
		if err := built.add(rr); err != nil {
			return nil, err
		}
	}
	if err := zp.Err(); err != nil {
		return nil, err
	}
	return built, nil
}

// add 把一条记录登记进区索引
func (b *zoneBuild) add(rr dns.RR) error {
	hdr := rr.Header()
	if hdr == nil {
		return nil
	}
	key := strings.ToLower(hdr.Name)
	if _, ok := dns.IsDomainName(key); !ok {
		return fmt.Errorf("记录名 %q 不是合法域名", hdr.Name)
	}
	// 类不匹配（CH/HS）的记录无法作为 IN 应答，直接跳过而不是留着误导用户
	if hdr.Class != dns.ClassINET {
		return nil
	}

	byType, ok := b.records[key]
	if !ok {
		byType = make(map[uint16][]dns.RR)
		b.records[key] = byType
	}
	byType[hdr.Rrtype] = append(byType[hdr.Rrtype], rr)
	b.count++

	if soa, ok := rr.(*dns.SOA); ok && key == b.origin {
		b.soa = soa
	}
	return nil
}

// Lookup 查询本地权威区。
//
// 返回 matched=true 表示该名字由本地负责，此时即使 answers 为空也必须以
// 权威 NODATA 应答——继续向上游查询恰恰是用户配置内网区时要杜绝的事。
// soa 为该名字所属区的 SOA，供负缓存使用，可能为 nil。
func (e *ZoneEngine) Lookup(qname string, qtype uint16) (answers []dns.RR, soa dns.RR, matched bool) {
	e.mu.RLock()
	defer e.mu.RUnlock()

	if !e.enabled {
		return nil, nil, false
	}

	name := strings.ToLower(dns.Fqdn(qname))
	if _, ok := dns.IsDomainName(name); !ok {
		return nil, nil, false
	}

	origin, ok := e.authoritativeOriginLocked(name)
	if !ok {
		return nil, nil, false
	}
	soa = e.soaForLocked(origin)

	byType := e.records[name]
	if len(byType) == 0 {
		// 名字落在权威区内但区里没有它：依然是权威的「不存在该名字」
		return nil, soa, true
	}

	// ANY 要求返回该名字的全部记录，这是区数据能直接给出的答案
	if qtype == dns.TypeANY {
		for _, rrs := range byType {
			answers = append(answers, copyRRs(rrs)...)
		}
		return answers, soa, true
	}

	if rrs := byType[qtype]; len(rrs) > 0 {
		return copyRRs(rrs), soa, true
	}

	// 无该类型的记录：区内的 CNAME 仍要继续追，追不到则按 NODATA 处理。
	// 只回一条孤立 CNAME 对手写客户端等同于一次无解答案。
	cnames := byType[dns.TypeCNAME]
	if qtype == dns.TypeCNAME || len(cnames) == 0 {
		return nil, soa, true
	}
	chain := copyRRs(cnames)
	for _, rr := range cnames {
		cn, ok := rr.(*dns.CNAME)
		if !ok {
			continue
		}
		chain = append(chain, e.chaseLocked(cn.Target, qtype, map[string]bool{name: true})...)
	}
	if len(chain) == len(cnames) {
		return nil, soa, true
	}
	return chain, soa, true
}

// authoritativeOriginLocked 找出负责该名字的区顶点（最长后缀优先）
func (e *ZoneEngine) authoritativeOriginLocked(name string) (string, bool) {
	for _, origin := range e.origins {
		if name == origin || strings.HasSuffix(name, "."+origin) {
			return origin, true
		}
	}
	return "", false
}

// soaForLocked 取该区的 SOA；区里没写 SOA 时合成一条，保证 NODATA 可被负缓存
func (e *ZoneEngine) soaForLocked(origin string) dns.RR {
	if soa, ok := e.soaByOrigin[origin]; ok && soa != nil {
		return dns.Copy(soa)
	}
	return &dns.SOA{
		Hdr:     dns.RR_Header{Name: origin, Rrtype: dns.TypeSOA, Class: dns.ClassINET, Ttl: e.defaultTTL},
		Ns:      "localhost.",
		Mbox:    "nobody.invalid.",
		Serial:  1,
		Refresh: 10000,
		Retry:   2400,
		Expire:  604800,
		Minttl:  e.defaultTTL,
	}
}

// chaseLocked 沿区内的 CNAME 链继续取请求类型的记录。
//
// visited 与深度上限共同兜住自引用与环路；链一旦离开本地权威区即停止，
// 本引擎没有向上游补全的能力。
func (e *ZoneEngine) chaseLocked(target string, qtype uint16, visited map[string]bool) []dns.RR {
	if len(visited) > 8 {
		return nil
	}
	name := strings.ToLower(dns.Fqdn(target))
	if visited[name] {
		return nil
	}
	visited[name] = true
	if _, ok := e.authoritativeOriginLocked(name); !ok {
		return nil
	}

	byType := e.records[name]
	if len(byType) == 0 {
		return nil
	}
	if rrs := byType[qtype]; len(rrs) > 0 {
		return copyRRs(rrs)
	}

	var chained []dns.RR
	for _, rr := range byType[dns.TypeCNAME] {
		cn, ok := rr.(*dns.CNAME)
		if !ok {
			continue
		}
		chained = append(chained, dns.Copy(cn))
		chained = append(chained, e.chaseLocked(cn.Target, qtype, visited)...)
	}
	return chained
}

// copyRRs 复制记录切片。
//
// 索引里的记录只读，但应答会流入缓存与响应改写环节，共享指针会把那些
// 环节的修改写回索引本身。
func copyRRs(rrs []dns.RR) []dns.RR {
	out := make([]dns.RR, 0, len(rrs))
	for _, rr := range rrs {
		out = append(out, dns.Copy(rr))
	}
	return out
}

// ParseZonePreview 解析区文本并返回记录预览，用于配置界面保存前自检。
//
// 与引擎使用同一套解析路径与同一套上限，预览通过即代表保存后能生效。
func ParseZonePreview(origin, content string, ttl uint32) ([]string, error) {
	if ttl == 0 {
		ttl = DefaultZoneTTL
	}
	if len(content) > MaxZoneContentBytes {
		return nil, fmt.Errorf("区文本 %d 字节超出上限 %d 字节", len(content), MaxZoneContentBytes)
	}
	built, err := parseZoneEntry(ZoneEntry{ID: "preview", Origin: origin, Content: content, Enabled: true}, ttl, MaxZoneRecords)
	if err != nil {
		return nil, err
	}
	if built.trunc {
		return nil, fmt.Errorf("记录数超出上限 %d", MaxZoneRecords)
	}

	preview := make([]string, 0, built.count)
	names := make([]string, 0, len(built.records))
	for name := range built.records {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		byType := built.records[name]
		types := make([]int, 0, len(byType))
		for rrtype := range byType {
			types = append(types, int(rrtype))
		}
		sort.Ints(types)
		for _, rrtype := range types {
			for _, rr := range byType[uint16(rrtype)] {
				preview = append(preview, rr.String())
			}
		}
	}
	return preview, nil
}
