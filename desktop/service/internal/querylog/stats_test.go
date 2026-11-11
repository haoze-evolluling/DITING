package querylog

import (
	"testing"
	"time"
)

func fixedClock(t time.Time) func() time.Time {
	return func() time.Time { return t }
}

func TestCollectorSummaryClassification(t *testing.T) {
	c := NewCollector()
	now := time.Date(2026, 10, 13, 12, 30, 0, 0, time.Local)
	c.now = fixedClock(now)

	base := now.UnixMilli()
	// 4 条查询：1 放行、1 拦截、1 缓存命中、1 失败
	c.Record(Record{Timestamp: base, Domain: "a.com", Status: StatusAllowed, DurationMs: 10, ClientIP: "1.1.1.1"})
	c.Record(Record{Timestamp: base + 1, Domain: "ads.com", Status: StatusBlocked, Blocked: true, DurationMs: 1, ClientIP: "1.1.1.1"})
	c.Record(Record{Timestamp: base + 2, Domain: "a.com", Status: StatusCached, Cached: true, DurationMs: 0, ClientIP: "2.2.2.2"})
	c.Record(Record{Timestamp: base + 3, Domain: "x.com", Status: StatusError, DurationMs: 20, ClientIP: "2.2.2.2"})

	s := c.Summary()
	if s.Queries != 4 {
		t.Fatalf("queries=%d want 4", s.Queries)
	}
	if s.Blocked != 1 {
		t.Fatalf("blocked=%d want 1", s.Blocked)
	}
	if s.Cached != 1 {
		t.Fatalf("cached=%d want 1", s.Cached)
	}
	if s.Errors != 1 {
		t.Fatalf("errors=%d want 1", s.Errors)
	}
	if s.Forwarded != 1 {
		t.Fatalf("forwarded=%d want 1", s.Forwarded)
	}
	if s.CacheHitRate <= 0 {
		t.Fatalf("cacheHitRate=%v want >0", s.CacheHitRate)
	}
}

func TestCollectorTopN(t *testing.T) {
	c := NewCollector()
	now := time.Date(2026, 10, 13, 12, 0, 0, 0, time.Local)
	c.now = fixedClock(now)
	base := now.UnixMilli()

	for i := 0; i < 3; i++ {
		c.Record(Record{Timestamp: base, Domain: "hot.com", Status: StatusAllowed, ClientIP: "9.9.9.9"})
	}
	c.Record(Record{Timestamp: base, Domain: "cold.com", Status: StatusAllowed, ClientIP: "8.8.8.8"})
	c.Record(Record{Timestamp: base, Domain: "ads.com", Status: StatusBlocked, Blocked: true, ClientIP: "9.9.9.9"})
	c.Record(Record{Timestamp: base, Domain: "ads.com", Status: StatusBlocked, Blocked: true, ClientIP: "9.9.9.9"})

	top := c.TopDomains(1)
	if len(top) != 1 || top[0].Name != "hot.com" || top[0].Count != 3 {
		t.Fatalf("topDomains unexpected: %+v", top)
	}
	topBlocked := c.TopBlockedDomains(1)
	if len(topBlocked) != 1 || topBlocked[0].Name != "ads.com" || topBlocked[0].Count != 2 {
		t.Fatalf("topBlocked unexpected: %+v", topBlocked)
	}
	topClients := c.TopClients(1)
	if len(topClients) != 1 || topClients[0].Name != "9.9.9.9" {
		t.Fatalf("topClients unexpected: %+v", topClients)
	}
}

func TestCollectorWindowEviction(t *testing.T) {
	c := NewCollector()
	now := time.Date(2026, 10, 13, 12, 0, 0, 0, time.Local)
	c.now = fixedClock(now)

	// 26 小时前的记录应被滚动窗口排除
	old := now.Add(-26 * time.Hour).UnixMilli()
	c.Record(Record{Timestamp: old, Domain: "old.com", Status: StatusAllowed})
	c.now = fixedClock(now)
	c.Record(Record{Timestamp: now.UnixMilli(), Domain: "now.com", Status: StatusAllowed})

	s := c.Summary()
	if s.Queries != 1 {
		t.Fatalf("expected only in-window query counted, got %d", s.Queries)
	}
}

func TestCollectorPerHourPadding(t *testing.T) {
	c := NewCollector()
	now := time.Date(2026, 10, 13, 12, 0, 0, 0, time.Local)
	c.now = fixedClock(now)
	c.Record(Record{Timestamp: now.UnixMilli(), Domain: "a.com", Status: StatusAllowed})

	pts := c.PerHour()
	if len(pts) != statsWindowHours {
		t.Fatalf("expected %d points, got %d", statsWindowHours, len(pts))
	}
	last := pts[len(pts)-1]
	if last.Queries != 1 {
		t.Fatalf("expected last hour 1 query, got %d", last.Queries)
	}
}

func TestCollectorClear(t *testing.T) {
	c := NewCollector()
	c.Record(Record{Timestamp: time.Now().UnixMilli(), Domain: "a.com", Status: StatusAllowed})
	c.Clear()
	if s := c.Summary(); s.Queries != 0 {
		t.Fatalf("expected 0 after clear, got %d", s.Queries)
	}
}
