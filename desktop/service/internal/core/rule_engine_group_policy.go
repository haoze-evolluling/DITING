package core

import "time"

// ReasonAllowlistOnly 未命中放行规则且开启「仅白名单」模式时的判定原因标识
const ReasonAllowlistOnly = "ALLOWLIST_ONLY"

// IsBlockingActiveForGroup 判断指定分组当前时刻拦截是否处于生效状态。
func (e *RuleEngine) IsBlockingActiveForGroup(groupID string) bool {
	return e.IsBlockingActiveForGroupAt(groupID, e.currentTime())
}

// IsBlockingActiveForGroupAt 判断指定分组在给定时刻拦截是否生效（便于测试注入时钟）。
//
// 语义（借鉴 blocky config/schedule.go 的 per-group schedule 门控）：
// 分组配置了组级计划开关且存在启用计划时，以组级计划判定生效窗口；
// 否则回落全局计划语义 —— 因此未配置组级计划时行为与历史完全一致。
func (e *RuleEngine) IsBlockingActiveForGroupAt(groupID string, now time.Time) bool {
	e.mu.RLock()
	defer e.mu.RUnlock()

	if g, ok := e.groupByIDUnlocked(groupID); ok && g.ScheduleEnabled && HasEnabledSchedule(g.Schedules) {
		return ActiveSchedule(g.Schedules, now)
	}

	if !e.cfg.ScheduleEnabled || !HasEnabledSchedule(e.cfg.Schedules) {
		return true
	}
	return ActiveSchedule(e.cfg.Schedules, now)
}

// IsAllowlistOnlyForGroup 判断指定分组是否启用「仅白名单」模式（组级覆盖全局）。
//
// 组级字段为布尔零值（false）时表示继承全局配置，无法反向关闭全局开关。
func (e *RuleEngine) IsAllowlistOnlyForGroup(groupID string) bool {
	e.mu.RLock()
	defer e.mu.RUnlock()

	if g, ok := e.groupByIDUnlocked(groupID); ok {
		return g.AllowlistOnly
	}
	return e.cfg.AllowlistOnly
}

// groupByIDUnlocked 按 ID 查找启用中的分组（调用方须持有 e.mu）。
//
// 默认组或分组功能关闭时返回 false，调用方据此回落全局配置。
func (e *RuleEngine) groupByIDUnlocked(groupID string) (*ClientGroup, bool) {
	if groupID == "" || groupID == DefaultClientGroupID || !e.groupCfg.Enabled {
		return nil, false
	}
	for i := range e.groupCfg.Groups {
		if e.groupCfg.Groups[i].ID == groupID {
			return &e.groupCfg.Groups[i], true
		}
	}
	return nil, false
}

// applyAllowlistOnly 在「仅白名单」模式下将未命中放行规则的评估结果改写为阻断。
//
// 判定依据：Action == "allow" 恰为优先级 1（$important 例外）与优先级 3（@@ 例外）
// 的返回形态；pass（未命中任何规则）与 block 均视为需要阻断。
//
// 重写命中一并放行：$dnsrewrite 是用户对该名字最明确的一次表态，
// 把它改写为阻断既违背规则本意，也让「仅白名单」模式下的重写功能形同虚设。
func applyAllowlistOnly(res CheckHostResult) CheckHostResult {
	if res.Blocked || res.Action == "allow" || res.IsRewrite() {
		return res
	}
	return CheckHostResult{
		Blocked: true,
		Action:  "block",
		Reason:  ReasonAllowlistOnly,
	}
}
