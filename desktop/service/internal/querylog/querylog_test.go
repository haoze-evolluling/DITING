package querylog

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"
)

func TestQueryLogRecordAndSearch(t *testing.T) {
	cfg := DefaultQueryLogConfig()
	cfg.FileEnabled = false
	q := New(cfg)
	defer func() { _ = q.Close() }()

	for i := 1; i <= 5; i++ {
		q.Record(Record{Domain: "d.com", QType: "A", Status: StatusAllowed})
	}
	q.Record(Record{Domain: "ads.com", QType: "A", Status: StatusBlocked, Blocked: true})

	res := q.Search(SearchQuery{Limit: 100})
	if res.Total != 6 || len(res.Entries) != 6 {
		t.Fatalf("expected 6 entries, got total=%d len=%d", res.Total, len(res.Entries))
	}
	// 新→旧：最后写入的 ads.com 应位于首位
	if res.Entries[0].Domain != "ads.com" {
		t.Fatalf("expected newest-first order, got %+v", res.Entries[0])
	}

	blocked := q.Search(SearchQuery{Status: StatusBlocked, Limit: 100})
	if blocked.Total != 1 {
		t.Fatalf("expected 1 blocked, got %d", blocked.Total)
	}
}

func TestQueryLogDisabledRecordsNothing(t *testing.T) {
	cfg := DefaultQueryLogConfig()
	cfg.Enabled = false
	q := New(cfg)
	defer func() { _ = q.Close() }()

	q.Record(Record{Domain: "a.com", Status: StatusAllowed})
	if res := q.Search(SearchQuery{}); res.Total != 0 {
		t.Fatalf("expected nothing recorded when disabled, got %d", res.Total)
	}
	if s := q.Stats(); s.Queries != 0 {
		t.Fatalf("expected empty stats when disabled, got %+v", s)
	}
}

func TestQueryLogPrivacyStripsClient(t *testing.T) {
	cfg := DefaultQueryLogConfig()
	cfg.FileEnabled = false
	cfg.LogClients = false
	q := New(cfg)
	defer func() { _ = q.Close() }()

	q.Record(Record{Domain: "a.com", ClientIP: "192.168.1.9", ClientName: "laptop", Status: StatusAllowed})
	res := q.Search(SearchQuery{})
	if len(res.Entries) != 1 {
		t.Fatalf("expected 1 entry")
	}
	if res.Entries[0].ClientIP != "" || res.Entries[0].ClientName != "" {
		t.Fatalf("expected client info stripped, got %+v", res.Entries[0])
	}
	// 客户端隐私关闭后亦不应进入 Top 客户端
	if tops := q.TopClients(10); len(tops) != 0 {
		t.Fatalf("expected no client rankings, got %+v", tops)
	}
}

func TestQueryLogStatusTimestampNormalization(t *testing.T) {
	cfg := DefaultQueryLogConfig()
	cfg.FileEnabled = false
	q := New(cfg)
	defer func() { _ = q.Close() }()

	// 未知状态回落 allowed；缺失时间戳自动补齐
	q.Record(Record{Domain: "a.com", Status: "weird"})
	res := q.Search(SearchQuery{})
	if res.Entries[0].Status != StatusAllowed {
		t.Fatalf("expected normalized status allowed, got %q", res.Entries[0].Status)
	}
	if res.Entries[0].Timestamp <= 0 {
		t.Fatalf("expected timestamp auto-filled, got %d", res.Entries[0].Timestamp)
	}
}

func TestQueryLogUpdateConfigResize(t *testing.T) {
	cfg := DefaultQueryLogConfig()
	cfg.FileEnabled = false
	cfg.MaxEntries = 10
	q := New(cfg)
	defer func() { _ = q.Close() }()

	for i := 0; i < 8; i++ {
		q.Record(Record{Domain: "d.com", Status: StatusAllowed})
	}

	updated := cfg
	updated.MaxEntries = 3
	if err := q.UpdateConfig(updated); err != nil {
		t.Fatalf("UpdateConfig: %v", err)
	}
	res := q.Search(SearchQuery{Limit: 100})
	if res.Total != 3 {
		t.Fatalf("expected ring shrunk to 3, got %d", res.Total)
	}
}

