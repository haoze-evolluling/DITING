package querylog

import (
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// testClock 支持并发安全地推进的测试时钟。
type testClock struct {
	nanos atomic.Int64
}

func newTestClock(t time.Time) *testClock {
	c := &testClock{}
	c.nanos.Store(t.UnixNano())
	return c
}

func (c *testClock) now() time.Time { return time.Unix(0, c.nanos.Load()) }

func (c *testClock) set(t time.Time) { c.nanos.Store(t.UnixNano()) }

func TestWriterAppendAndFlush(t *testing.T) {
	dir := t.TempDir()
	clk := newTestClock(time.Date(2026, 10, 13, 10, 0, 0, 0, time.Local))
	w, err := newWriter(dir, 7, writerOptions{clock: clk.now})
	if err != nil {
		t.Fatalf("newWriter: %v", err)
	}
	w.enqueue(Record{Timestamp: 1, Domain: "a.com", Status: StatusAllowed})
	w.enqueue(Record{Timestamp: 2, Domain: "b.com", Status: StatusBlocked, Blocked: true})
	if err := w.close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	files := w.listFiles()
	if len(files) != 1 {
		t.Fatalf("expected 1 file, got %d", len(files))
	}
	data, err := os.ReadFile(files[0])
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 lines, got %d: %q", len(lines), string(data))
	}
	if !strings.Contains(lines[0], "a.com") || !strings.Contains(lines[1], "b.com") {
		t.Fatalf("unexpected content: %v", lines)
	}
}

func TestWriterDayRotation(t *testing.T) {
	dir := t.TempDir()
	day1 := time.Date(2026, 10, 13, 23, 59, 0, 0, time.Local)
	clk := newTestClock(day1)
	// 直接构造写入器并同步调用写路径，避免 run goroutine 的时序不确定性
	w := &writer{dir: dir, retentionDays: 7, clock: clk.now}

	w.writeRecord(Record{Timestamp: day1.UnixMilli(), Domain: "day1.com", Status: StatusAllowed})

	day2 := time.Date(2026, 10, 14, 0, 1, 0, 0, time.Local)
	clk.set(day2)
	w.writeRecord(Record{Timestamp: day2.UnixMilli(), Domain: "day2.com", Status: StatusAllowed})
	w.flush()
	w.closeFile()

	files := w.listFiles()
	if len(files) != 2 {
		t.Fatalf("expected 2 files after rotation, got %d: %v", len(files), files)
	}
	// 校验两份文件各含一条且内容正确
	for i, want := range []string{"day1.com", "day2.com"} {
		data, err := os.ReadFile(files[i])
		if err != nil {
			t.Fatalf("read %s: %v", files[i], err)
		}
		if !strings.Contains(string(data), want) {
			t.Fatalf("file %d expected %q, got %q", i, want, string(data))
		}
	}
}

func TestWriterRetentionCleanup(t *testing.T) {
	dir := t.TempDir()
	// 预先放置一份过期文件
	oldDay := time.Now().AddDate(0, 0, -30)
	oldName := writerFilePrefix + oldDay.Format(dayLayout) + writerFileSuffix
	oldPath := filepath.Join(dir, oldName)
	if err := os.WriteFile(oldPath, []byte(`{"ts":1}`+"\n"), 0644); err != nil {
		t.Fatalf("seed old file: %v", err)
	}

	w, err := newWriter(dir, 7, writerOptions{})
	if err != nil {
		t.Fatalf("newWriter: %v", err)
	}
	// cleanup 在 run 启动时执行，等待其完成
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(oldPath); os.IsNotExist(err) {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	_ = w.close()

	if _, err := os.Stat(oldPath); !os.IsNotExist(err) {
		t.Fatalf("expected old file removed, still present")
	}
}

func TestWriterEnqueueDropsWhenFull(t *testing.T) {
	// 构造一个未启动 run 的写入器，队列即刻写满
	w := &writer{ch: make(chan Record, 1)}
	if !w.enqueue(Record{Domain: "a.com"}) {
		t.Fatalf("first enqueue should succeed")
	}
	if w.enqueue(Record{Domain: "b.com"}) {
		t.Fatalf("second enqueue should drop when full")
	}
}

func TestWriterUnwritableDir(t *testing.T) {
	// 用一个不存在的父目录下的路径，且父目录为文件，制造 MkdirAll 失败
	dir := t.TempDir()
	f := filepath.Join(dir, "afile")
	if err := os.WriteFile(f, []byte("x"), 0644); err != nil {
		t.Fatalf("write file: %v", err)
	}
	if _, err := newWriter(filepath.Join(f, "sub"), 7, writerOptions{}); err == nil {
		t.Fatalf("expected error for unwritable dir")
	}
}
