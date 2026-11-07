package core

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/miekg/dns"
)

// sbMockResolver 记录收到的哈希前缀查询并按脚本作答
type sbMockResolver struct {
	mu       sync.Mutex
	requests []string
	answers  []string // 每次应答返回的十六进制摘要
	err      error
	delay    time.Duration
}

func (m *sbMockResolver) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	return nil, nil
}

func (m *sbMockResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	m.mu.Lock()
	if len(req.Question) > 0 {
		m.requests = append(m.requests, req.Question[0].Name)
	}
	err := m.err
	delay := m.delay
	answers := append([]string(nil), m.answers...)
	m.mu.Unlock()

	if delay > 0 {
		select {
		case <-time.After(delay):
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	if err != nil {
		return nil, err
	}

	resp := new(dns.Msg)
	resp.SetReply(req)
	qname := ""
	if len(req.Question) > 0 {
		qname = req.Question[0].Name
	}
	for _, a := range answers {
		resp.Answer = append(resp.Answer, &dns.TXT{
			Hdr: dns.RR_Header{Name: qname, Rrtype: dns.TypeTXT, Class: dns.ClassINET, Ttl: 60},
			Txt: []string{a},
		})
	}
	return resp, nil
}

func (m *sbMockResolver) Configure(cfg ResolverConfig) error { return nil }
func (m *sbMockResolver) Shutdown() error                    { return nil }

func (m *sbMockResolver) queryCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.requests)
}

func (m *sbMockResolver) lastQuery() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.requests) == 0 {
		return ""
	}
	return m.requests[len(m.requests)-1]
}

func (m *sbMockResolver) sawSuffix(suffix string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, q := range m.requests {
		if strings.HasSuffix(q, suffix) {
			return true
		}
	}
	return false
}

func hexHash(host string) string {
	sum := sha256.Sum256([]byte(host))
	return hex.EncodeToString(sum[:])
}

func newSBEngine(t *testing.T, cfg SafeBrowsingConfig, resolver Resolver) *SafeBrowsingEngine {
	t.Helper()
	engine, err := NewSafeBrowsingEngine(cfg, resolver)
	if err != nil {
		t.Fatalf("声誉查询内核不可用: %v", err)
	}
	return engine
}

func enabledSB(t *testing.T, resolver Resolver) *SafeBrowsingEngine {
	cfg := DefaultSafeBrowsingConfig()
	cfg.Enabled = true
	cfg.TimeoutMs = 2000
	return newSBEngine(t, cfg, resolver)
}

// sbPlanFor 让内核规划一次恶意网址库查询，返回归一化后的计划。
//
// 归一化、摘要与查询名都在 Rust 内核里，所以白盒断言改为读内核的产出。
func sbPlanFor(t *testing.T, engine *SafeBrowsingEngine, host string) sbPlan {
	t.Helper()
	plan, ok := engine.kernel.plan(sbServiceIDMalware, host)
	if !ok {
		t.Fatalf("主机名 %q 应产生计划", host)
	}
	return plan
}

// sbHashLabels 数出查询名里携带的前缀标签数，即待核对的摘要数
func sbHashLabels(t *testing.T, engine *SafeBrowsingEngine, host string) int {
	t.Helper()
	plan := sbPlanFor(t, engine, host)
	trimmed := strings.TrimSuffix(plan.question, SafeBrowsingSuffix)
	count := 0
	for _, label := range strings.Split(trimmed, ".") {
		if label != "" {
			count++
		}
	}
	return count
}

func TestSafeBrowsing_HostnameToHashes(t *testing.T) {
	cases := []struct {
		host string
		want int
	}{
		{"example.com", 1},
		{"www.example.com", 2},
		{"1.2.3.sub.host.com", 3},
		{"foo.co.uk", 1},
		{"bar.foo.co.uk", 2},
		// 非 ICANN 私有后缀无法界定注册域，逐级上溯至更多层
		{"foo.dyndns.org", 3},
		{"bar.foo.dyndns.org", 4},
	}

	for _, tc := range cases {
		t.Run(tc.host, func(t *testing.T) {
			engine := enabledSB(t, &sbMockResolver{})
			if got := sbHashLabels(t, engine, tc.host); got != tc.want {
				t.Fatalf("%s 期望 %d 个摘要，实得 %d", tc.host, tc.want, got)
			}
		})
	}
}

