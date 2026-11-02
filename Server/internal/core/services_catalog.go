package core

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"
)

// servicesCatalogJSON 内置阻断服务目录。
//
// 数据来自 AdGuard Home 的内置服务清单并补充了国内高频站点，
// 只保留 ID / 名称 / 分组 / 域名规则，刻意丢弃其随附的 SVG 图标
// （139 个图标会让本文件膨胀数 MB，而前端用 M3Icon 表现已足够）。
//
//go:embed data/services.json
var servicesCatalogJSON []byte

// BlockedService 目录中的单个服务
type BlockedService struct {
	ID     string   `json:"id"`
	Name   string   `json:"name"`
	Group  string   `json:"group"`
	Rules  []string `json:"rules"`
	RuleN  int      `json:"ruleCount"`
	Source string   `json:"source"`
}

// BlockedServiceGroup 服务分组
type BlockedServiceGroup struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Count int    `json:"count"`
}

// servicesCatalog 目录的编译产物：原始条目 + 预编译规则 + ID 索引。
type servicesCatalog struct {
	Version  int
	Groups   []serviceGroup
	Services []serviceEntry
	byID     map[string]int // 服务 ID → Services 下标
}

type serviceGroup struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type serviceEntry struct {
	ID    string   `json:"id"`
	Name  string   `json:"name"`
	Group string   `json:"group"`
	Rules []string `json:"rules"`
	// parsed 为该服务规则编译后的结果，建目录时一次性算好，避免每次重建规则索引重复解析
	parsed []*ParsedRule
}

// serviceRuleSourcePrefix 服务规则的 Source 前缀。
//
// 用独立前缀而非直接写服务 ID：查询日志与前端需要区分
// 「这条拦截来自内置服务」与「来自同名的订阅列表」。
const serviceRuleSourcePrefix = "service:"

var (
	catalogOnce sync.Once
	catalogData *servicesCatalog
	catalogErr  error
)

// loadServicesCatalog 解析内置目录，进程内只解析一次。
//
// 解析失败属构建期错误（嵌入数据是编译产物），因此缓存错误后原样返回，
// 由调用方决定是降级为「无服务可拦」还是直接失败。
func loadServicesCatalog() (*servicesCatalog, error) {
	catalogOnce.Do(func() {
		var raw struct {
			Version  int            `json:"version"`
			Groups   []serviceGroup `json:"groups"`
			Services []serviceEntry `json:"services"`
		}
		if err := json.Unmarshal(servicesCatalogJSON, &raw); err != nil {
			catalogErr = fmt.Errorf("解析内置服务目录失败: %w", err)
			return
		}

		cat := &servicesCatalog{
			Version:  raw.Version,
			Groups:   raw.Groups,
			Services: raw.Services,
			byID:     make(map[string]int, len(raw.Services)),
		}
		for i := range cat.Services {
			s := &cat.Services[i]
			cat.Services[i].ID = strings.TrimSpace(s.ID)
			s.parsed = parseServiceRules(s)
			cat.byID[s.ID] = i
		}
		catalogData = cat
	})
	return catalogData, catalogErr
}

// parseServiceRules 把服务的域名规则编译为 ParsedRule。
//
// 单条规则解析失败只丢弃该条并记录下标，不让整个服务失效：
// 目录是静态数据，一条坏规则不该拖垮同服务下其它可用规则。
func parseServiceRules(s *serviceEntry) []*ParsedRule {
	source := serviceRuleSourcePrefix + s.ID
	out := make([]*ParsedRule, 0, len(s.Rules))
	for _, line := range s.Rules {
		if r, ok := ParseRuleLine(line, source); ok && r != nil {
			out = append(out, r)
		}
	}
	return out
}

