package core

import (
	"log"
	"strings"
	"time"
)

// ReasonServiceScheduleInactive 内置服务的周计划未生效（窗口外）时的判定原因标识。
//
// 与全局分时拦截的 ReasonScheduleInactive 区分开：前者只放行这一个服务，
// 其余规则照常生效；后者是整体放行。查询日志需要能看出是哪一种。
const ReasonServiceScheduleInactive = "SERVICE_SCHEDULE_INACTIVE"

// ServiceIDFromSource 从规则来源标识中取出内置服务 ID。
//
// 来源形如 service:bilibili；非内置服务来源返回 ok=false。
func ServiceIDFromSource(source string) (id string, ok bool) {
	trimmed, found := strings.CutPrefix(source, serviceRuleSourcePrefix)
	if !found {
		return "", false
	}
	trimmed = strings.TrimSpace(trimmed)
	if trimmed == "" {
		return "", false
	}
	return trimmed, true
}

// NormalizeServiceSchedules 编译并过滤服务级周计划。
//
// 语义与全局时间计划一致：
//   - 键不存在的服务恒为生效（未配置计划即无时间限制）；
//   - 键存在但无任何启用计划时同样恒为生效，与全局 HasEnabledSchedule 的判定保持一致；
//   - 键存在且有启用计划时，只有命中窗口才拦截。
//
// 因此「让某服务永不拦截」的正确做法是在服务列表中取消勾选，而不是清空它的计划。
func NormalizeServiceSchedules(raw map[string][]BlockingSchedule) map[string][]BlockingSchedule {
	if len(raw) == 0 {
		return nil
	}

	out := make(map[string][]BlockingSchedule, len(raw))
	// 键序不固定，先按服务 ID 排序处理，使日志输出稳定可比对
	for _, id := range sortedKeys(raw) {
		schedules := raw[id]
		serviceID := strings.TrimSpace(id)
		if serviceID == "" {
			log.Printf("[FilterConfig] 丢弃没有服务 ID 的服务计划")
			continue
		}
		if !ServiceExists(serviceID) {
			log.Printf("[FilterConfig] 忽略未知内置服务的计划: %s", serviceID)
			continue
		}

		compiled := make([]BlockingSchedule, 0, len(schedules))
		for i := range schedules {
			item := schedules[i]
			if err := NormalizeSchedule(&item); err != nil {
				log.Printf("[FilterConfig] 丢弃服务 %s 的非法计划 (%s): %v", serviceID, item.Name, err)
				continue
			}
			compiled = append(compiled, item)
		}
		if len(compiled) == 0 {
			continue
		}
		out[serviceID] = compiled
	}

	if len(out) == 0 {
		return nil
	}
	return out
}

// sortedKeys 返回 map 的键升序排列，便于归一化过程输出稳定的日志。
func sortedKeys(m map[string][]BlockingSchedule) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sortStrings(keys)
	return keys
}

// serviceScheduleBlocks 判断某来源的拦截在当前时刻是否应当生效。
//
// 非内置服务来源、未知服务，以及未配置启用计划的服务一律返回 true
// —— 即「没有时间限制」，与历史行为完全一致。
//
// 先取时刻再加读锁，与 IsBlockingActiveForGroupAt 的写法一致：
// 嵌套 RLock 在已有写者排队时会被阻塞，两次独立的读锁则不会。
func (e *RuleEngine) serviceScheduleBlocks(source string) bool {
	now := e.currentTime()
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.serviceScheduleBlocksAtUnlocked(source, now)
}

// serviceScheduleBlocksAtUnlocked 为 serviceScheduleBlocks 的无锁实现，便于测试注入时钟。
//
// 调用方须已持有 e.mu 读锁（或已通过 currentTime 的只读路径拿到时刻）。
func (e *RuleEngine) serviceScheduleBlocksAtUnlocked(source string, now time.Time) bool {
	if len(e.cfg.ServiceSchedules) == 0 {
		return true
	}
	serviceID, ok := ServiceIDFromSource(source)
	if !ok {
		return true
	}
	schedules, configured := e.cfg.ServiceSchedules[serviceID]
	if !configured || !HasEnabledSchedule(schedules) {
		return true
	}
	return ActiveSchedule(schedules, now)
}

// ServiceScheduleState 单个服务的计划生效状态，供界面展示
type ServiceScheduleState struct {
	ServiceID   string `json:"serviceId"`
	Active      bool   `json:"active"`
	HasSchedule bool   `json:"hasSchedule"`
	// ActiveName 当前命中的计划名；未命中或未配置时为空
	ActiveName string `json:"activeName,omitempty"`
}

// ServiceScheduleStates 返回所有已配置计划的服务在当前时刻的生效状态。
func (e *RuleEngine) ServiceScheduleStates() []ServiceScheduleState {
	e.mu.RLock()
	defer e.mu.RUnlock()

	now := e.currentTime()
	out := make([]ServiceScheduleState, 0, len(e.cfg.ServiceSchedules))
	for _, id := range sortedKeys(e.cfg.ServiceSchedules) {
		schedules := e.cfg.ServiceSchedules[id]
		state := ServiceScheduleState{
			ServiceID:   id,
			Active:      !HasEnabledSchedule(schedules) || ActiveSchedule(schedules, now),
			HasSchedule: HasEnabledSchedule(schedules),
		}
		if hit := FirstActiveSchedule(schedules, now); hit != nil {
			state.ActiveName = hit.Name
		}
		out = append(out, state)
	}
	return out
}

// GetServiceSchedules 返回服务级周计划的副本（深拷贝计划切片，避免调用方改写内部状态）。
func (e *RuleEngine) GetServiceSchedules() map[string][]BlockingSchedule {
	e.mu.RLock()
	defer e.mu.RUnlock()

	if len(e.cfg.ServiceSchedules) == 0 {
		return nil
	}
	out := make(map[string][]BlockingSchedule, len(e.cfg.ServiceSchedules))
	for id, schedules := range e.cfg.ServiceSchedules {
		out[id] = append([]BlockingSchedule(nil), schedules...)
	}
	return out
}