// eTLD+1 必须参与比对，但公共后缀本身不应参与
func TestSafeBrowsing_ETLDPlusOneIncluded(t *testing.T) {
	engine := enabledSB(t, &sbMockResolver{})
	hashes := sbPlanFor(t, engine, "1.2.3.sub.host.com").hashes
	find := func(host string) bool {
		want := sha256.Sum256([]byte(host))
		for _, h := range hashes {
			if h == want {
				return true
			}
		}
		return false
	}

	for _, host := range []string{"3.sub.host.com", "sub.host.com", "host.com"} {
		if !find(host) {
			t.Fatalf("%s 应参与比对", host)
		}
	}
	if find("com") {
		t.Fatal("公共后缀不应参与比对")
	}
}

// 子域层数超限时只保留末尾 4 层，避免查询名超出 DNS 长度限制
func TestSafeBrowsing_DeepSubdomainTruncated(t *testing.T) {
	engine := enabledSB(t, &sbMockResolver{})
	hashes := sbPlanFor(t, engine, "a.b.c.d.e.f.example.com").hashes
	if len(hashes) > 4 {
		t.Fatalf("摘要数应受子域层数上限约束，实得 %d", len(hashes))
	}

	// 截断后最长的那个应当是末尾 4 个标签
	want := sha256.Sum256([]byte("e.f.example.com"))
	found := false
	for _, h := range hashes {
		if h == want {
			found = true
		}
	}
	if !found {
		t.Fatal("截断后应保留末尾 4 个标签")
	}
}

func TestSafeBrowsing_QuestionFormat(t *testing.T) {
	engine := enabledSB(t, &sbMockResolver{})
	plan := sbPlanFor(t, engine, "sub.host.com")
	q := buildHashQuestion(plan.question)

	if len(q.Question) != 1 {
		t.Fatalf("应只有一个问题，实得 %d", len(q.Question))
	}
	if q.Question[0].Qtype != dns.TypeTXT {
		t.Fatalf("查询类型应为 TXT，实得 %d", q.Question[0].Qtype)
	}
	if !q.RecursionDesired {
		t.Fatal("哈希前缀查询应带递归位")
	}
	name := q.Question[0].Name
	if !strings.HasSuffix(name, SafeBrowsingSuffix) {
		t.Fatalf("查询名应以 %s 结尾，实得 %q", SafeBrowsingSuffix, name)
	}

	// 每个前缀都以 4 个十六进制字符的标签出现
	labels := strings.Split(strings.TrimSuffix(name, SafeBrowsingSuffix), ".")
	labels = labels[:len(labels)-1]
	if len(labels) != len(plan.hashes) {
		t.Fatalf("应给出 %d 个前缀标签，实得 %d", len(plan.hashes), len(labels))
	}
	for _, l := range labels {
		if len(l) != 4 {
			t.Fatalf("前缀标签长度应为 4，实得 %q", l)
		}
	}
}

func TestSafeBrowsing_BlockOnMatch(t *testing.T) {
	// 服务端返回 "host.com" 的完整摘要，而查询的是 sub.host.com
	resolver := &sbMockResolver{answers: []string{hexHash("host.com")}}
	engine := enabledSB(t, resolver)

	v := engine.Check(context.Background(), "sub.host.com")
	if v.Failed {
		t.Fatalf("不应失败: %v", v.Err)
	}
	if !v.Blocked {
		t.Fatal("父域被收录时应拦截")
	}
	if v.Service != ReasonSafeBrowsing {
		t.Fatalf("应归因于恶意网址库，实得 %q", v.Service)
	}
}

