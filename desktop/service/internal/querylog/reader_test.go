package querylog

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// writeJSONL 将若干记录写入指定文件（按给定顺序，即时间递增）。
func writeJSONL(t *testing.T, path string, recs []Record) {
	t.Helper()
	f, err := os.Create(path)
	if err != nil {
		t.Fatalf("create %s: %v", path, err)
	}
	defer f.Close()
	for _, r := range recs {
		data, _ := json.Marshal(r)
		if _, err := f.Write(append(data, '\n')); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
}

func TestReadFileReverseNewestFirst(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "querylog-20261013.jsonl")
	recs := []Record{
		{Timestamp: 1000, Domain: "a.com", Status: StatusAllowed},
		{Timestamp: 2000, Domain: "b.com", Status: StatusAllowed},
		{Timestamp: 3000, Domain: "c.com", Status: StatusBlocked, Blocked: true},
	}
	writeJSONL(t, path, recs)

	var got []Record
	if err := readFileReverse(path, func(r Record) bool {
		got = append(got, r)
		return true
	}); err != nil {
		t.Fatalf("readFileReverse: %v", err)
	}
	if len(got) != 3 {
		t.Fatalf("expected 3, got %d", len(got))
	}
	if got[0].Timestamp != 3000 || got[1].Timestamp != 2000 || got[2].Timestamp != 1000 {
		t.Fatalf("expected newest-first order, got %+v", got)
	}
}

func TestReadFileReverseSkipsCorruptLines(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "querylog-20261013.jsonl")
	content := `{"ts":1000,"domain":"a.com","status":"allowed"}
this is not json
{"ts":2000,"domain":"b.com","status":"allowed"}
`
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	var got []Record
	_ = readFileReverse(path, func(r Record) bool {
		got = append(got, r)
		return true
	})
	if len(got) != 2 {
		t.Fatalf("expected 2 valid records, got %d", len(got))
	}
}

func TestSearchFilesReverseEarlyStop(t *testing.T) {
	dir := t.TempDir()
	// 两个文件，跨天
	day1 := "querylog-20261012.jsonl"
	day2 := "querylog-20261013.jsonl"
	writeJSONL(t, filepath.Join(dir, day1), []Record{
		{Timestamp: 1000, Domain: "old1.com", Status: StatusAllowed},
		{Timestamp: 2000, Domain: "old2.com", Status: StatusAllowed},
	})
	writeJSONL(t, filepath.Join(dir, day2), []Record{
		{Timestamp: 3000, Domain: "new1.com", Status: StatusAllowed},
		{Timestamp: 4000, Domain: "new2.com", Status: StatusAllowed},
	})
	// listFiles 升序：[day1, day2]
	paths := []string{filepath.Join(dir, day1), filepath.Join(dir, day2)}

	var hits []Record
	searchFilesReverse(paths, SearchQuery{Limit: 10}, 2, false, func(r Record) bool {
		hits = append(hits, r)
		return len(hits) >= 2
	})
	if len(hits) != 2 {
		t.Fatalf("expected 2 hits, got %d", len(hits))
	}
	// 新→旧：应先返回 day2 的 4000、3000
	if hits[0].Timestamp != 4000 || hits[1].Timestamp != 3000 {
		t.Fatalf("expected newest first, got %+v", hits)
	}
}

func TestFileDateMs(t *testing.T) {
	ms := fileDateMs(filepath.Join("x", "querylog-20261013.jsonl"))
	want := time.Date(2026, 10, 13, 0, 0, 0, 0, time.Local).UnixMilli()
	if ms != want {
		t.Fatalf("fileDateMs=%d want %d", ms, want)
	}
	if fileDateMs("garbage.txt") != 0 {
		t.Fatalf("expected 0 for non-matching name")
	}
}

// Total 必须是全量命中数，不能随 offset 截断：否则前端按 Total 算出的
// 页数在第 1 页就只有 1 页，历史记录永远翻不到（BUG-65）。
func TestSearchFilesTotalStableAcrossOffsets(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "querylog-20261012.jsonl")
	recs := make([]Record, 0, 100)
	for i := 0; i < 100; i++ {
		recs = append(recs, Record{Timestamp: int64(1000 + i), Domain: "h.test", Status: StatusAllowed})
	}
	writeJSONL(t, path, recs)
	paths := []string{path}

	for _, offset := range []int{0, 50, 200} {
		// 与 searchFiles 相同：候选只需补足 offset+limit 窗口内的部分
		need := offset + 10
		var hits []Record
		total := searchFilesReverse(paths, SearchQuery{Limit: 10}, need, true, func(r Record) bool {
			if len(hits) < need {
				hits = append(hits, r)
			}
			// 与 searchFiles 一致：不请求提前停止，计数模式自行决定何时不再追加
			return false
		})
		if total != 100 {
			t.Fatalf("offset=%d 时 Total=%d，应为 100", offset, total)
		}
		if got := len(hits); got > need {
			t.Fatalf("offset=%d 时候选数 %d 超过 need=%d", offset, got, need)
		}
	}
}
