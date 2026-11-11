package core

import (
	"log"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

const (
	// BlockModeNullIP 返回空 IP (0.0.0.0 / ::)
	BlockModeNullIP = "null_ip"
	// BlockModeNXDOMAIN 返回 NXDOMAIN (Name Error)
	BlockModeNXDOMAIN = "nxdomain"
	// BlockModeRefused 返回 REFUSED
	BlockModeRefused = "refused"

	// DefaultBlockingIPv4 默认 IPv4 拦截响应地址
	DefaultBlockingIPv4 = "0.0.0.0"
	// DefaultBlockingIPv6 默认 IPv6 拦截响应地址
	DefaultBlockingIPv6 = "::"

	// DefaultRuleTTL 拦截响应的默认缓存 TTL 秒数
	DefaultRuleTTL uint32 = 10
)

// FilterList 最近一次拉取状态取值（FilterList.LastStatus）
const (
	ListStatusOK        = "ok"        // 内容已更新
	ListStatusUnchanged = "unchanged" // 304 未变更
	ListStatusCached    = "cached"    // 拉取失败，沿用本地缓存
	ListStatusFailed    = "failed"    // 拉取失败且无可用缓存
)

// FilterList 订阅规则源描述
type FilterList struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	URL         string `json:"url"` // 支持 http://, https:// 或本地文件绝对/相对路径
	Enabled     bool   `json:"enabled"`
	RulesCount  int    `json:"rulesCount"`
	LastUpdated int64  `json:"lastUpdated"` // Unix 毫秒时间戳
	Checksum    string `json:"checksum"`

	// ETag / LastModified 为增量更新的协商凭证（借鉴 blocky downloaded_cache），随配置持久化。
	ETag         string `json:"etag,omitempty"`
	LastModified string `json:"lastModified,omitempty"`

	// LastStatus / LastError 为最近一次拉取结果（运行时状态，不落盘）。
	// LastStatus 取值：ok（内容已更新）| unchanged（304 未变更）| cached（沿用本地缓存）| failed（拉取失败）。
	LastStatus string `json:"lastStatus,omitempty"`
	LastError  string `json:"lastError,omitempty"`
}

// FilterConfig 规则过滤引擎运行与策略配置
type FilterConfig struct {
	Enabled             bool         `json:"enabled"`
	BlockMode           string       `json:"blockMode"`    // "null_ip" | "nxdomain" | "refused"
	BlockingIPv4        string       `json:"blockingIPv4"` // 默认 "0.0.0.0"
	BlockingIPv6        string       `json:"blockingIPv6"` // 默认 "::"
	CustomRules         []string     `json:"customRules"`  // 用户自定义规则文本行
	Lists               []FilterList `json:"lists"`        // 订阅规则列表
	UpdateIntervalHours int          `json:"updateIntervalHours"`
	DataDir             string       `json:"dataDir"` // 规则源 .txt 缓存目录

	// 分时拦截（时间计划）：开启后仅在命中计划的窗口内执行拦截
	ScheduleEnabled bool               `json:"scheduleEnabled"`
	Schedules       []BlockingSchedule `json:"schedules"`

	// FilterResponse 响应侧别名链复检开关（默认关闭）。
	// 开启后对上游应答中的 CNAME 目标与 A/AAAA 记录所属名二次匹配黑名单规则，
	// 用于拦截「QNAME 合法但别名指向黑名单域」的深链绕过。
	FilterResponse bool `json:"filterResponse"`

	// AllowlistOnly 全局「仅白名单」模式（默认关闭，借鉴 blocky allowlistOnly / pi-hole 分组模型）。
	// 开启后仅当命中放行规则（@@ 例外）才放行，未命中任何规则的查询一律阻断。
	AllowlistOnly bool `json:"allowlistOnly"`

	// BogusNXDomain 伪应答纠正开关（默认关闭）。
	//
	// 开启后，应答中的 A/AAAA 落在 BogusNXDomainNetworks 内即判定为上游劫持，就地改写为
	// NXDOMAIN 并打上拦截标记，使查询日志与 EDE 自动归类。默认关闭是必要的：企业内网
	// 大量使用私网地址，误判会让合法域名直接解析失败。
	BogusNXDomain bool `json:"bogusNxDomain"`
	// BogusNXDomainNetworks 伪应答地址清单，同时接受单个 IP 与 CIDR 网段
	BogusNXDomainNetworks []string `json:"bogusNxDomainNetworks,omitempty"`

	// BlockedServices 被整组拦截的内置服务 ID（见 services.json）。
	//
	// 与订阅列表相互独立：这里的规则随程序内置，无需联网拉取，
	// 因此在配置中只存 ID，规则本体在构建规则索引时从目录展开。
	BlockedServices []string `json:"blockedServices,omitempty"`
	// BlockedServiceGroups 被整组拦截的服务分组 ID（如 social_network）。
	// 与 BlockedServices 取并集，便于「一键拦掉全部短视频」这类用法。
	BlockedServiceGroups []string `json:"blockedServiceGroups,omitempty"`

	// ServiceSchedules 单个内置服务的每周生效计划（服务 ID → 计划列表）。
	//
	// 与全局 ScheduleEnabled 相互独立：全局计划管的是「什么时候整体拦截」，
	// 这里管的是「某个应用什么时候可以被访问」。未出现在本表中的服务恒为生效。
	ServiceSchedules map[string][]BlockingSchedule `json:"serviceSchedules,omitempty"`
}