func TestSafeBrowsing_NoMatchPasses(t *testing.T) {
	resolver := &sbMockResolver{answers: []string{hexHash("unrelated.example")}}
	engine := enabledSB(t, resolver)

	v := engine.Check(context.Background(), "sub.host.com")
	if v.Blocked || v.Failed {
		t.Fatalf("未命中应放行，实得 %+v", v)
	}
}

// 查询失败必须放行而不是拦截：第三方抖动不该整网断解析
func TestSafeBrowsing_FailOpen(t *testing.T) {
	resolver := &sbMockResolver{err: errors.New("upstream down")}
	engine := enabledSB(t, resolver)

	v := engine.Check(context.Background(), "host.com")
	if v.Blocked {
		t.Fatal("查询失败时绝不能拦截")
	}
	if !v.Failed {
		t.Fatal("应如实标记为失败，供日志观察")
	}
	if v.Err == nil {
		t.Fatal("失败应带回原因")
	}
	if stats := engine.Stats(); stats.Failures != 1 {
		t.Fatalf("失败计数应为 1，实得 %d", stats.Failures)
	}
}

func TestSafeBrowsing_TimeoutIsFailure(t *testing.T) {
	resolver := &sbMockResolver{delay: 500 * time.Millisecond}
	cfg := DefaultSafeBrowsingConfig()
	cfg.Enabled = true
	cfg.TimeoutMs = 100
	engine := newSBEngine(t, cfg, resolver)

	start := time.Now()
	v := engine.Check(context.Background(), "host.com")
	if elapsed := time.Since(start); elapsed > 400*time.Millisecond {
		t.Fatalf("超时未生效，耗时 %v", elapsed)
	}
	if v.Blocked || !v.Failed {
		t.Fatalf("超时应按失败处理并放行，实得 %+v", v)
	}
}

func TestSafeBrowsing_NilResolverIsFailure(t *testing.T) {
	engine := enabledSB(t, nil)

	v := engine.Check(context.Background(), "host.com")
	if v.Blocked || !v.Failed {
		t.Fatalf("解析器未就绪时应失败并放行，实得 %+v", v)
	}
}

func TestSafeBrowsing_DisabledSkipsWork(t *testing.T) {
	resolver := &sbMockResolver{answers: []string{hexHash("host.com")}}
	engine := newSBEngine(t, DefaultSafeBrowsingConfig(), resolver)

	if engine.IsEnabled() {
		t.Fatal("默认配置应为关闭")
	}
	if v := engine.Check(context.Background(), "host.com"); v.Blocked || v.Failed {
		t.Fatalf("关闭时不应产生任何结论，实得 %+v", v)
	}
	if resolver.queryCount() != 0 {
		t.Fatal("关闭时不应发出任何查询")
	}
}

// 缓存的作用是让同一前缀不重复外发查询
func TestSafeBrowsing_CacheAvoidsRepeatQueries(t *testing.T) {
	resolver := &sbMockResolver{answers: []string{hexHash("host.com")}}
	engine := enabledSB(t, resolver)

	if v := engine.Check(context.Background(), "host.com"); !v.Blocked {
		t.Fatal("首次应拦截")
	}
	first := resolver.queryCount()
	if first == 0 {
		t.Fatal("首次应发出查询")
	}

	if v := engine.Check(context.Background(), "host.com"); !v.Blocked {
		t.Fatal("第二次仍应拦截")
	}
	if resolver.queryCount() != first {
		t.Fatalf("重复查询不应再次外发，实得 %d 次（原 %d）", resolver.queryCount(), first)
	}

	stats := engine.Stats()
	if stats.CacheHits != 1 {
		t.Fatalf("缓存命中计数应为 1，实得 %d", stats.CacheHits)
	}
}

// 服务端明确回了「没收录」也是结论，同样应缓存，否则会反复问同一个问题
func TestSafeBrowsing_NegativeResultIsCached(t *testing.T) {
	resolver := &sbMockResolver{answers: nil}
	engine := enabledSB(t, resolver)

	engine.Check(context.Background(), "host.com")
	first := resolver.queryCount()

	engine.Check(context.Background(), "host.com")
	if resolver.queryCount() != first {
		t.Fatalf("空结果也应缓存，实得 %d 次查询（原 %d）", resolver.queryCount(), first)
	}
}

