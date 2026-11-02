package main

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

func newClientGroupProgram(t *testing.T) *program {
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

func TestController_ClientGroupsNilSafety(t *testing.T) {
	prg := &program{cfg: config.DefaultConfig()}

	res, err := prg.GetClientGroups(context.Background())
	if err != nil || res == nil {
		t.Fatalf("nil engine 应返回非空响应, got %+v err=%v", res, err)
	}
	if res.Groups == nil {
		t.Fatalf("应返回非 nil 分组切片")
	}
	if err := prg.ConfigureClientGroups(context.Background(), ipc.ConfigureClientGroupsRequest{}); err == nil {
		t.Fatalf("nil engine 配置应返回错误")
	}
}

func TestController_ClientGroupsConfigureAndResolve(t *testing.T) {
	prg := newClientGroupProgram(t)

	enabled := true
	groups := []core.ClientGroup{
		{ID: "kids", Name: "儿童", Enabled: true, Clients: []string{"192.168.1.0/24"}, RuleListIDs: []string{"list-ads"}},
	}
	if err := prg.ConfigureClientGroups(context.Background(), ipc.ConfigureClientGroupsRequest{
		Enabled: &enabled,
		Groups:  &groups,
	}); err != nil {
		t.Fatalf("ConfigureClientGroups: %v", err)
	}

	// 1. 配置回读
	got, err := prg.GetClientGroups(context.Background())
	if err != nil {
		t.Fatalf("GetClientGroups: %v", err)
	}
	if !got.Enabled || len(got.Groups) != 1 || got.Groups[0].ID != "kids" {
		t.Fatalf("分组未生效: %+v", got)
	}

	// 2. 规则引擎侧分组匹配器已构建
	engineGroups := prg.filterEngine.GetClientGroups()
	if !engineGroups.Enabled || len(engineGroups.Groups) != 1 {
		t.Fatalf("规则引擎未同步分组: %+v", engineGroups)
	}

	// 3. 持久化字段已同步到 cfg
	if !prg.cfg.Client.GroupsEnabled || len(prg.cfg.Client.Groups) != 1 {
		t.Fatalf("cfg 未同步分组: %+v", prg.cfg.Client)
	}

	// 4. IP→分组解析器已重建
	if prg.groupResolver == nil {
		t.Fatalf("groupResolver 未重建")
	}
	if id := prg.groupResolver.Resolve(net.ParseIP("192.168.1.9")); id != "kids" {
		t.Fatalf("解析器应命中 kids, 得到 %s", id)
	}
	if id := prg.groupResolver.Resolve(net.ParseIP("10.0.0.1")); id != core.DefaultClientGroupID {
		t.Fatalf("未覆盖地址应回落 default, 得到 %s", id)
	}
}

func TestController_ClientGroupsNormalizeInvalid(t *testing.T) {
	prg := newClientGroupProgram(t)

	groups := []core.ClientGroup{
		{ID: "dup", Name: "A", Enabled: true, Clients: []string{"10.0.0.0/8"}},
		{ID: "dup", Name: "B", Enabled: true},
		{ID: "bad", Name: "C", Enabled: true, Clients: []string{"not-an-ip"}, BlockMode: "nope"},
	}
	if err := prg.ConfigureClientGroups(context.Background(), ipc.ConfigureClientGroupsRequest{Groups: &groups}); err != nil {
		t.Fatalf("归一化问题不应阻断配置: %v", err)
	}

	got, _ := prg.GetClientGroups(context.Background())
	// 重复 ID 被去重；非法成员被剔除；非法拦截方式被清空
	if len(got.Groups) != 2 {
		t.Fatalf("重复分组应被去重, 得到 %+v", got.Groups)
	}
	if got.Groups[1].ID != "bad" || len(got.Groups[1].Clients) != 0 || got.Groups[1].BlockMode != "" {
		t.Fatalf("非法字段未被清理: %+v", got.Groups[1])
	}
}