// DefaultFilterConfig 生成默认过滤配置
func DefaultFilterConfig() FilterConfig {
	return FilterConfig{
		Enabled:             true,
		BlockMode:           BlockModeNullIP,
		BlockingIPv4:        DefaultBlockingIPv4,
		BlockingIPv6:        DefaultBlockingIPv6,
		CustomRules:         []string{},
		Lists:               defaultSubscriptionLists(),
		UpdateIntervalHours: 24,
		DataDir:             platform.DefaultFilterDir(),
		ScheduleEnabled:     false,
		Schedules:           []BlockingSchedule{},
		FilterResponse:      false,
		AllowlistOnly:       false,

		BogusNXDomain:         false,
		BogusNXDomainNetworks: DefaultBogusNXDomainNetworks(),
	}
}

// defaultSubscriptionLists 提供默认内置订阅列表
func defaultSubscriptionLists() []FilterList {
	return []FilterList{
		{
			ID:          "adguard-dns-filter",
			Name:        "AdGuard DNS Filter",
			URL:         "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt",
			Enabled:     true,
			RulesCount:  0,
			LastUpdated: 0,
		},
	}
}

// NormalizeFilterConfig 校验与修补配置项默认值
func NormalizeFilterConfig(cfg *FilterConfig) {
	if cfg == nil {
		return
	}
	if cfg.BlockMode == "" {
		cfg.BlockMode = BlockModeNullIP
	}
	if cfg.BlockingIPv4 == "" {
		cfg.BlockingIPv4 = DefaultBlockingIPv4
	}
	if cfg.BlockingIPv6 == "" {
		cfg.BlockingIPv6 = DefaultBlockingIPv6
	}
	if cfg.UpdateIntervalHours <= 0 {
		cfg.UpdateIntervalHours = 24
	}
	if cfg.DataDir == "" {
		cfg.DataDir = DefaultFilterConfig().DataDir
	}
	if cfg.CustomRules == nil {
		cfg.CustomRules = []string{}
	}
	if cfg.Lists == nil {
		cfg.Lists = defaultSubscriptionLists()
	}
	// 编译时间计划，丢弃非法条目并记录日志（坏配置不阻断拦截常开语义）
	if cfg.Schedules == nil {
		cfg.Schedules = []BlockingSchedule{}
	} else {
		valid := cfg.Schedules[:0]
		for i := range cfg.Schedules {
			if err := NormalizeSchedule(&cfg.Schedules[i]); err != nil {
				log.Printf("[FilterConfig] 丢弃非法时间计划 (%s): %v", cfg.Schedules[i].Name, err)
				continue
			}
			valid = append(valid, cfg.Schedules[i])
		}
		cfg.Schedules = valid
	}

	// 伪应答地址：只做去空白与去重，合法性交由匹配器编译时判定并报告。
	// 这里丢掉的条目无法反馈给用户，而编译期的错误信息可以。
	normalized := make([]string, 0, len(cfg.BogusNXDomainNetworks))
	seen := make(map[string]struct{}, len(cfg.BogusNXDomainNetworks))
	for _, raw := range cfg.BogusNXDomainNetworks {
		entry := strings.TrimSpace(raw)
		if entry == "" {
			continue
		}
		key := strings.ToLower(entry)
		if _, dup := seen[key]; dup {
			continue
		}
		seen[key] = struct{}{}
		normalized = append(normalized, entry)
	}
	cfg.BogusNXDomainNetworks = normalized

	// 内置服务 ID 与分组：剔除目录中不存在的项。
	// 记录日志而非报错——目录版本变化会让旧配置里的服务消失，
	// 此时保留其余勾选、丢弃失效项，比拒绝加载整份配置更符合用户预期。
	cfg.BlockedServices = filterKnownIDs(cfg.BlockedServices, ServiceExists, "服务")
	cfg.BlockedServiceGroups = filterKnownIDs(cfg.BlockedServiceGroups, ServiceGroupExists, "服务分组")
	cfg.ServiceSchedules = NormalizeServiceSchedules(cfg.ServiceSchedules)
}