func TestQueryLogClearRemovesFiles(t *testing.T) {
	dir := t.TempDir()
	cfg := DefaultQueryLogConfig()
	cfg.DataDir = dir
	cfg.RetentionDays = 7
	q := New(cfg)
	if !q.fileOK {
		t.Fatalf("expected writer available for writable temp dir")
	}
	q.Record(Record{Domain: "persist.com", Status: StatusAllowed})
	if err := q.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	// 落盘文件应存在
	files, _ := filepath.Glob(filepath.Join(dir, "querylog-*.jsonl"))
	if len(files) == 0 {
		t.Fatalf("expected a persisted jsonl file")
	}
	data, _ := readAll(files[0])
	if !strings.Contains(data, "persist.com") {
		t.Fatalf("expected persisted record, got %q", data)
	}

	// 重新打开并通过 Search(IncludeFile) 读到落盘历史
	q2 := New(cfg)
	res := q2.Search(SearchQuery{Limit: 10, IncludeFile: true})
	if res.Total == 0 {
		t.Fatalf("expected to read persisted history from disk")
	}

	q2.Clear(true)
	if res2 := q2.Search(SearchQuery{Limit: 10, IncludeFile: true}); res2.Total != 0 {
		t.Fatalf("expected empty after clear, got %d", res2.Total)
	}
	filesAfter, _ := filepath.Glob(filepath.Join(dir, "querylog-*.jsonl"))
	if len(filesAfter) != 0 {
		t.Fatalf("expected files removed, got %v", filesAfter)
	}
	_ = q2.Close()
}

func TestQueryLogSearchFallbackToFileWhenMemoryInsufficient(t *testing.T) {
	dir := t.TempDir()
	cfg := DefaultQueryLogConfig()
	cfg.DataDir = dir
	cfg.MaxEntries = 2 // 内存环仅容纳 2 条

	// 直接写入三天的历史文件中，模拟早于内存环的落盘数据
	dayMs := int64(24 * time.Hour / time.Millisecond)
	now := time.Now().UnixMilli()
	earlier := now - 3*dayMs
	if err := writeFileRecords(dir, writerFilePrefix+time.UnixMilli(earlier).Format(dayLayout)+writerFileSuffix, []Record{
		{Timestamp: earlier, Domain: "old1.com", Status: StatusAllowed},
		{Timestamp: earlier + 1000, Domain: "old2.com", Status: StatusAllowed},
	}); err != nil {
		t.Fatalf("seed file: %v", err)
	}

	q := New(cfg)
	defer func() { _ = q.Close() }()
	q.Record(Record{Domain: "new.com", Status: StatusAllowed})

	res := q.Search(SearchQuery{Limit: 50, IncludeFile: true})
	if res.Total < 3 {
		t.Fatalf("expected fallback to read disk history, got total=%d", res.Total)
	}

	// 不启用落盘回退时仅返回内存命中
	memOnly := q.Search(SearchQuery{Limit: 50, IncludeFile: false})
	if memOnly.Total != 1 {
		t.Fatalf("expected 1 memory-only hit, got %d", memOnly.Total)
	}
}

// ---- 测试辅助 ----

func readAll(path string) (string, error) {
	data, err := os.ReadFile(path)
	return string(data), err
}

func writeFileRecords(dir, name string, recs []Record) error {
	path := filepath.Join(dir, name)
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	for _, r := range recs {
		data, err := json.Marshal(r)
		if err != nil {
			return err
		}
		if _, err := f.Write(append(data, '\n')); err != nil {
			return err
		}
	}
	return nil
}

func TestQueryLogStatsAndTop(t *testing.T) {
	cfg := DefaultQueryLogConfig()
	cfg.FileEnabled = false
	q := New(cfg)
	defer func() { _ = q.Close() }()

	q.Record(Record{Domain: "a.com", ClientIP: "10.0.0.1", DurationMs: 10, Status: StatusAllowed})
	q.Record(Record{Domain: "a.com", ClientIP: "10.0.0.1", DurationMs: 20, Status: StatusAllowed})
	q.Record(Record{Domain: "b.com", ClientIP: "10.0.0.2", DurationMs: 30, Status: StatusBlocked, Blocked: true})

	s := q.Stats()
	if s.Queries != 3 || s.Blocked != 1 || s.Forwarded != 2 {
		t.Fatalf("unexpected summary: %+v", s)
	}
	if s.AvgResponseMs != 20 {
		t.Fatalf("expected avg 20ms, got %f", s.AvgResponseMs)
	}

	tops := q.TopDomains(10)
	if len(tops) != 2 || tops[0].Name != "a.com" || tops[0].Count != 2 {
		t.Fatalf("unexpected top domains: %+v", tops)
	}
	if bl := q.TopBlockedDomains(10); len(bl) != 1 || bl[0].Name != "b.com" {
		t.Fatalf("unexpected top blocked: %+v", bl)
	}
	clients := q.TopClients(10)
	if len(clients) != 2 {
		t.Fatalf("expected 2 clients, got %+v", clients)
	}
	// 客户端排行按计数降序，同计数按名称升序
	sort.Slice(clients, func(i, j int) bool { return clients[i].Name < clients[j].Name })
	if clients[0].Name != "10.0.0.1" || clients[0].Count != 2 {
		t.Fatalf("unexpected client ranking: %+v", clients)
	}
}
