package main

import (
	"context"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

func newScheduleProgram(t *testing.T) *program {
	t.Helper()
	cfg := config.DefaultConfig()
	fcfg := core.DefaultFilterConfig()
	fcfg.DataDir = t.TempDir()
	fcfg.Lists = []core.FilterList{}
	cfg.Filter = fcfg

	engine := core.NewRuleEngine(fcfg)
	t.Cleanup(engine.Close)

	return &program{cfg: cfg, filterEngine: engine}
}

func TestController_ScheduleNilSafety(t *testing.T) {
	prg := &program{cfg: config.DefaultConfig()}

	res, err := prg.GetBlockingSchedule(context.Background())
	if err != nil || res == nil {
		t.Fatalf("expected non-nil empty response, got %+v err=%v", res, err)
	}
	if res.Enabled || !res.Active {
		t.Fatalf("nil engine should report disabled but active (常开): %+v", res)
	}
	if res.Schedules == nil {
		t.Fatalf("expected non-nil schedules slice")
	}

	if err := prg.ConfigureBlockingSchedule(context.Background(), ipc.ConfigureScheduleRequest{}); err == nil {
		t.Fatalf("nil engine should return error on configure")
	}
}

func TestController_ScheduleConfigureAndFetch(t *testing.T) {
	prg := newScheduleProgram(t)

	// 初始：计划关闭 → active 恒为 true
	initial, err := prg.GetBlockingSchedule(context.Background())
	if err != nil {
		t.Fatalf("GetBlockingSchedule: %v", err)
	}
	if initial.Enabled || !initial.Active {
		t.Fatalf("unexpected initial state: %+v", initial)
	}

	enabled := true
	schedules := []core.BlockingSchedule{{
		ID: "night", Name: "夜间", Enabled: true, Weekdays: []string{"mon"}, Start: "23:00", End: "07:00",
	}}
	if err := prg.ConfigureBlockingSchedule(context.Background(), ipc.ConfigureScheduleRequest{
		Enabled:   &enabled,
		Schedules: &schedules,
	}); err != nil {
		t.Fatalf("ConfigureBlockingSchedule: %v", err)
	}

	got, err := prg.GetBlockingSchedule(context.Background())
	if err != nil {
		t.Fatalf("GetBlockingSchedule after configure: %v", err)
	}
	if !got.Enabled || len(got.Schedules) != 1 || got.Schedules[0].ID != "night" {
		t.Fatalf("schedule not persisted: %+v", got)
	}
	// 计划已编译：配置副本中不应残留零值时间段
	if cfg := prg.filterEngine.GetConfig(); cfg.Schedules[0].Start != "23:00" {
		t.Fatalf("raw schedule fields lost: %+v", cfg.Schedules[0])
	}
}

func TestController_SchedulePartialUpdateKeepsRules(t *testing.T) {
	prg := newScheduleProgram(t)

	// 先写入自定义规则
	rules := []string{"||ads.example^"}
	if err := prg.SetCustomRules(context.Background(), rules); err != nil {
		t.Fatalf("SetCustomRules: %v", err)
	}

	enabled := true
	if err := prg.ConfigureBlockingSchedule(context.Background(), ipc.ConfigureScheduleRequest{Enabled: &enabled}); err != nil {
		t.Fatalf("ConfigureBlockingSchedule: %v", err)
	}

	cfg := prg.filterEngine.GetConfig()
	if !cfg.ScheduleEnabled {
		t.Fatalf("schedule enabled flag not applied")
	}
	if len(cfg.CustomRules) != 1 || cfg.CustomRules[0] != "||ads.example^" {
		t.Fatalf("custom rules clobbered by schedule update: %v", cfg.CustomRules)
	}
}
