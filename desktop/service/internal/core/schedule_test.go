package core

import (
	"testing"
	"time"
)

func at(y int, mo time.Month, d, h, mi int) time.Time {
	return time.Date(y, mo, d, h, mi, 0, 0, time.Local)
}

func TestParseScheduleClockAndWeekdays(t *testing.T) {
	tests := []struct {
		raw    string
		expect int
		ok     bool
	}{
		{"00:00", 0, true},
		{"9:05", 9*60 + 5, true},
		{"23:59", 23*60 + 59, true},
		{"24:00", 0, false},
		{"12:60", 0, false},
		{"abc", 0, false},
		{"", 0, false},
	}
	for _, tc := range tests {
		got, err := parseScheduleClock(tc.raw)
		if tc.ok && err != nil {
			t.Errorf("parseScheduleClock(%q) 意外报错: %v", tc.raw, err)
			continue
		}
		if !tc.ok && err == nil {
			t.Errorf("parseScheduleClock(%q) 应当报错", tc.raw)
			continue
		}
		if tc.ok && got != tc.expect {
			t.Errorf("parseScheduleClock(%q) = %d，期望 %d", tc.raw, got, tc.expect)
		}
	}

	// 空列表 = 每天
	if mask, err := parseScheduleWeekdays(nil); err != nil || mask != scheduleAllWeekdays {
		t.Errorf("空星期列表应表示每天，得到 mask=%08b err=%v", mask, err)
	}
	// 缩写/全称与大小写兼容
	if mask, err := parseScheduleWeekdays([]string{"MON", "wednesday"}); err != nil {
		t.Errorf("星期解析报错: %v", err)
	} else if mask != (1<<1)|(1<<3) {
		t.Errorf("星期掩码错误: %08b", mask)
	}
	if _, err := parseScheduleWeekdays([]string{"funday"}); err == nil {
		t.Errorf("非法星期应报错")
	}
}

func TestNormalizeSchedule(t *testing.T) {
	s := &BlockingSchedule{Name: "夜间", Start: "23:00", End: "07:00", Enabled: true}
	if err := NormalizeSchedule(s); err != nil {
		t.Fatalf("NormalizeSchedule 报错: %v", err)
	}
	if s.ID == "" || s.Name != "夜间" {
		t.Errorf("ID/Name 自动补全异常: %+v", s)
	}
	if s.startMin != 23*60 || s.endMin != 7*60 || s.weekdayMask != scheduleAllWeekdays {
		t.Errorf("编译产物错误: start=%d end=%d mask=%08b", s.startMin, s.endMin, s.weekdayMask)
	}

	bad := &BlockingSchedule{Start: "8:00", End: "25:00"}
	if err := NormalizeSchedule(bad); err == nil {
		t.Errorf("非法时刻应报错")
	}
}

func TestScheduleIsActiveSameDay(t *testing.T) {
	s := &BlockingSchedule{Enabled: true, Start: "09:00", End: "12:00"}
	// 周一
	if err := NormalizeSchedule(s); err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		when   time.Time
		expect bool
	}{
		{at(2026, 10, 12, 8, 59), false},
		{at(2026, 10, 12, 9, 0), true},
		{at(2026, 10, 12, 11, 59), true},
		{at(2026, 10, 12, 12, 0), false}, // 结束点开区间
	}
	for _, c := range cases {
		if got := s.IsActive(c.when); got != c.expect {
			t.Errorf("IsActive(%s) = %v，期望 %v", c.when.Format(time.RFC3339), got, c.expect)
		}
	}
}

func TestScheduleIsActiveCrossMidnight(t *testing.T) {
	s := &BlockingSchedule{Enabled: true, Start: "23:00", End: "07:00", Weekdays: []string{"fri"}}
	if err := NormalizeSchedule(s); err != nil {
		t.Fatal(err)
	}

	// 周五 2026-10-09 23:30 → 命中（周五起始日）
	if !s.IsActive(at(2026, time.October, 9, 23, 30)) {
		t.Errorf("周五跨夜窗口起始段应命中")
	}
	// 周六 2026-10-10 06:30 → 命中（归属周五）
	if !s.IsActive(at(2026, time.October, 10, 6, 30)) {
		t.Errorf("跨夜次日凌晨应归属起始日命中")
	}
	// 周六 2026-10-10 23:30 → 不命中（周六非生效日）
	if s.IsActive(at(2026, time.October, 10, 23, 30)) {
		t.Errorf("非生效日起始段不应命中")
	}
	// 周五 2026-10-09 22:59 → 不命中
	if s.IsActive(at(2026, time.October, 9, 22, 59)) {
		t.Errorf("窗口前不应命中")
	}
}

func TestScheduleZeroLengthNeverActive(t *testing.T) {
	s := &BlockingSchedule{Enabled: true, Start: "10:00", End: "10:00"}
	if err := NormalizeSchedule(s); err != nil {
		t.Fatal(err)
	}
	for h := 0; h < 24; h++ {
		if s.IsActive(at(2026, 10, 12, h, 0)) {
			t.Fatalf("零长度窗口在 %d 点不应生效", h)
		}
	}
}

func TestScheduleDisabledNeverActive(t *testing.T) {
	s := &BlockingSchedule{Enabled: false, Start: "00:00", End: "23:59"}
	if err := NormalizeSchedule(s); err != nil {
		t.Fatal(err)
	}
	if s.IsActive(at(2026, 10, 12, 12, 0)) {
		t.Errorf("禁用计划不应生效")
	}
	if HasEnabledSchedule([]BlockingSchedule{*s}) {
		t.Errorf("禁用计划不应计入 HasEnabledSchedule")
	}
}

func TestActiveScheduleAndFirst(t *testing.T) {
	s1 := BlockingSchedule{ID: "a", Enabled: true, Start: "00:00", End: "08:00"}
	s2 := BlockingSchedule{ID: "b", Enabled: true, Start: "20:00", End: "23:59"}
	list := []BlockingSchedule{s1, s2}
	for i := range list {
		if err := NormalizeSchedule(&list[i]); err != nil {
			t.Fatal(err)
		}
	}

	if ActiveSchedule(list, at(2026, 10, 12, 3, 0)) != true {
		t.Errorf("凌晨应命中计划 a")
	}
	if ActiveSchedule(list, at(2026, 10, 12, 12, 0)) != false {
		t.Errorf("中午不应命中任何计划")
	}
	if ActiveSchedule(nil, at(2026, 10, 12, 3, 0)) != false {
		t.Errorf("空列表应返回 false")
	}
	if got := FirstActiveSchedule(list, at(2026, 10, 12, 21, 0)); got == nil || got.ID != "b" {
		t.Errorf("应返回命中的计划 b，得到 %+v", got)
	}
	if got := FirstActiveSchedule(list, at(2026, 10, 12, 12, 0)); got != nil {
		t.Errorf("无命中时应返回 nil")
	}
}