// ServicesCatalog 返回全部服务（按分组、名称排序）。
func ServicesCatalog() ([]BlockedService, []BlockedServiceGroup) {
	cat, err := loadServicesCatalog()
	if err != nil || cat == nil {
		return nil, nil
	}

	groupOrder := make(map[string]int, len(cat.Groups))
	groupNames := make(map[string]string, len(cat.Groups))
	for i, g := range cat.Groups {
		groupOrder[g.ID] = i
		groupNames[g.ID] = g.Name
	}

	services := make([]BlockedService, 0, len(cat.Services))
	for i := range cat.Services {
		s := &cat.Services[i]
		services = append(services, BlockedService{
			ID:     s.ID,
			Name:   s.Name,
			Group:  s.Group,
			Rules:  s.Rules,
			RuleN:  len(s.parsed),
			Source: serviceRuleSourcePrefix + s.ID,
		})
	}
	sort.SliceStable(services, func(i, j int) bool {
		gi, gj := groupOrder[services[i].Group], groupOrder[services[j].Group]
		if gi != gj {
			return gi < gj
		}
		return services[i].Name < services[j].Name
	})

	groups := make([]BlockedServiceGroup, 0, len(cat.Groups))
	counts := make(map[string]int, len(cat.Groups))
	for i := range services {
		counts[services[i].Group]++
	}
	for _, g := range cat.Groups {
		groups = append(groups, BlockedServiceGroup{
			ID:    g.ID,
			Name:  groupNames[g.ID],
			Count: counts[g.ID],
		})
	}
	return services, groups
}

// KnownServiceIDs 返回目录中全部服务 ID 的有序列表，供配置归一化使用。
func KnownServiceIDs() []string {
	cat, err := loadServicesCatalog()
	if err != nil || cat == nil {
		return nil
	}
	ids := make([]string, 0, len(cat.Services))
	for i := range cat.Services {
		ids = append(ids, cat.Services[i].ID)
	}
	sort.Strings(ids)
	return ids
}

// parseBlockedServiceRules 把选中的服务与分组展开为规则列表。
//
// 未知 ID 直接跳过：配置可能来自旧版本（服务已下线）或用户手改，
// 静默丢弃比让整个引擎加载失败更合适，界面上的清单会显示实际生效项。
func parseBlockedServiceRules(serviceIDs, groupIDs []string) []*ParsedRule {
	if len(serviceIDs) == 0 && len(groupIDs) == 0 {
		return nil
	}
	cat, err := loadServicesCatalog()
	if err != nil || cat == nil {
		return nil
	}

	groups := make(map[string]bool, len(groupIDs))
	for _, g := range groupIDs {
		groups[strings.TrimSpace(g)] = true
	}
	selected := make(map[string]bool, len(serviceIDs))
	for _, id := range serviceIDs {
		selected[strings.TrimSpace(id)] = true
	}

	var out []*ParsedRule
	for i := range cat.Services {
		s := &cat.Services[i]
		if !selected[s.ID] && !groups[s.Group] {
			continue
		}
		out = append(out, s.parsed...)
	}
	return out
}

// CountBlockedServiceRules 统计当前选择实际展开出的规则条数。
//
// 供界面显示「已拦 N 条规则」：分组与服务取并集，因此不能简单相加。
func CountBlockedServiceRules(serviceIDs, groupIDs []string) int {
	return len(parseBlockedServiceRules(serviceIDs, groupIDs))
}

// ServiceExists 判断服务 ID 是否在内置目录中。
func ServiceExists(id string) bool {
	cat, err := loadServicesCatalog()
	if err != nil || cat == nil {
		return false
	}
	_, ok := cat.byID[strings.TrimSpace(id)]
	return ok
}

// ServiceGroupExists 判断分组 ID 是否在内置目录中。
func ServiceGroupExists(id string) bool {
	cat, err := loadServicesCatalog()
	if err != nil || cat == nil {
		return false
	}
	id = strings.TrimSpace(id)
	for i := range cat.Groups {
		if cat.Groups[i].ID == id {
			return true
		}
	}
	return false
}
