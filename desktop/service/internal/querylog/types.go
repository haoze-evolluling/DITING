package querylog

import (
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// 查询状态常量，用于 Record.Status 的规范化取值。
const (
	// StatusAllowed 正常放行并回源解析
	StatusAllowed = "allowed"
	// StatusBlocked 被规则引擎 / 访问控制 / 限流 / 防重绑定等拦截
	StatusBlocked = "blocked"
	// StatusCached 命中新鲜缓存
	StatusCached = "cached"
	// StatusStale 命中陈旧容灾缓存（乐观复用）
	StatusStale = "stale"
	// StatusError 上游解析失败或流水线异常
	StatusError = "error"
)

// 统计与容量默认值。
const (
	// DefaultMaxEntries 默认内存环形缓冲容量
	DefaultMaxEntries = 10000
	// DefaultRetentionDays 默认落盘日志留存天数
	DefaultRetentionDays = 7
	// MaxSearchLimit 单次检索返回条目数上限
	MaxSearchLimit = 500
)

// Record 单条查询历史记录（落盘即为一行 JSON）。
type Record struct {
	Timestamp    int64   `json:"ts"`                     // Unix 毫秒时间戳
	Domain       string  `json:"domain"`                 // 查询域名（含尾部点）
	QType        string  `json:"qtype,omitempty"`        // 记录类型，如 A / AAAA
	ClientIP     string  `json:"clientIP,omitempty"`     // 客户端 IP（LogClients 关闭时置空）
	ClientName   string  `json:"clientName,omitempty"`   // 客户端主机名 / 别名
	DurationMs   float64 `json:"durationMs"`             // 解析耗时（毫秒）
	RCode        string  `json:"rcode,omitempty"`        // 应答码，如 NOERROR / NXDOMAIN
	Status       string  `json:"status"`                 // 见 Status* 常量
	Cached       bool    `json:"cached,omitempty"`       // 是否命中缓存
	CacheHit     string  `json:"cacheHit,omitempty"`     // "fresh" | "stale"
	Blocked      bool    `json:"blocked,omitempty"`      // 是否被拦截
	FilterRule   string  `json:"filterRule,omitempty"`   // 命中的规则文本
	FilterReason string  `json:"filterReason,omitempty"` // 拦截 / 放行原因说明
	Protocol     string  `json:"protocol,omitempty"`     // udp | tcp
	Error        string  `json:"error,omitempty"`        // 错误信息
}

// NormalizeStatus 将任意状态字符串规整为受控枚举，未知值回落为 allowed。
func NormalizeStatus(s string) string {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case StatusBlocked:
		return StatusBlocked
	case StatusCached:
		return StatusCached
	case StatusStale:
		return StatusStale
	case StatusError:
		return StatusError
	default:
		return StatusAllowed
	}
}

// QueryLogConfig 查询历史与统计的运行配置。
type QueryLogConfig struct {
	Enabled       bool   `json:"enabled"`       // 总开关：关闭后不再记录任何查询
	MaxEntries    int    `json:"maxEntries"`    // 内存环形缓冲容量
	FileEnabled   bool   `json:"fileEnabled"`   // 是否将历史落盘为 JSON-Lines
	RetentionDays int    `json:"retentionDays"` // 落盘日志留存天数
	LogClients    bool   `json:"logClients"`    // 是否记录客户端 IP / 主机名（隐私开关）
	DataDir       string `json:"dataDir"`       // 落盘目录
}

// DefaultQueryLogConfig 返回标准默认查询日志配置。
//
// 默认开启内存环与落盘（仅记录，不改变 DNS 解析行为）。
func DefaultQueryLogConfig() QueryLogConfig {
	return QueryLogConfig{
		Enabled:       true,
		MaxEntries:    DefaultMaxEntries,
		FileEnabled:   true,
		RetentionDays: DefaultRetentionDays,
		LogClients:    true,
		DataDir:       platform.DefaultQueryLogDir(),
	}
}

// NormalizeQueryLogConfig 校验并修补查询日志配置的缺省与边界值。
func NormalizeQueryLogConfig(cfg *QueryLogConfig) {
	if cfg == nil {
		return
	}
	if cfg.MaxEntries <= 0 {
		cfg.MaxEntries = DefaultMaxEntries
	}
	if cfg.MaxEntries > 200000 {
		cfg.MaxEntries = 200000
	}
	if cfg.RetentionDays <= 0 {
		cfg.RetentionDays = DefaultRetentionDays
	}
	if cfg.RetentionDays > 365 {
		cfg.RetentionDays = 365
	}
	if strings.TrimSpace(cfg.DataDir) == "" {
		cfg.DataDir = platform.DefaultQueryLogDir()
	}
}

// NameCount 用于 Top-N 排行的一项（域名 / 客户端 + 计数）。
type NameCount struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

// HourPoint 单个小时的聚合数据点（用于趋势曲线）。
type HourPoint struct {
	HourMs  int64 `json:"hourMs"` // 该小时起点（Unix 毫秒）
	Queries int   `json:"queries"`
	Blocked int   `json:"blocked"`
	Cached  int   `json:"cached"`
}

// Summary 当前 24 小时滚动窗口的汇总统计。
type Summary struct {
	Queries       int     `json:"queries"`
	Blocked       int     `json:"blocked"`
	Cached        int     `json:"cached"`
	Forwarded     int     `json:"forwarded"`
	Errors        int     `json:"errors"`
	AvgResponseMs float64 `json:"avgResponseMs"`
	CacheHitRate  float64 `json:"cacheHitRate"` // 0 - 1
}

// SearchQuery 查询历史检索条件。
type SearchQuery struct {
	Domain      string `json:"domain"`
	Client      string `json:"client"`
	QType       string `json:"qtype"`
	RCode       string `json:"rcode"`
	Status      string `json:"status"` // "" | blocked | allowed | cached | error
	StartMs     int64  `json:"startMs"`
	EndMs       int64  `json:"endMs"`
	Limit       int    `json:"limit"`
	Offset      int    `json:"offset"`
	IncludeFile bool   `json:"includeFile"` // 内存不足时是否回退扫描落盘文件
}

// SearchResult 查询历史检索结果。
type SearchResult struct {
	Total   int      `json:"total"`
	Entries []Record `json:"entries"`
}

// matches 判断单条记录是否满足检索条件（供内存环与文件读取共用）。
func (q SearchQuery) matches(r Record) bool {
	if q.Domain != "" && !strings.Contains(strings.ToLower(r.Domain), strings.ToLower(q.Domain)) {
		return false
	}
	if q.Client != "" {
		if !strings.Contains(strings.ToLower(r.ClientIP), strings.ToLower(q.Client)) &&
			!strings.Contains(strings.ToLower(r.ClientName), strings.ToLower(q.Client)) {
			return false
		}
	}
	if q.QType != "" && !strings.EqualFold(r.QType, q.QType) {
		return false
	}
	if q.RCode != "" && !strings.EqualFold(r.RCode, q.RCode) {
		return false
	}
	if q.Status != "" && NormalizeStatus(r.Status) != NormalizeStatus(q.Status) {
		return false
	}
	if q.StartMs > 0 && r.Timestamp < q.StartMs {
		return false
	}
	if q.EndMs > 0 && r.Timestamp > q.EndMs {
		return false
	}
	return true
}