// equalStrings 判断两个字符串切片是否逐项相等（长度与顺序都要一致）。
func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// filterKnownIDs 去除空白、重复与目录中不存在的 ID，保持原有顺序。
func filterKnownIDs(ids []string, known func(string) bool, kind string) []string {
	if len(ids) == 0 {
		return nil
	}
	out := make([]string, 0, len(ids))
	seen := make(map[string]struct{}, len(ids))
	for _, raw := range ids {
		id := strings.TrimSpace(raw)
		if id == "" {
			continue
		}
		if _, dup := seen[id]; dup {
			continue
		}
		seen[id] = struct{}{}
		if !known(id) {
			log.Printf("[FilterConfig] 忽略未知的内置%s: %s", kind, id)
			continue
		}
		out = append(out, id)
	}
	return out
}

// FilterStats 规则引擎运行时统计指标
type FilterStats struct {
	Enabled        bool    `json:"enabled"`
	TotalRules     int     `json:"totalRules"`
	ActiveLists    int     `json:"activeLists"`
	TotalQueries   uint64  `json:"totalQueries"`
	BlockedQueries uint64  `json:"blockedQueries"`
	AllowedQueries uint64  `json:"allowedQueries"`
	BlockRate      float64 `json:"blockRate"`
	// ScheduleActive 当前时刻拦截是否处于生效窗口（计划关闭时恒为 true）
	ScheduleActive bool `json:"scheduleActive"`
	// Paused 定时暂停拦截是否处于生效状态（纯运行时状态，重启即恢复）
	Paused bool `json:"paused"`
	// PausedRemainingSec 暂停剩余秒数（未暂停为 0）
	PausedRemainingSec int64 `json:"pausedRemainingSec"`
	// PausedUntilMs 预计恢复时刻 Unix 毫秒（未暂停为 0）
	PausedUntilMs int64 `json:"pausedUntilMs"`
}

// CheckHostResult 域名过滤检测结果
type CheckHostResult struct {
	Blocked     bool   `json:"blocked"`
	Action      string `json:"action"` // "block" | "allow" | "pass"
	MatchedRule string `json:"matchedRule"`
	ListName    string `json:"listName"`
	Reason      string `json:"reason"`
	// Rewritten 为 $dnsrewrite 规则给出的应答内容；仅在 Action == "rewrite" 时非空。
	//
	// 拦截与重写是两种不同的应答改写，用独立字段而非复用 Blocked，
	// 便于查询日志与规则测试面板区分展示。
	Rewritten *RewriteResult `json:"rewritten,omitempty"`
}

// IsRewrite 判断本次判定是否为重写命中
func (r CheckHostResult) IsRewrite() bool {
	return r.Action == "rewrite" && r.Rewritten != nil
}

// CheckDomainRequest 域名检测请求 DTO
type CheckDomainRequest struct {
	Domain string `json:"domain"`
	QType  string `json:"qtype,omitempty"`
}

// UpdateRulesRequest 更新用户自定义规则请求 DTO
type UpdateRulesRequest struct {
	Rules []string `json:"rules"`
}
