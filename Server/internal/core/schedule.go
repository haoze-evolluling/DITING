package core

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// scheduleWeekdayKeys 标准星期键名，索引与 time.Weekday 对齐
var scheduleWeekdayKeys = []string{"sun", "mon", "tue", "wed", "thu", "fri", "sat"}

const (
	// scheduleMinutesPerDay 一天的分钟数
	scheduleMinutesPerDay = 24 * 60
	// scheduleAllWeekdays 全周位掩码（bit0=周日 ... bit6=周六）
	scheduleAllWeekdays uint8 = 0x7F
)

// ReasonScheduleInactive 拦截计划未生效（窗口外）时的判定原因标识
const ReasonScheduleInactive = "SCHEDULE_INACTIVE"

// BlockingSchedule 描述一条分时拦截（时间计划）规则。
//
// 设计借鉴 blocky config/schedule.go 与 dnscrypt-proxy time_ranges.go：
// 编译为「周掩码 + 两个分钟整数」，判定零分配；End 早于 Start 表示跨夜窗口。
type BlockingSchedule struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	Enabled  bool     `json:"enabled"`
	Weekdays []string `json:"weekdays"` // "mon".."sun"，空表示每天生效
	Start    string   `json:"start"`    // "HH:MM"
	End      string   `json:"end"`      // "HH:MM"，早于 Start 即跨夜

	startMin    int   // 编译产物：起始分钟
	endMin      int   // 编译产物：结束分钟
	weekdayMask uint8 // 编译产物：生效星期位掩码
}

// parseScheduleClock 解析 "HH:MM" 时刻为当日分钟数。
func parseScheduleClock(raw string) (int, error) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return 0, fmt.Errorf("时刻不能为空")
	}
	parts := strings.Split(s, ":")
	if len(parts) != 2 {
		return 0, fmt.Errorf("时刻格式应为 HH:MM，得到 %q", raw)
	}
	hour, err := strconv.Atoi(strings.TrimSpace(parts[0]))
	if err != nil || hour < 0 || hour > 23 {
		return 0, fmt.Errorf("小时非法: %q", raw)
	}
	minute, err := strconv.Atoi(strings.TrimSpace(parts[1]))
	if err != nil || minute < 0 || minute > 59 {
		return 0, fmt.Errorf("分钟非法: %q", raw)
	}
	return hour*60 + minute, nil
}

// parseScheduleWeekdays 将星期键名列表编译为位掩码，空列表表示每天生效。
func parseScheduleWeekdays(days []string) (uint8, error) {
	if len(days) == 0 {
		return scheduleAllWeekdays, nil
	}
	var mask uint8
	for _, raw := range days {
		key := strings.ToLower(strings.TrimSpace(raw))
		if len(key) > 3 {
			key = key[:3]
		}
		idx := -1
		for i, k := range scheduleWeekdayKeys {
			if k == key {
				idx = i
				break
			}
		}
		if idx < 0 {
			return 0, fmt.Errorf("星期非法: %q", raw)
		}
		mask |= 1 << uint(idx)
	}
	return mask, nil
}

// NormalizeSchedule 校验并编译单条时间计划。
//
// 返回错误时调用方应丢弃该条计划（坏配置不阻断拦截常开语义）。
func NormalizeSchedule(s *BlockingSchedule) error {
	if s == nil {
		return fmt.Errorf("计划为空")
	}
	s.ID = strings.TrimSpace(s.ID)
	if s.ID == "" {
		s.ID = fmt.Sprintf("schedule-%d", time.Now().UnixNano())
	}
	s.Name = strings.TrimSpace(s.Name)
	if s.Name == "" {
		s.Name = s.ID
	}

	startMin, err := parseScheduleClock(s.Start)
	if err != nil {
		return err
	}
	endMin, err := parseScheduleClock(s.End)
	if err != nil {
		return err
	}
	mask, err := parseScheduleWeekdays(s.Weekdays)
	if err != nil {
		return err
	}

	s.startMin = startMin
	s.endMin = endMin
	s.weekdayMask = mask
	return nil
}

// IsActive 判定该计划在给定时刻是否处于拦截生效窗口内。
func (s *BlockingSchedule) IsActive(now time.Time) bool {
	if s == nil || !s.Enabled || s.weekdayMask == 0 {
		return false
	}
	// 起止相同视为零长度窗口，永不生效
	if s.startMin == s.endMin {
		return false
	}

	nowMin := now.Hour()*60 + now.Minute()
	today := uint8(1) << uint(now.Weekday())

	if s.startMin < s.endMin {
		// 当日窗口 [start, end)
		if nowMin >= s.startMin && nowMin < s.endMin {
			return s.weekdayMask&today != 0
		}
		return false
	}

	// 跨夜窗口：本日 [start, 24:00) 或次日 [00:00, end)，星期归属按窗口起始日
	if nowMin >= s.startMin {
		return s.weekdayMask&today != 0
	}
	if nowMin < s.endMin {
		yesterday := uint8(1) << uint((now.Weekday()+6)%7)
		return s.weekdayMask&yesterday != 0
	}
	return false
}

// ActiveSchedule 判断给定时刻是否命中任一启用且非空的时间计划。
//
// 注意：空计划列表返回 false（是否常开由调用方结合开关语义决定）。
func ActiveSchedule(schedules []BlockingSchedule, now time.Time) bool {
	for i := range schedules {
		if schedules[i].IsActive(now) {
			return true
		}
	}
	return false
}

// HasEnabledSchedule 判断计划列表中是否存在已启用条目。
func HasEnabledSchedule(schedules []BlockingSchedule) bool {
	for i := range schedules {
		if schedules[i].Enabled {
			return true
		}
	}
	return false
}

// FirstActiveSchedule 返回首个命中的启用计划（供 UI 展示当前生效项）。
func FirstActiveSchedule(schedules []BlockingSchedule, now time.Time) *BlockingSchedule {
	for i := range schedules {
		if schedules[i].IsActive(now) {
			return &schedules[i]
		}
	}
	return nil
}
