package main

import (
	"context"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/querylog"
)

func newQueryLogProgram(t *testing.T) *program {
	t.Helper()
	cfg := config.DefaultConfig()
	cfg.QueryLog.DataDir = t.TempDir()
	return &program{
		cfg:      cfg,
		queryLog: querylog.New(cfg.QueryLog),
	}
}

func TestController_QueryLogRecordSearchStats(t *testing.T) {
	prg := newQueryLogProgram(t)
	t.Cleanup(func() { _ = prg.queryLog.Close() })

	prg.queryLog.Record(querylog.Record{Domain: "a.com", QType: "A", Status: querylog.StatusAllowed})
	prg.queryLog.Record(querylog.Record{Domain: "ads.example.com", QType: "A", Status: querylog.StatusBlocked, Blocked: true, FilterRule: "||ads.example.com^"})
	prg.queryLog.Record(querylog.Record{Domain: "a.com", QType: "A", Status: querylog.StatusBlocked, Blocked: true, FilterRule: "||a.com^"})
	prg.queryLog.Record(querylog.Record{Domain: "cdn.a.com", QType: "A", Status: querylog.StatusCached, Cached: true, CacheHit: "fresh"})

	// 检索
	res, err := prg.GetQueryLog(context.Background(), querylog.SearchQuery{Limit: 10})
	if err != nil {
		t.Fatalf("GetQueryLog: %v", err)
	}
	if res.Total != 4 || len(res.Entries) != 4 {
		t.Fatalf("expected 4 entries, got total=%d len=%d", res.Total, len(res.Entries))
	}

	// 带过滤检索
	blocked, err := prg.GetQueryLog(context.Background(), querylog.SearchQuery{Status: querylog.StatusBlocked, Limit: 10})
	if err != nil {
		t.Fatalf("GetQueryLog(blocked): %v", err)
	}
	if blocked.Total != 2 {
		t.Fatalf("expected 2 blocked entries, got %d", blocked.Total)
	}

	// 统计
	stats, err := prg.GetQueryStats(context.Background())
	if err != nil {
		t.Fatalf("GetQueryStats: %v", err)
	}
	if stats.Summary.Queries != 4 || stats.Summary.Blocked != 2 || stats.Summary.Cached != 1 {
		t.Fatalf("unexpected summary: %+v", stats.Summary)
	}
	if len(stats.TopDomains) == 0 || stats.TopDomains[0].Name != "a.com" || stats.TopDomains[0].Count != 2 {
		t.Fatalf("unexpected top domains: %+v", stats.TopDomains)
	}
	if stats.TopBlocked == nil || stats.TopClients == nil || stats.PerHour == nil {
		t.Fatalf("expected non-nil slices in stats payload")
	}
}

func TestController_QueryLogNilSafety(t *testing.T) {
	cfg := config.DefaultConfig()
	prg := &program{cfg: cfg}

	res, err := prg.GetQueryLog(context.Background(), querylog.SearchQuery{})
	if err != nil || res == nil || res.Entries == nil {
		t.Fatalf("expected empty non-nil result, got %+v err=%v", res, err)
	}

	stats, err := prg.GetQueryStats(context.Background())
	if err != nil || stats == nil || stats.TopDomains == nil {
		t.Fatalf("expected empty stats, got %+v err=%v", stats, err)
	}

	if err := prg.ClearQueryLog(context.Background()); err == nil {
		t.Fatalf("expected error when query log not initialized")
	}

	gotCfg, err := prg.GetQueryLogConfig(context.Background())
	if err != nil || gotCfg == nil {
		t.Fatalf("GetQueryLogConfig: %+v err=%v", gotCfg, err)
	}
}

func TestController_UpdateQueryLogConfigPersists(t *testing.T) {
	prg := newQueryLogProgram(t)
	t.Cleanup(func() { _ = prg.queryLog.Close() })

	tmp := t.TempDir() + "/config.json"
	prg.configPath = tmp

	updated := querylog.QueryLogConfig{
		Enabled:       false,
		MaxEntries:    512,
		FileEnabled:   false,
		RetentionDays: 3,
		LogClients:    false,
		DataDir:       prg.cfg.QueryLog.DataDir,
	}
	if err := prg.UpdateQueryLogConfig(context.Background(), updated); err != nil {
		t.Fatalf("UpdateQueryLogConfig: %v", err)
	}
	if prg.cfg.QueryLog.MaxEntries != 512 || prg.cfg.QueryLog.Enabled {
		t.Fatalf("expected program config updated, got %+v", prg.cfg.QueryLog)
	}

	// 重新加载确认已落盘
	loaded, err := config.LoadConfig(tmp)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	if loaded.QueryLog.MaxEntries != 512 || loaded.QueryLog.RetentionDays != 3 || loaded.QueryLog.Enabled {
		t.Fatalf("expected persisted config, got %+v", loaded.QueryLog)
	}

	// 关闭后不再记录
	prg.queryLog.Record(querylog.Record{Domain: "x.com", Status: querylog.StatusAllowed})
	stats, _ := prg.GetQueryStats(context.Background())
	if stats.Summary.Queries != 0 {
		t.Fatalf("expected no records after disabling, got %+v", stats.Summary)
	}
}

func TestController_ClearQueryLog(t *testing.T) {
	prg := newQueryLogProgram(t)
	t.Cleanup(func() { _ = prg.queryLog.Close() })

	prg.queryLog.Record(querylog.Record{Domain: "a.com", Status: querylog.StatusAllowed})
	if err := prg.ClearQueryLog(context.Background()); err != nil {
		t.Fatalf("ClearQueryLog: %v", err)
	}

	res, _ := prg.GetQueryLog(context.Background(), querylog.SearchQuery{Limit: 10})
	if res.Total != 0 {
		t.Fatalf("expected empty log after clear, got total=%d", res.Total)
	}
	stats, _ := prg.GetQueryStats(context.Background())
	if stats.Summary.Queries != 0 {
		t.Fatalf("expected cleared stats, got %+v", stats.Summary)
	}
}

func TestConfig_QueryLogDefaults(t *testing.T) {
	cfg := config.DefaultConfig()
	if !cfg.QueryLog.Enabled || !cfg.QueryLog.FileEnabled || !cfg.QueryLog.LogClients {
		t.Fatalf("expected query log enabled by default: %+v", cfg.QueryLog)
	}
	if cfg.QueryLog.MaxEntries != querylog.DefaultMaxEntries || cfg.QueryLog.RetentionDays != querylog.DefaultRetentionDays {
		t.Fatalf("unexpected default capacities: %+v", cfg.QueryLog)
	}
	if cfg.QueryLog.DataDir == "" {
		t.Fatalf("expected non-empty default data dir")
	}
}
