package core

import (
	"fmt"
	"net"
	"sort"
	"strings"
)

// ClientGroup 客户端分组：将一组 IP/CIDR 绑定到专属规则集与拦截方式。
//
// 设计借鉴 pi-hole 的 group/client 模型（gravity.db.sql）与 Technitium
// AdvancedBlockingApp 的「网络 → 组」最近前缀匹配语义。
type ClientGroup struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Enabled     bool     `json:"enabled"`
	Clients     []string `json:"clients"`               // IP 或 CIDR，支持 IPv4/IPv6
	RuleListIDs []string `json:"ruleListIds,omitempty"` // 该组启用的订阅列表 ID（空=全部）
	BlockMode   string   `json:"blockMode,omitempty"`   // 组级拦截方式覆盖（空=继承全局）
	// UpstreamIDs 为该组的专属上游节点 ID（空=沿用主链路）。
	//
	// 借鉴 Technitium 的按网络指定转发器与 AdGuard 的按客户端选上游：
	// 指向的上游 ID 必须是上游配置中真实存在的节点，不存在的会在编译期被剔除。
	UpstreamIDs []string `json:"upstreamIds,omitempty"`

	// 组级分时拦截计划（借鉴 blocky config/schedule.go 的 per-group schedule 门控）：
	// 配置了启用计划时以本组计划判定生效窗口；未配置时回落全局计划语义。
	ScheduleEnabled bool               `json:"scheduleEnabled,omitempty"`
	Schedules       []BlockingSchedule `json:"schedules,omitempty"`

	// AllowlistOnly 组级「仅白名单」开关（空=继承全局）。
	// 开启后仅命中放行规则的查询才被放行，其余一律阻断。
	AllowlistOnly bool `json:"allowlistOnly,omitempty"`
}

// ClientGroupConfig 客户端分组总配置
type ClientGroupConfig struct {
	Enabled bool          `json:"enabled"`
	Groups  []ClientGroup `json:"groups"`
}

// DefaultClientGroupID 未命中任何分组时的回落组标识
const DefaultClientGroupID = "default"

// groupEntry 单个已编译的成员条目（IP 或 CIDR）
type groupEntry struct {
	groupID string
	ipNet   *net.IPNet
	ones    int
}

// GroupResolver 客户端 IP → 分组的最长前缀匹配器。
type GroupResolver struct {
	entries []groupEntry
}

// NewGroupResolver 由分组配置编译匹配器；非法条目会被跳过并返回错误汇总。
//
// 返回的 resolver 在分组全部非法时仍可用（全部回落 default）。
func NewGroupResolver(cfg ClientGroupConfig) (*GroupResolver, error) {
	r := &GroupResolver{}
	if !cfg.Enabled {
		return r, nil
	}

	var problems []string
	for _, g := range cfg.Groups {
		if !g.Enabled {
			continue
		}
		id := strings.TrimSpace(g.ID)
		if id == "" || id == DefaultClientGroupID {
			problems = append(problems, fmt.Sprintf("分组 %q 的 ID 为空或与默认组冲突", g.Name))
			continue
		}
		for _, raw := range g.Clients {
			ip, ipNet, err := parseIPOrCIDR(strings.TrimSpace(raw))
			if err != nil {
				problems = append(problems, fmt.Sprintf("分组 %s 的成员 %q 非法: %v", id, raw, err))
				continue
			}
			if ipNet != nil {
				ones, _ := ipNet.Mask.Size()
				r.entries = append(r.entries, groupEntry{groupID: id, ipNet: ipNet, ones: ones})
			} else {
				mask := 32
				if ip.To4() == nil {
					mask = 128
				}
				r.entries = append(r.entries, groupEntry{
					groupID: id,
					ipNet:   &net.IPNet{IP: ip, Mask: net.CIDRMask(mask, mask)},
					ones:    mask,
				})
			}
		}
	}

	// 前缀长者优先，保证最长前缀匹配；同长度保持声明顺序（稳定）
	sort.SliceStable(r.entries, func(i, j int) bool {
		return r.entries[i].ones > r.entries[j].ones
	})

	if len(problems) > 0 {
		return r, fmt.Errorf("%s", strings.Join(problems, "; "))
	}
	return r, nil
}

