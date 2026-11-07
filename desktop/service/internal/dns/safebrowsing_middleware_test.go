package dns

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// sbStubResolver 按脚本应答哈希前缀查询
type sbStubResolver struct {
	answers []string
	err     error
	queries []string
}

func (m *sbStubResolver) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	return nil, nil
}

func (m *sbStubResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	if len(req.Question) > 0 {
		m.queries = append(m.queries, req.Question[0].Name)
	}
	if m.err != nil {
		return nil, m.err
	}
	resp := new(dns.Msg)
	resp.SetReply(req)
	name := ""
	if len(req.Question) > 0 {
		name = req.Question[0].Name
	}
	for _, a := range m.answers {
		resp.Answer = append(resp.Answer, &dns.TXT{
			Hdr: dns.RR_Header{Name: name, Rrtype: dns.TypeTXT, Class: dns.ClassINET, Ttl: 60},
			Txt: []string{a},
		})
	}
	return resp, nil
}

func (m *sbStubResolver) Configure(cfg core.ResolverConfig) error { return nil }
func (m *sbStubResolver) Shutdown() error                         { return nil }

func sbHash(host string) string {
	sum := sha256.Sum256([]byte(host))
	return hex.EncodeToString(sum[:])
}

func newSBEngine(enabled bool, resolver core.Resolver) *core.SafeBrowsingEngine {
	cfg := core.DefaultSafeBrowsingConfig()
	cfg.Enabled = enabled
	cfg.TimeoutMs = 2000
	engine, err := core.NewSafeBrowsingEngine(cfg, resolver)
	if err != nil {
		panic(fmt.Sprintf("声誉查询内核不可用: %v", err))
	}
	return engine
}

func sbContext(t *testing.T, name string, qtype uint16) *DNSContext {
	t.Helper()
	req := new(dns.Msg)
	req.SetQuestion(name, qtype)
	return NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")
}