func TestSafeBrowsing_CacheExpiry(t *testing.T) {
	resolver := &sbMockResolver{answers: []string{hexHash("host.com")}}
	cfg := DefaultSafeBrowsingConfig()
	cfg.Enabled = true
	cfg.CacheTTLSeconds = 1
	engine := newSBEngine(t, cfg, resolver)

	engine.Check(context.Background(), "host.com")
	first := resolver.queryCount()

	// 有效期只有 1 秒（配置的最小粒度），过期判定由内核用注入的 now_ms 完成，
	// 这里只能真的等过去——等的是「Go 把新时刻交给内核」这条路。
	time.Sleep(1100 * time.Millisecond)

	if v := engine.Check(context.Background(), "host.com"); !v.Blocked {
		t.Fatal("过期后重新查询仍应得到拦截结论")
	}
	if resolver.queryCount() <= first {
		t.Fatal("过期后应重新外发查询")
	}
}

func TestSafeBrowsing_CacheRespectsSizeLimit(t *testing.T) {
	resolver := &sbMockResolver{}
	cfg := DefaultSafeBrowsingConfig()
	cfg.Enabled = true
	cfg.CacheSize = 4
	engine := newSBEngine(t, cfg, resolver)

	for _, host := range []string{"a.com", "b.com", "c.com", "d.com", "e.com", "f.com"} {
		engine.Check(context.Background(), host)
	}
	if got := resolver.queryCount(); got != 6 {
		t.Fatalf("每个新前缀都该查一次，实得 %d 次", got)
	}

	// 容量为 4，最早的两个应已被淘汰：再查 a.com 会重新外发
	engine.Check(context.Background(), "a.com")
	if got := resolver.queryCount(); got != 7 {
		t.Fatalf("被淘汰的前缀应重新查询，实得 %d 次", got)
	}

	// 最近用过的 f.com 仍在缓存里，不应再查
	before := resolver.queryCount()
	engine.Check(context.Background(), "f.com")
	if resolver.queryCount() != before {
		t.Fatalf("仍在缓存的前缀不应重新查询，实得 %d 次（原 %d）", resolver.queryCount(), before)
	}
}

func TestSafeBrowsing_ParentalControl(t *testing.T) {
	resolver := &sbMockResolver{answers: []string{hexHash("adult.example")}}
	cfg := DefaultSafeBrowsingConfig()
	cfg.ParentalEnabled = true
	engine := newSBEngine(t, cfg, resolver)

	v := engine.Check(context.Background(), "adult.example")
	if !v.Blocked {
		t.Fatal("家长控制命中应拦截")
	}
	if v.Service != ReasonParentalControl {
		t.Fatalf("应归因于家长控制，实得 %q", v.Service)
	}
	if !strings.HasSuffix(resolver.lastQuery(), ParentalControlSuffix) {
		t.Fatalf("应向家长控制后缀发查询，实得 %q", resolver.lastQuery())
	}
}

// 两个服务同时启用时，恶意网址库优先归因
func TestSafeBrowsing_MalwareTakesPrecedence(t *testing.T) {
	resolver := &sbMockResolver{answers: []string{hexHash("host.com")}}
	cfg := DefaultSafeBrowsingConfig()
	cfg.Enabled = true
	cfg.ParentalEnabled = true
	engine := newSBEngine(t, cfg, resolver)

	v := engine.Check(context.Background(), "host.com")
	if !v.Blocked || v.Service != ReasonSafeBrowsing {
		t.Fatalf("应优先归因于恶意网址库，实得 %+v", v)
	}
}

// 恶意网址库未命中时不能短路掉家长控制
func TestSafeBrowsing_FallsThroughToParental(t *testing.T) {
	resolver := &sbMockResolver{answers: nil}
	cfg := DefaultSafeBrowsingConfig()
	cfg.Enabled = true
	cfg.ParentalEnabled = true
	engine := newSBEngine(t, cfg, resolver)

	engine.Check(context.Background(), "host.com")
	if n := resolver.queryCount(); n < 2 {
		t.Fatalf("两个服务都应被查询，实得 %d 次", n)
	}
	if !resolver.sawSuffix(ParentalControlSuffix) {
		t.Fatal("家长控制未被查询")
	}
}

