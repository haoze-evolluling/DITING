package core

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

// listTestEngine 构建仅含一条 HTTP 订阅源的引擎（缓存目录为空）。
func listTestEngine(t *testing.T, url string) (*RuleEngine, string) {
	t.Helper()
	dir := t.TempDir()
	cfg := DefaultFilterConfig()
	cfg.DataDir = dir
	cfg.CustomRules = []string{}
	cfg.Lists = []FilterList{{ID: "list-a", Name: "测试源", URL: url, Enabled: true}}
	engine := NewRuleEngine(cfg)
	t.Cleanup(engine.Close)
	return engine, dir
}

// TestRefreshListETagNotModified 校验条件请求：首次 200 带回 ETag，二次命中 304 时仅刷新状态。
func TestRefreshListETagNotModified(t *testing.T) {
	var hits atomic.Int32
	var secondReqETag string
	var secondReqModified string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits.Add(1) > 1 {
			secondReqETag = r.Header.Get("If-None-Match")
			secondReqModified = r.Header.Get("If-Modified-Since")
			if secondReqETag == `"v1"` {
				w.WriteHeader(http.StatusNotModified)
				return
			}
		}
		w.Header().Set("ETag", `"v1"`)
		w.Header().Set("Last-Modified", "Wed, 01 Oct 2025 00:00:00 GMT")
		_, _ = w.Write([]byte("||ads.example.com^\n"))
	}))
	defer srv.Close()

	engine, dir := listTestEngine(t, srv.URL)

	if err := engine.RefreshList("list-a"); err != nil {
		t.Fatalf("首次刷新失败: %v", err)
	}
	if got := engine.GetFilterLists()[0]; got.LastStatus != ListStatusOK || got.RulesCount != 1 {
		t.Fatalf("首次刷新状态异常: %+v", got)
	}
	if got := engine.GetFilterLists()[0].ETag; got != `"v1"` {
		t.Fatalf("ETag 未记录: %q", got)
	}

	// 二次刷新应携带协商凭证并命中 304
	if err := engine.RefreshList("list-a"); err != nil {
		t.Fatalf("二次刷新失败: %v", err)
	}
	if secondReqETag != `"v1"` || secondReqModified == "" {
		t.Fatalf("条件请求头缺失: etag=%q modified=%q", secondReqETag, secondReqModified)
	}
	list := engine.GetFilterLists()[0]
	if list.LastStatus != ListStatusUnchanged {
		t.Fatalf("304 应标记 unchanged, 得到 %q", list.LastStatus)
	}
	if list.RulesCount != 1 {
		t.Fatalf("304 后规则数应保持不变, 得到 %d", list.RulesCount)
	}
	if !engine.Match("ads.example.com", 1).Blocked {
		t.Fatalf("304 后规则应继续生效")
	}
	_ = dir
}

// TestRefreshListTransientErrorKeepsCache 校验传输失败时保留本地缓存且不清零规则。
func TestRefreshListTransientErrorKeepsCache(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("||ads.example.com^\n"))
	}))
	engine, dir := listTestEngine(t, srv.URL)

	if err := engine.RefreshList("list-a"); err != nil {
		t.Fatalf("首次刷新失败: %v", err)
	}
	// 关闭服务端模拟网络不可达
	srv.Close()

	if err := engine.RefreshList("list-a"); err != nil {
		t.Fatalf("传输失败应降级沿用缓存而非报错: %v", err)
	}
	list := engine.GetFilterLists()[0]
	if list.LastStatus != ListStatusCached {
		t.Fatalf("应标记 cached, 得到 %q", list.LastStatus)
	}
	if list.LastError == "" {
		t.Fatalf("cached 状态应附带错误原因")
	}
	if !engine.Match("ads.example.com", 1).Blocked {
		t.Fatalf("传缓存保留后规则应继续生效")
	}
	// 缓存文件应原样存在
	if _, err := os.Stat(filepath.Join(dir, "list-a.txt")); err != nil {
		t.Fatalf("缓存文件应保留: %v", err)
	}
}

// TestRefreshListHTTPErrorFails 校验 HTTP 4xx/5xx 照实报错（不沿用缓存）。
func TestRefreshListHTTPErrorFails(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	defer srv.Close()

	engine, _ := listTestEngine(t, srv.URL)
	if err := engine.RefreshList("list-a"); err == nil {
		t.Fatalf("HTTP 500 应返回错误")
	}
	if got := engine.GetFilterLists()[0].LastStatus; got != ListStatusFailed {
		t.Fatalf("应标记 failed, 得到 %q", got)
	}
}

// TestRefreshListAtomicWriteNoTempLeftover 校验原子写入不留 .tmp 残留。
func TestRefreshListAtomicWriteNoTempLeftover(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("||ads.example.com^\n||track.example.com^\n"))
	}))
	defer srv.Close()

	engine, dir := listTestEngine(t, srv.URL)
	if err := engine.RefreshList("list-a"); err != nil {
		t.Fatalf("刷新失败: %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("读取缓存目录失败: %v", err)
	}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".tmp") {
			t.Fatalf("存在临时文件残留: %s", e.Name())
		}
	}
	if engine.GetFilterLists()[0].RulesCount != 2 {
		t.Fatalf("规则数应为 2, 得到 %d", engine.GetFilterLists()[0].RulesCount)
	}
}

// TestRefreshAllListsUnchangedSkipsRebuild 校验全量 304 时不重建索引且规则继续生效。
func TestRefreshAllListsUnchangedSkipsRebuild(t *testing.T) {
	var first atomic.Bool
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !first.CompareAndSwap(false, true) {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.Header().Set("ETag", `"v1"`)
		_, _ = w.Write([]byte("||ads.example.com^\n"))
	}))
	defer srv.Close()

	engine, _ := listTestEngine(t, srv.URL)
	if err := engine.RefreshAllLists(); err != nil {
		t.Fatalf("首次全量刷新失败: %v", err)
	}
	if err := engine.RefreshAllLists(); err != nil {
		t.Fatalf("二次全量刷新失败: %v", err)
	}
	if got := engine.GetFilterLists()[0].LastStatus; got != ListStatusUnchanged {
		t.Fatalf("应标记 unchanged, 得到 %q", got)
	}
	if !engine.Match("ads.example.com", 1).Blocked {
		t.Fatalf("304 后规则应继续生效")
	}
}