// Resolve 返回客户端 IP 命中的分组 ID；未命中任何分组时回落 DefaultClientGroupID。
func (r *GroupResolver) Resolve(ip net.IP) string {
	if r == nil || ip == nil {
		return DefaultClientGroupID
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	for _, e := range r.entries {
		if e.ipNet != nil && e.ipNet.Contains(ip) {
			return e.groupID
		}
	}
	return DefaultClientGroupID
}

// Size 返回已编译的成员条目总数。
func (r *GroupResolver) Size() int {
	if r == nil {
		return 0
	}
	return len(r.entries)
}

// NormalizeClientGroupConfig 校验并修补客户端分组配置。
//
// 空 ID 会被自动生成，重复 ID 会被去重（保留首个），非法成员会被剔除并计入返回错误。
func NormalizeClientGroupConfig(cfg *ClientGroupConfig) error {
	if cfg == nil {
		return nil
	}
	if cfg.Groups == nil {
		cfg.Groups = []ClientGroup{}
		return nil
	}

	seen := make(map[string]bool, len(cfg.Groups))
	var problems []string
	valid := cfg.Groups[:0]
	for i := range cfg.Groups {
		g := cfg.Groups[i]
		g.Name = strings.TrimSpace(g.Name)
		g.ID = strings.TrimSpace(g.ID)
		if g.ID == "" {
			g.ID = fmt.Sprintf("group-%d", i+1)
		}
		if g.ID == DefaultClientGroupID || seen[g.ID] {
			problems = append(problems, fmt.Sprintf("分组 ID %q 重复或与保留字冲突，已跳过", g.ID))
			continue
		}
		if g.Name == "" {
			g.Name = g.ID
		}

		members := make([]string, 0, len(g.Clients))
		for _, raw := range g.Clients {
			trimmed := strings.TrimSpace(raw)
			if trimmed == "" {
				continue
			}
			if _, _, err := parseIPOrCIDR(trimmed); err != nil {
				problems = append(problems, fmt.Sprintf("分组 %s 的成员 %q 非法，已剔除", g.ID, trimmed))
				continue
			}
			members = append(members, trimmed)
		}
		g.Clients = members

		// 专属上游 ID 去空去重；是否真实存在由上游配置侧在编译匹配表时校验
		if len(g.UpstreamIDs) > 0 {
			seenUp := make(map[string]bool, len(g.UpstreamIDs))
			upstreams := make([]string, 0, len(g.UpstreamIDs))
			for _, raw := range g.UpstreamIDs {
				id := strings.TrimSpace(raw)
				if id == "" || seenUp[id] {
					continue
				}
				seenUp[id] = true
				upstreams = append(upstreams, id)
			}
			g.UpstreamIDs = upstreams
		}
		if g.BlockMode != "" && !IsValidBlockMode(g.BlockMode) {
			problems = append(problems, fmt.Sprintf("分组 %s 的拦截方式 %q 非法，已回落全局", g.ID, g.BlockMode))
			g.BlockMode = ""
		}
		// 编译组级时间计划，丢弃非法条目（坏配置不阻断整体语义）
		if len(g.Schedules) > 0 {
			valid := g.Schedules[:0]
			for i := range g.Schedules {
				if err := NormalizeSchedule(&g.Schedules[i]); err != nil {
					problems = append(problems, fmt.Sprintf("分组 %s 的时间计划 %q 非法，已丢弃: %v", g.ID, g.Schedules[i].Name, err))
					continue
				}
				valid = append(valid, g.Schedules[i])
			}
			g.Schedules = valid
			// 无可用计划时关闭组级计划开关，避免出现「开关开但永不生效」的歧义状态
			if !HasEnabledSchedule(g.Schedules) {
				g.ScheduleEnabled = false
			}
		} else {
			g.ScheduleEnabled = false
		}
		seen[g.ID] = true
		valid = append(valid, g)
	}
	cfg.Groups = valid

	if len(problems) > 0 {
		return fmt.Errorf("%s", strings.Join(problems, "; "))
	}
	return nil
}

// IsValidBlockMode 校验拦截方式取值是否受支持。
func IsValidBlockMode(mode string) bool {
	switch mode {
	case BlockModeNullIP, BlockModeNXDOMAIN, BlockModeRefused:
		return true
	default:
		return false
	}
}

// GroupUpstreamMap 由分组配置汇总出「分组 → 专属上游 ID」映射。
//
// 只包含确实指定了专属上游的启用分组；未指定者不出现在结果中，
// 与「未启用该功能」保持同一语义。
//
// 本方法不假定配置已被 Normalize 处理过：启动路径会直接传入磁盘上的原始配置，
// 因此空 ID 与重复项在此就地剔除。
func (c ClientGroupConfig) GroupUpstreamMap() map[string][]string {
	if !c.Enabled || len(c.Groups) == 0 {
		return nil
	}

	out := make(map[string][]string)
	for _, g := range c.Groups {
		if !g.Enabled || len(g.UpstreamIDs) == 0 {
			continue
		}
		id := strings.TrimSpace(g.ID)
		if id == "" || id == DefaultClientGroupID {
			continue
		}

		seen := make(map[string]bool, len(g.UpstreamIDs))
		ids := make([]string, 0, len(g.UpstreamIDs))
		for _, raw := range g.UpstreamIDs {
			trimmed := strings.TrimSpace(raw)
			if trimmed == "" || seen[trimmed] {
				continue
			}
			seen[trimmed] = true
			ids = append(ids, trimmed)
		}
		if len(ids) == 0 {
			continue
		}
		out[id] = ids
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

// GroupConfig 从客户端配置中提取分组配置。
func (c ClientConfig) GroupConfig() ClientGroupConfig {
	groups := c.Groups
	if groups == nil {
		groups = []ClientGroup{}
	}
	return ClientGroupConfig{Enabled: c.GroupsEnabled, Groups: groups}
}

// Normalize 归一化客户端配置中的分组字段，并将结果写回。
func (c *ClientConfig) Normalize() error {
	if c == nil {
		return nil
	}
	gc := c.GroupConfig()
	err := NormalizeClientGroupConfig(&gc)
	c.Groups = gc.Groups
	return err
}
