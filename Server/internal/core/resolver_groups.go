package core

import (
	"context"
	"fmt"
	"strings"

	"github.com/miekg/dns"
)

// SetGroupUpstreams 按客户端分组指定专属上游（值为主链路中已配置的上游 ID）。
//
// 传空映射即关闭该功能，所有分组回落主链路。
// 未知的上游 ID 会被忽略并汇总为错误，但已生效的部分仍会保留——
// 分组配置与上游列表是两份独立持久化的配置，任一侧的中间状态都不应让服务不可用。
func (r *CoreResolver) SetGroupUpstreams(ids map[string][]string) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	return r.applyGroupUpstreamsLocked(ids)
}

// applyGroupUpstreamsLocked 归一化并落实分组上游映射（调用方需持有 r.mu 写锁）
func (r *CoreResolver) applyGroupUpstreamsLocked(ids map[string][]string) error {
	if len(ids) == 0 {
		r.groupUpstreamIDs = nil
		r.groupUpstreams = nil
		return nil
	}

	// 按 ID 建立索引；同一 ID 在多条链上重复时以主链路为准
	byID := make(map[string]*ConfiguredProvider, len(r.providers))
	for _, p := range r.providers {
		if p != nil && p.ID != "" {
			byID[p.ID] = p
		}
	}

	resolved := make(map[string][]*ConfiguredProvider, len(ids))
	stored := make(map[string][]string, len(ids))
	var problems []string

	for group, list := range ids {
		group = strings.TrimSpace(group)
		if group == "" || group == DefaultClientGroupID {
			if len(list) > 0 {
				problems = append(problems, fmt.Sprintf("分组 %q 为保留组，不能绑定专属上游", group))
			}
			continue
		}

		seen := make(map[string]bool, len(list))
		providers := make([]*ConfiguredProvider, 0, len(list))
		cleanIDs := make([]string, 0, len(list))
		for _, rawID := range list {
			id := strings.TrimSpace(rawID)
			if id == "" || seen[id] {
				continue
			}
			seen[id] = true
			p, ok := byID[id]
			if !ok {
				problems = append(problems, fmt.Sprintf("分组 %s 引用了不存在的上游 %q", group, id))
				continue
			}
			providers = append(providers, p)
			cleanIDs = append(cleanIDs, id)
		}

		if len(providers) == 0 {
			continue
		}
		resolved[group] = providers
		stored[group] = cleanIDs
	}

	r.groupUpstreamIDs = stored
	r.groupUpstreams = resolved

	if len(problems) > 0 {
		return fmt.Errorf("%s", strings.Join(problems, "; "))
	}
	return nil
}

// HasGroupUpstreams 判断该分组是否配置了专属上游
func (r *CoreResolver) HasGroupUpstreams(group string) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if len(r.groupUpstreams) == 0 {
		return false
	}
	return len(r.groupUpstreams[strings.TrimSpace(group)]) > 0
}

// ExchangeForGroup 使用该分组的专属上游解析结构化请求。
//
// 分组未配置专属上游时返回错误，由调用方决定回落策略——
// 调用方不应在此处猜测意图。
//
// 与全局回退链的关系：分组专属上游**不会**跨到全局回退链。
// 专属上游通常承载的是策略选择（如面向儿童的过滤解析器），
// 在其不可用时改走默认上游会静默绕过该策略，与用户设置分组的本意相反。
// 组内仍按当前调度模式在主备节点之间自动容灾。
func (r *CoreResolver) ExchangeForGroup(ctx context.Context, group string, req *dns.Msg) (*dns.Msg, error) {
	if req == nil {
		return nil, fmt.Errorf("nil dns request")
	}

	providers, mode, err := r.groupChain(group)
	if err != nil {
		return nil, err
	}

	rawQuery, err := req.Pack()
	if err != nil {
		return nil, fmt.Errorf("pack dns query: %w", err)
	}

	rawResp, err := r.scheduler.Resolve(ctx, mode, providers, rawQuery)
	if err != nil {
		return nil, err
	}

	resp := new(dns.Msg)
	if err := resp.Unpack(rawResp); err != nil {
		return nil, fmt.Errorf("unpack dns response: %w", err)
	}
	resp.Id = req.Id
	return resp, nil
}

// groupChain 取出该分组的上游链与当前调度模式
func (r *CoreResolver) groupChain(group string) ([]*ConfiguredProvider, string, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	providers := r.groupUpstreams[strings.TrimSpace(group)]
	if len(providers) == 0 {
		return nil, "", fmt.Errorf("client group %q has no dedicated upstream", group)
	}
	return providers, r.mode, nil
}

// GroupUpstreamIDs 返回当前生效的分组上游映射（副本），供状态展示
func (r *CoreResolver) GroupUpstreamIDs() map[string][]string {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if len(r.groupUpstreamIDs) == 0 {
		return nil
	}
	out := make(map[string][]string, len(r.groupUpstreamIDs))
	for group, ids := range r.groupUpstreamIDs {
		out[group] = append([]string(nil), ids...)
	}
	return out
}
