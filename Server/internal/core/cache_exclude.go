package core

import (
	"fmt"
	"regexp"
	"strings"
	"sync/atomic"
)

const (
	// maxCacheExcludePatterns 排除规则条数上限。
	//
	// 每条规则都会在缓存热路径上对每个查询求值一次，
	// 无上限的规则集会直接转化为无上限的查询延迟。
	maxCacheExcludePatterns = 256
	// maxCacheExcludePatternLen 单条规则的长度上限
	maxCacheExcludePatternLen = 512
)

// CacheExcluder 依据正则集合判断某个域名是否不参与缓存。
//
// 采用 Go 的 RE2 引擎：它不支持回溯，因此不存在灾难性回溯（ReDoS）风险，
// 由不可信来源提供的规则也不会拖垮解析线程。
type CacheExcluder struct {
	patterns []string
	res      []*regexp.Regexp
	hits     atomic.Uint64
}

// NewCacheExcluder 编译排除规则；非法规则会被剔除并汇总为错误返回。
//
// 返回的匹配器在任何情况下都可用（最坏情况是没有任何规则），
// 单条规则写错不应导致整个缓存功能不可用。
func NewCacheExcluder(patterns []string) (*CacheExcluder, error) {
	e := &CacheExcluder{}
	if len(patterns) == 0 {
		return e, nil
	}

	var problems []string
	for _, raw := range patterns {
		p := strings.TrimSpace(raw)
		if p == "" {
			continue
		}
		if len(e.patterns) >= maxCacheExcludePatterns {
			problems = append(problems, fmt.Sprintf("排除规则数量超过上限 %d，其余已忽略", maxCacheExcludePatterns))
			break
		}
		if len(p) > maxCacheExcludePatternLen {
			problems = append(problems, fmt.Sprintf("排除规则 %q 超过长度上限 %d，已忽略", truncateForLog(p), maxCacheExcludePatternLen))
			continue
		}
		re, err := regexp.Compile(p)
		if err != nil {
			problems = append(problems, fmt.Sprintf("排除规则 %q 非法，已忽略: %v", truncateForLog(p), err))
			continue
		}
		e.patterns = append(e.patterns, p)
		e.res = append(e.res, re)
	}

	if len(problems) > 0 {
		return e, fmt.Errorf("%s", strings.Join(problems, "; "))
	}
	return e, nil
}

// IsExcluded 判断域名是否命中任一排除规则。
//
// 域名会先做归一化（去尾点、转小写），使规则无需关心用户输入的大小写与根点差异。
// 空规则集恒返回 false，调用方无需额外判空。
func (e *CacheExcluder) IsExcluded(domain string) bool {
	if e == nil || len(e.res) == 0 {
		return false
	}

	normalized := NormalizeCacheDomain(domain)
	if normalized == "" {
		return false
	}

	for _, re := range e.res {
		if re.MatchString(normalized) {
			e.hits.Add(1)
			return true
		}
	}
	return false
}

// Patterns 返回当前生效的规则原文
func (e *CacheExcluder) Patterns() []string {
	if e == nil {
		return nil
	}
	return append([]string(nil), e.patterns...)
}

// Hits 返回累计命中次数（被排除而跳过缓存的查询数）
func (e *CacheExcluder) Hits() uint64 {
	if e == nil {
		return 0
	}
	return e.hits.Load()
}

// Size 返回已编译的规则条数
func (e *CacheExcluder) Size() int {
	if e == nil {
		return 0
	}
	return len(e.patterns)
}

// NormalizeCacheDomain 归一化域名：去空白、去尾点、转小写
func NormalizeCacheDomain(domain string) string {
	return strings.ToLower(strings.TrimSuffix(strings.TrimSpace(domain), "."))
}

// truncateForLog 截断过长的规则原文，避免错误信息本身撑爆日志
func truncateForLog(s string) string {
	const limit = 64
	if len(s) <= limit {
		return s
	}
	return s[:limit] + "..."
}