func TestSafeBrowsingMiddleware_Blocks(t *testing.T) {
	resolver := &sbStubResolver{answers: []string{sbHash("tracker.example")}}
	engine := newSBEngine(true, resolver)
	mw := NewSafeBrowsingMiddleware(engine, nil)

	ctx := sbContext(t, "tracker.example.", dns.TypeA)
	nextCalled := false
	if err := mw(ctx, func() error { nextCalled = true; return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if nextCalled {
		t.Fatal("命中后不应继续向管线深处传递")
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 1 {
		t.Fatalf("应构造出一条拦截应答，实得 %+v", ctx.Resp)
	}
	if a, ok := ctx.Resp.Answer[0].(*dns.A); !ok || a.A.String() != "0.0.0.0" {
		t.Fatalf("默认拦截方式应返回 0.0.0.0，实得 %v", ctx.Resp.Answer[0])
	}

	if v, _ := ctx.Get("filter_blocked"); v != true {
		t.Fatal("应标记 filter_blocked")
	}
	if v, _ := ctx.Get("source"); v != "safebrowsing" {
		t.Fatalf("应答来源应标为 safebrowsing，实得 %v", v)
	}
	// 归因写进 filter_reason，EDE 与查询日志据此展示
	if v, _ := ctx.Get("filter_reason"); v != core.ReasonSafeBrowsing {
		t.Fatalf("应归因于恶意网址库，实得 %v", v)
	}
}

func TestSafeBrowsingMiddleware_UnblockedPassesThrough(t *testing.T) {
	resolver := &sbStubResolver{answers: []string{sbHash("someone.else")}}
	engine := newSBEngine(true, resolver)
	mw := NewSafeBrowsingMiddleware(engine, nil)

	ctx := sbContext(t, "safe.example.", dns.TypeA)
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if ctx.Resp != nil {
		t.Fatal("未命中不应构造应答")
	}
	if _, ok := ctx.Get("filter_blocked"); ok {
		t.Fatal("未命中不应标记拦截")
	}
}

// 上游故障时必须放行：第三方抖动不该让整个网络解析失败
func TestSafeBrowsingMiddleware_FailOpen(t *testing.T) {
	resolver := &sbStubResolver{err: errors.New("hash server unreachable")}
	engine := newSBEngine(true, resolver)
	mw := NewSafeBrowsingMiddleware(engine, nil)

	ctx := sbContext(t, "example.com.", dns.TypeA)
	nextCalled := false
	if err := mw(ctx, func() error { nextCalled = true; return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if !nextCalled {
		t.Fatal("查询失败必须放行")
	}
	if ctx.Resp != nil {
		t.Fatal("查询失败不得伪造应答")
	}
	if v, _ := ctx.Get("safebrowsing_failed"); v != true {
		t.Fatal("应留下失败标记供日志观察")
	}
}

func TestSafeBrowsingMiddleware_DisabledIsNoop(t *testing.T) {
	resolver := &sbStubResolver{answers: []string{sbHash("tracker.example")}}
	engine := newSBEngine(false, resolver)
	mw := NewSafeBrowsingMiddleware(engine, nil)

	ctx := sbContext(t, "tracker.example.", dns.TypeA)
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if len(resolver.queries) != 0 {
		t.Fatal("关闭时不应发起任何外部查询")
	}
}

func TestSafeBrowsingMiddleware_NilEngineIsNoop(t *testing.T) {
	mw := NewSafeBrowsingMiddleware(nil, nil)

	ctx := sbContext(t, "tracker.example.", dns.TypeA)
	nextCalled := false
	if err := mw(ctx, func() error { nextCalled = true; return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if !nextCalled {
		t.Fatal("引擎缺席时应直接放行")
	}
}

// 不产生连接的类型不查声誉：拦下 MX/TXT 只会让邮件与验证流程莫名失败
func TestSafeBrowsingMiddleware_SkipsNonConnectableTypes(t *testing.T) {
	for _, qtype := range []uint16{dns.TypeMX, dns.TypeTXT, dns.TypeNS, dns.TypeSOA, dns.TypeCAA} {
		resolver := &sbStubResolver{answers: []string{sbHash("tracker.example")}}
		engine := newSBEngine(true, resolver)
		mw := NewSafeBrowsingMiddleware(engine, nil)

		ctx := sbContext(t, "tracker.example.", qtype)
		if err := mw(ctx, func() error { return nil }); err != nil {
			t.Fatalf("类型 %d 返回错误: %v", qtype, err)
		}
		if len(resolver.queries) != 0 {
			t.Fatalf("类型 %d 不应触发声誉查询", qtype)
		}
		if ctx.Resp != nil {
			t.Fatalf("类型 %d 不应被拦截", qtype)
		}
	}
}

func TestSafeBrowsingMiddleware_ChecksConnectableTypes(t *testing.T) {
	for _, qtype := range []uint16{dns.TypeA, dns.TypeAAAA, dns.TypeHTTPS, dns.TypeSVCB} {
		resolver := &sbStubResolver{answers: []string{sbHash("tracker.example")}}
		engine := newSBEngine(true, resolver)
		mw := NewSafeBrowsingMiddleware(engine, nil)

		ctx := sbContext(t, "tracker.example.", qtype)
		nextCalled := false
		if err := mw(ctx, func() error { nextCalled = true; return nil }); err != nil {
			t.Fatalf("类型 %d 返回错误: %v", qtype, err)
		}
		if nextCalled {
			t.Fatalf("类型 %d 命中后应短路", qtype)
		}
		if ctx.Resp == nil {
			t.Fatalf("类型 %d 应被拦截", qtype)
		}
	}
}

// 拦截应答要沿用用户在「拦截方式」里的选择，否则同一域名会因来源不同给出不同结果
func TestSafeBrowsingMiddleware_HonorsBlockMode(t *testing.T) {
	cases := []struct {
		mode  string
		rcode int
	}{
		{core.BlockModeNXDOMAIN, dns.RcodeNameError},
		{core.BlockModeRefused, dns.RcodeRefused},
	}
	for _, tc := range cases {
		resolver := &sbStubResolver{answers: []string{sbHash("tracker.example")}}
		engine := newSBEngine(true, resolver)
		mw := NewSafeBrowsingMiddleware(engine, func() core.FilterConfig {
			return core.FilterConfig{BlockMode: tc.mode}
		})

		ctx := sbContext(t, "tracker.example.", dns.TypeA)
		if err := mw(ctx, func() error { return nil }); err != nil {
			t.Fatalf("模式 %s 返回错误: %v", tc.mode, err)
		}
		if ctx.Resp == nil || ctx.Resp.Rcode != tc.rcode {
			t.Fatalf("模式 %s 期望 rcode %d，实得 %+v", tc.mode, tc.rcode, ctx.Resp)
		}
	}
}

func TestSafeBrowsingMiddleware_ParentalControlAttribution(t *testing.T) {
	resolver := &sbStubResolver{answers: []string{sbHash("adult.example")}}
	cfg := core.DefaultSafeBrowsingConfig()
	cfg.ParentalEnabled = true
	engine, err := core.NewSafeBrowsingEngine(cfg, resolver)
	if err != nil {
		t.Fatalf("声誉查询内核不可用: %v", err)
	}
	mw := NewSafeBrowsingMiddleware(engine, nil)

	ctx := sbContext(t, "adult.example.", dns.TypeA)
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if v, _ := ctx.Get("filter_reason"); v != core.ReasonParentalControl {
		t.Fatalf("应归因于家长控制，实得 %v", v)
	}
}

// 声誉查询必须排在本地规则之后、缓存之前。
//
// 在本地规则之后：本地规则不花钱，先让它筛掉绝大多数请求，
// 只有到这里仍未被拦的域名才值得花一次外部查询。
// 在缓存之前：缓存的键里没有「谁拦的」这一维度，声誉拦截的应答
// 一旦进了缓存，后续命中会直接绕过声誉查询，判断依据随之失真。
func TestSafeBrowsingMiddleware_PipelineOrder(t *testing.T) {
	tmpDir := t.TempDir()
	filterCfg := core.DefaultFilterConfig()
	filterCfg.DataDir = tmpDir
	filterCfg.Lists = []core.FilterList{}
	filterCfg.CustomRules = []string{"||local-blocked.example^"}
	filterEngine := core.NewRuleEngine(filterCfg)
	defer filterEngine.Close()

	resolver := &sbStubResolver{answers: []string{sbHash("reputation-blocked.example")}}
	sbEngine := newSBEngine(true, resolver)

	forwardCalls := 0
	forward := func(ctx *DNSContext, next func() error) error {
		forwardCalls++
		resp := new(dns.Msg)
		resp.SetReply(ctx.Req)
		ctx.Resp = resp
		return nil
	}

	pipeline := NewPipeline(
		NewFilterMiddleware(filterEngine),
		NewSafeBrowsingMiddleware(sbEngine, filterEngine.GetConfig),
		forward,
	)

	// 本地规则拦下的域名不该再花一次外部查询
	ctx1 := sbContext(t, "local-blocked.example.", dns.TypeA)
	if err := pipeline.Execute(ctx1); err != nil {
		t.Fatalf("执行失败: %v", err)
	}
	if v, _ := ctx1.Get("filter_list"); v == core.ReasonSafeBrowsing {
		t.Fatalf("本地规则命中的域名不应转为声誉拦截，实得 %v", v)
	}
	if len(resolver.queries) != 0 {
		t.Fatalf("本地规则已拦下，不应再发外部查询，实得 %v", resolver.queries)
	}

	// 本地规则放行、声誉库命中的域名由声誉中间件拦下
	ctx2 := sbContext(t, "reputation-blocked.example.", dns.TypeA)
	if err := pipeline.Execute(ctx2); err != nil {
		t.Fatalf("执行失败: %v", err)
	}
	if v, _ := ctx2.Get("filter_reason"); v != core.ReasonSafeBrowsing {
		t.Fatalf("应归因于声誉库，实得 %v", v)
	}
	if forwardCalls != 0 {
		t.Fatal("声誉命中应短路，不应落到转发")
	}
}

func TestSafeBrowsingMiddleware_EmptyQuestionIsNoop(t *testing.T) {
	resolver := &sbStubResolver{answers: []string{sbHash("tracker.example")}}
	engine := newSBEngine(true, resolver)
	mw := NewSafeBrowsingMiddleware(engine, nil)

	ctx := NewDNSContext(context.Background(), new(dns.Msg), &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 1}, "udp")
	nextCalled := false
	if err := mw(ctx, func() error { nextCalled = true; return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if !nextCalled {
		t.Fatal("空问题不应中断管线")
	}
}
