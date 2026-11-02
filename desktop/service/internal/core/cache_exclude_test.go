package core

import (
	"strings"
	"testing"
)

func TestCacheExcluder_Matching(t *testing.T) {
	ex, err := NewCacheExcluder([]string{`\.local$`, `^ads\.`, `tracker`})
	if err != nil {
		t.Fatalf("NewCacheExcluder: %v", err)
	}

	match := map[string]bool{
		"printer.local":     true,
		"printer.local.":    true, // 尾点被归一化后仍应命中
		"ADS.Example.com":   true, // 大小写不敏感
		"  ads.x.com  ":     true, // 两侧空白被归一化
		"a.tracker.b":       true, // 子串规则
		"example.com":       false,
		"local.example.com": false, // $ 锚定，非后缀
	}
	for domain, want := range match {
		if got := ex.IsExcluded(domain); got != want {
			t.Errorf("IsExcluded(%q) = %v, want %v", domain, got, want)
		}
	}
	if ex.Size() != 3 {
		t.Fatalf("expected 3 compiled rules, got %d", ex.Size())
	}
}

// 非法规则不应让整组规则失效，但必须被明确报告
func TestCacheExcluder_InvalidPatternsReported(t *testing.T) {
	ex, err := NewCacheExcluder([]string{`valid\.test$`, `[unclosed`})
	if err == nil {
		t.Fatal("expected an error naming the invalid pattern")
	}
	if ex.Size() != 1 {
		t.Fatalf("the valid rule must survive, got %d", ex.Size())
	}
	if !ex.IsExcluded("a.valid.test") {
		t.Fatal("the valid rule must still take effect")
	}
	if !strings.Contains(err.Error(), "非法") {
		t.Fatalf("error should describe the problem: %v", err)
	}
}

func TestCacheExcluder_EmptyIsNoOp(t *testing.T) {
	ex, err := NewCacheExcluder(nil)
	if err != nil {
		t.Fatalf("NewCacheExcluder(nil): %v", err)
	}
	if ex.IsExcluded("anything.test") {
		t.Fatal("an empty rule set must never exclude anything")
	}

	// nil 接收者同样安全，调用方无需判空
	var nilEx *CacheExcluder
	if nilEx.IsExcluded("anything.test") {
		t.Fatal("a nil excluder must never exclude anything")
	}
	if nilEx.Size() != 0 || nilEx.Hits() != 0 || nilEx.Patterns() != nil {
		t.Fatal("a nil excluder must report empty state")
	}
}

func TestCacheExcluder_BlankAndOversizedDropped(t *testing.T) {
	long := strings.Repeat("a", maxCacheExcludePatternLen+1)
	ex, err := NewCacheExcluder([]string{"   ", long, `ok\.test$`})
	if err == nil {
		t.Fatal("the oversized pattern must be reported")
	}
	if ex.Size() != 1 {
		t.Fatalf("only the valid rule should remain, got %d", ex.Size())
	}
}

func TestCacheExcluder_CountLimit(t *testing.T) {
	patterns := make([]string, 0, maxCacheExcludePatterns+10)
	for i := 0; i < maxCacheExcludePatterns+10; i++ {
		patterns = append(patterns, "\\bdomain"+string(rune('a'+i%26))+string(rune('0'+i%10))+"\\.test$")
	}

	ex, err := NewCacheExcluder(patterns)
	if err == nil {
		t.Fatal("exceeding the pattern cap must be reported")
	}
	if ex.Size() != maxCacheExcludePatterns {
		t.Fatalf("expected the cap %d, got %d", maxCacheExcludePatterns, ex.Size())
	}
}

func TestCacheExcluder_Hits(t *testing.T) {
	ex, _ := NewCacheExcluder([]string{`skip\.test$`})
	if ex.Hits() != 0 {
		t.Fatal("no hits before any query")
	}
	ex.IsExcluded("a.skip.test")
	ex.IsExcluded("b.other.test")
	if ex.Hits() != 1 {
		t.Fatalf("hits = %d, want 1", ex.Hits())
	}
}

// 排除逻辑挂在缓存实例上，配置热更新后应立即生效
func TestDNSCache_ExcludeConfigHotReload(t *testing.T) {
	cfg := DefaultCacheConfig()
	cache := NewDNSCache(cfg)
	defer cache.Close()

	if cache.IsExcluded("temp.local") {
		t.Fatal("no rules configured yet")
	}

	cfg.ExcludePatterns = []string{`\.local$`}
	cache.UpdateConfig(cfg)
	if !cache.IsExcluded("temp.local") {
		t.Fatal("the new rule must take effect after a hot reload")
	}

	// 规则被写坏时保留上一次可用的规则集，而不是整体放开
	cfg.ExcludePatterns = []string{`[unclosed`}
	cache.UpdateConfig(cfg)
	if !cache.IsExcluded("temp.local") {
		t.Fatal("a malformed update must not silently drop the working rule set")
	}
}

// 清空规则列表必须真正放开缓存
func TestDNSCache_ExcludeCleared(t *testing.T) {
	cfg := DefaultCacheConfig()
	cfg.ExcludePatterns = []string{`\.local$`}
	cache := NewDNSCache(cfg)
	defer cache.Close()

	if !cache.IsExcluded("a.local") {
		t.Fatal("setup failed")
	}
	cfg.ExcludePatterns = nil
	cache.UpdateConfig(cfg)
	if cache.IsExcluded("a.local") {
		t.Fatal("clearing the rules must stop excluding")
	}
}
