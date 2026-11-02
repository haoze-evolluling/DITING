package querylog

import (
	"fmt"
	"sync"
	"testing"
)

func TestRingAppendAndOrder(t *testing.T) {
	r := newRing(3)
	for i := 1; i <= 3; i++ {
		r.append(Record{Timestamp: int64(i), Domain: fmt.Sprintf("d%d.com", i)})
	}
	if r.len() != 3 {
		t.Fatalf("expected len 3, got %d", r.len())
	}
	got, total := r.search(SearchQuery{Limit: 10})
	if total != 3 || len(got) != 3 {
		t.Fatalf("expected 3 entries, got total=%d len=%d", total, len(got))
	}
	// 应为新→旧（时间倒序）
	for i, rec := range got {
		if rec.Timestamp != int64(3-i) {
			t.Fatalf("entry %d out of order: %d", i, rec.Timestamp)
		}
	}
}

func TestRingOverwriteEviction(t *testing.T) {
	r := newRing(2)
	for i := 1; i <= 4; i++ {
		r.append(Record{Timestamp: int64(i)})
	}
	got, total := r.search(SearchQuery{Limit: 10})
	if total != 2 {
		t.Fatalf("expected 2 retained, got %d", total)
	}
	if got[0].Timestamp != 4 || got[1].Timestamp != 3 {
		t.Fatalf("expected retained [4,3] (newest first), got [%d,%d]", got[0].Timestamp, got[1].Timestamp)
	}
}

func TestRingResize(t *testing.T) {
	r := newRing(5)
	for i := 1; i <= 5; i++ {
		r.append(Record{Timestamp: int64(i)})
	}
	r.resize(2)
	got, total := r.search(SearchQuery{Limit: 10})
	if total != 2 {
		t.Fatalf("expected 2 after resize, got %d", total)
	}
	if got[0].Timestamp != 5 || got[1].Timestamp != 4 {
		t.Fatalf("expected most recent [5,4], got [%d,%d]", got[0].Timestamp, got[1].Timestamp)
	}
}

func TestRingSearchOffsetLimit(t *testing.T) {
	r := newRing(10)
	for i := 1; i <= 6; i++ {
		r.append(Record{Timestamp: int64(i)})
	}
	got, total := r.search(SearchQuery{Limit: 2, Offset: 1})
	// 时间倒序为 6,5,4,3,2,1，offset=1 → 从第 2 条起取 2 条：5,4
	if total != 6 {
		t.Fatalf("expected total 6, got %d", total)
	}
	if len(got) != 2 || got[0].Timestamp != 5 || got[1].Timestamp != 4 {
		t.Fatalf("unexpected page: %+v", got)
	}
}

func TestRingSearchEarlyStopByStartMs(t *testing.T) {
	r := newRing(10)
	for i := 1; i <= 6; i++ {
		r.append(Record{Timestamp: int64(i * 1000)})
	}
	got, total := r.search(SearchQuery{StartMs: 4000, Limit: 10})
	if total != 3 {
		t.Fatalf("expected 3 within window, got %d", total)
	}
	// 时间倒序：6000,5000,4000
	if got[0].Timestamp != 6000 || got[2].Timestamp != 4000 {
		t.Fatalf("unexpected order: %+v", got)
	}
}

func TestRingClear(t *testing.T) {
	r := newRing(4)
	r.append(Record{Timestamp: 1})
	r.clear()
	if r.len() != 0 {
		t.Fatalf("expected empty ring, got %d", r.len())
	}
}

func TestRingConcurrentAppend(t *testing.T) {
	r := newRing(1024)
	var wg sync.WaitGroup
	for g := 0; g < 8; g++ {
		wg.Add(1)
		go func(base int) {
			defer wg.Done()
			for i := 0; i < 200; i++ {
				r.append(Record{Timestamp: int64(base*1000 + i)})
			}
		}(g)
	}
	wg.Wait()
	if r.len() != 1024 {
		t.Fatalf("expected full ring 1024, got %d", r.len())
	}
}
