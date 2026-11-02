package ipc

import "github.com/haoze-evolluling/diting/server/internal/core"

// BlockedServicesResponse 内置阻断服务目录与当前选择状态
type BlockedServicesResponse struct {
	// Services 目录中的全部服务（含规则明细，供界面展开查看）
	Services []core.BlockedService `json:"services"`
	// Groups 服务分组及其服务数量
	Groups []core.BlockedServiceGroup `json:"groups"`
	// BlockedIDs 当前被勾选拦截的服务 ID
	BlockedIDs []string `json:"blockedIds"`
	// BlockedGroups 当前被整组拦截的分组 ID
	BlockedGroups []string `json:"blockedGroups"`
	// ActiveRules 当前选择展开后实际生效的规则条数
	ActiveRules int `json:"activeRules"`
	// Schedules 各服务的每周生效计划（仅包含已配置计划的服务）
	Schedules map[string][]core.BlockingSchedule `json:"schedules"`
	// ScheduleStates 上述计划在当前时刻的生效状态，供界面标注
	ScheduleStates []core.ServiceScheduleState `json:"scheduleStates"`
}

// ConfigureBlockedServicesRequest 更新内置服务拦截选择与周计划。
//
// 三个字段均为可选：省略表示沿用当前值，传空数组/空表表示清空该维度。
// 用指针而非切片本身来区分这两种意图。
type ConfigureBlockedServicesRequest struct {
	IDs    *[]string `json:"ids,omitempty"`
	Groups *[]string `json:"groups,omitempty"`
	// Schedules 传 nil 保持当前值；传 {} 清空全部服务计划
	Schedules *map[string][]core.BlockingSchedule `json:"schedules,omitempty"`
}