// 格式不符的 TXT 必须忽略，否则会拼出一个匹配不上的摘要参与比对
func TestSafeBrowsing_MalformedTXTIgnored(t *testing.T) {
	resolver := &sbMockResolver{answers: []string{"deadbeef", strings.Repeat("z", 64)}}
	engine := enabledSB(t, resolver)

	v := engine.Check(context.Background(), "host.com")
	if v.Blocked {
		t.Fatal("非法 TXT 不应造成拦截")
	}
	if v.Failed {
		t.Fatal("非法 TXT 不算查询失败")
	}
}

func TestSafeBrowsing_InvalidHostSkipped(t *testing.T) {
	resolver := &sbMockResolver{}
	engine := enabledSB(t, resolver)

	for _, host := range []string{"", "  ", "."} {
		if v := engine.Check(context.Background(), host); v.Blocked || v.Failed {
			t.Fatalf("空主机名 %q 不应产生结论", host)
		}
	}
	if resolver.queryCount() != 0 {
		t.Fatal("空主机名不应发起查询")
	}
}

func TestSafeBrowsing_ConfigureResetsCacheOnTTLChange(t *testing.T) {
	resolver := &sbMockResolver{answers: []string{hexHash("host.com")}}
	engine := enabledSB(t, resolver)

	engine.Check(context.Background(), "host.com")
	first := resolver.queryCount()

	cfg := DefaultSafeBrowsingConfig()
	cfg.Enabled = true
	cfg.CacheTTLSeconds = 120
	engine.Configure(cfg)

	// 有效期变化后缓存由内核整体重建，同一前缀必须重新外发
	engine.Check(context.Background(), "host.com")
	if resolver.queryCount() <= first {
		t.Fatalf("缓存重建后应重新查询，实得 %d 次（原 %d）", resolver.queryCount(), first)
	}
}

func TestSafeBrowsing_NormalizeConfig(t *testing.T) {
	cfg := SafeBrowsingConfig{TimeoutMs: 1, CacheSize: -5, CacheTTLSeconds: 0}
	NormalizeSafeBrowsingConfig(&cfg)

	if cfg.TimeoutMs != DefaultSafeBrowsingTimeoutMs {
		t.Fatalf("超范围超时应回落默认值，实得 %d", cfg.TimeoutMs)
	}
	if cfg.CacheSize != 0 {
		t.Fatalf("负容量应归零，实得 %d", cfg.CacheSize)
	}
	if cfg.CacheTTLSeconds != DefaultSafeBrowsingCacheTTL {
		t.Fatalf("零有效期应补默认值，实得 %d", cfg.CacheTTLSeconds)
	}

	huge := SafeBrowsingConfig{TimeoutMs: 999999}
	NormalizeSafeBrowsingConfig(&huge)
	if huge.TimeoutMs != DefaultSafeBrowsingTimeoutMs {
		t.Fatalf("过大的超时应回落默认值，实得 %d", huge.TimeoutMs)
	}
}

func TestSafeBrowsing_DefaultDisabled(t *testing.T) {
	cfg := DefaultSafeBrowsingConfig()
	if cfg.Enabled || cfg.ParentalEnabled {
		t.Fatal("声誉查询默认必须关闭")
	}
}

func TestSafeBrowsing_SetResolver(t *testing.T) {
	engine := enabledSB(t, nil)
	if v := engine.Check(context.Background(), "host.com"); !v.Failed {
		t.Fatal("无解析器应失败")
	}

	resolver := &sbMockResolver{answers: []string{hexHash("host.com")}}
	engine.SetResolver(resolver)
	if v := engine.Check(context.Background(), "host.com"); !v.Blocked {
		t.Fatalf("装配解析器后应正常判定，实得 %+v", v)
	}
}
