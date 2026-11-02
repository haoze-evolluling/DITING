package dns

import (
	"context"
	"net"
	"os"
	"path/filepath"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// responseFilterEngine 构建含黑名单域 ad.tracker.com 的过滤引擎（响应侧复检默认关闭）。
func responseFilterEngine(t *testing.T, enabled bool) *core.RuleEngine {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "list-ads.txt"), []byte("||ad.tracker.com^\n"), 0o600); err != nil {
		t.Fatalf("写入列表缓存失败: %v", err)
	}

	cfg := core.DefaultFilterConfig()
	cfg.DataDir = dir
	cfg.CustomRules = []string{}
	cfg.Lists = []core.FilterList{{ID: "list-ads", Name: "广告", Enabled: true}}
	cfg.FilterResponse = enabled

	engine := core.NewRuleEngine(cfg)
	t.Cleanup(engine.Close)
	return engine
}

// cnameResp 构造「QNAME 合法但 CNAME 别名指向黑名单域」的上游应答。
func cnameResp(qname, alias string) *dns.Msg {
	req := new(dns.Msg)
	req.SetQuestion(dns.Fqdn(qname), dns.TypeA)
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Answer = append(resp.Answer,
		&dns.CNAME{
			Hdr:    dns.RR_Header{Name: dns.Fqdn(qname), Rrtype: dns.TypeCNAME, Class: dns.ClassINET, Ttl: 60},
			Target: dns.Fqdn(alias),
		},
		&dns.A{
			Hdr: dns.RR_Header{Name: dns.Fqdn(alias), Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60},
			A:   net.ParseIP("203.0.113.7"),
		},
	)
	return resp
}

// responseFilterCtx 构造带着已装配应答的 DNS 上下文。
func responseFilterCtx(qname, alias, ip string) *DNSContext {
	req := new(dns.Msg)
	req.SetQuestion(dns.Fqdn(qname), dns.TypeA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP(ip), Port: 54321}, "udp")
	ctx.Resp = cnameResp(qname, alias)
	return ctx
}

// TestFilterResponseBlocksCnameAlias 校验别名指向黑名单域时应答被替换为阻断响应。
func TestFilterResponseBlocksCnameAlias(t *testing.T) {
	engine := responseFilterEngine(t, true)
	mw := NewFilterResponseMiddleware(engine, nil, func() bool { return true })

	ctx := responseFilterCtx("cdn.example.com", "ad.tracker.com", "192.168.1.9")
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}

	if blocked, _ := ctx.Get("filter_blocked"); blocked != true {
		t.Fatalf("别名命中黑名单应标记 filter_blocked")
	}
	if filtered, _ := ctx.Get("response_filtered"); filtered != true {
		t.Fatalf("应标记 response_filtered")
	}
	if rule, _ := ctx.Get("filter_rule"); rule != "||ad.tracker.com^" {
		t.Fatalf("filter_rule 应为命中的黑名单规则, 得到 %v", rule)
	}
	if reason, _ := ctx.Get("filter_reason"); reason != core.ReasonResponseBlocked {
		t.Fatalf("filter_reason 应为 %s, 得到 %v", core.ReasonResponseBlocked, reason)
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 1 {
		t.Fatalf("应答应被替换为阻断响应, 得到 %v", ctx.Resp)
	}
	if a, ok := ctx.Resp.Answer[0].(*dns.A); !ok || !a.A.IsUnspecified() {
		t.Fatalf("阻断响应应为 0.0.0.0 空地址, 得到 %v", ctx.Resp.Answer[0])
	}
}

// TestFilterResponseDisabledPassthrough 校验开关关闭时响应原样透传（默认行为不变）。
func TestFilterResponseDisabledPassthrough(t *testing.T) {
	engine := responseFilterEngine(t, true)
	mw := NewFilterResponseMiddleware(engine, nil, func() bool { return false })

	ctx := responseFilterCtx("cdn.example.com", "ad.tracker.com", "192.168.1.9")
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if _, ok := ctx.Get("filter_blocked"); ok {
		t.Fatalf("开关关闭时不应标记回阻断")
	}
	if len(ctx.Resp.Answer) != 2 {
		t.Fatalf("应答应原样保留, 得到 %d 条记录", len(ctx.Resp.Answer))
	}
}

// TestFilterResponseSkipsLocalAuthority 校验 hosts/rewrite 本地权威应答不被复检误杀。
func TestFilterResponseSkipsLocalAuthority(t *testing.T) {
	engine := responseFilterEngine(t, true)
	mw := NewFilterResponseMiddleware(engine, nil, func() bool { return true })

	ctx := responseFilterCtx("cdn.example.com", "ad.tracker.com", "192.168.1.9")
	ctx.Set("source", "hosts")

	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if _, ok := ctx.Get("filter_blocked"); ok {
		t.Fatalf("本地权威应答不应被响应侧复检拦截")
	}
}

// TestFilterResponseSkipsEmptyAndNonSuccess 校验空应答与非 NOERROR 应答直接跳过。
func TestFilterResponseSkipsEmptyAndNonSuccess(t *testing.T) {
	engine := responseFilterEngine(t, true)
	mw := NewFilterResponseMiddleware(engine, nil, func() bool { return true })

	// 非 NOERROR
	ctx := responseFilterCtx("cdn.example.com", "ad.tracker.com", "192.168.1.9")
	ctx.Resp.Rcode = dns.RcodeNameError
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if _, ok := ctx.Get("filter_blocked"); ok {
		t.Fatalf("NXDOMAIN 应答不应触发复检")
	}

	// 无应答记录
	ctx = responseFilterCtx("cdn.example.com", "ad.tracker.com", "192.168.1.9")
	ctx.Resp.Answer = nil
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if res := engine.MatchResponse(ctx.Resp, "cdn.example.com", dns.TypeA, core.DefaultClientGroupID); res.Blocked {
		t.Fatalf("空应答不应命中")
	}
}

// cnameResolver 固定返回「CNAME 别名 → 黑名单域」应答的上游桩。
//
// 不同于 pipelineMockResolver（按 qtype 过滤记录），此处完整保留 CNAME 链，
// 以便验证缓存中存储的原始应答确实携带别名。
type cnameResolver struct{}

func (cnameResolver) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) { return nil, nil }

func (cnameResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	qname := "cdn.example.com"
	if len(req.Question) > 0 {
		qname = req.Question[0].Name
	}
	return cnameResp(qname, "ad.tracker.com"), nil
}

func (cnameResolver) Configure(cfg core.ResolverConfig) error { return nil }
func (cnameResolver) Shutdown() error                         { return nil }

// TestFilterResponseOnCacheHitPath 校验缓存命中路径同样被复检。
//
// 这是链序的回归测试：响应侧中间件必须外层包裹 cacheMw，
// 否则缓存命中（cacheMw 短路返回且不执行 next）时会漏检。
func TestFilterResponseOnCacheHitPath(t *testing.T) {
	engine := responseFilterEngine(t, true)
	cache := core.NewDNSCache(core.DefaultCacheConfig())
	t.Cleanup(cache.Close)

	resolver := cnameResolver{}
	cacheMw := NewCacheMiddleware(cache, resolver)
	forward := NewForwardMiddleware(resolver)

	// 与生产一致的相对顺序：响应复检（外）→ 缓存（内）→ 回源
	forwardOnly := NewPipeline(cacheMw, forward)

	run := func(p *Pipeline) *DNSContext {
		req := new(dns.Msg)
		req.SetQuestion("cdn.example.com.", dns.TypeA)
		ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("192.168.1.9"), Port: 54321}, "udp")
		if err := p.Execute(ctx); err != nil {
			t.Fatalf("流水线执行失败: %v", err)
		}
		return ctx
	}

	// 阶段一：无响应复检，先让投毒应答进入缓存
	_ = run(forwardOnly) // 首次回源并写入缓存
	second := run(forwardOnly)
	if hit, _ := second.Get("cache_hit"); hit != "fresh" {
		t.Fatalf("阶段一第二次查询应为缓存命中, 得到 %v", hit)
	}
	if got := len(second.Resp.Answer); got != 2 {
		t.Fatalf("阶段一缓存应答应原样返回, 得到 %d 条", got)
	}

	// 阶段二：启用响应复检后接入外层中间件，缓存命中必须仍被复检并阻断
	mw := NewFilterResponseMiddleware(engine, nil, func() bool { return true }, cache)
	withFilter := NewPipeline(mw, cacheMw, forward)
	ctx := run(withFilter)

	if hit, _ := ctx.Get("cache_hit"); hit == "" {
		t.Fatalf("阶段二应为缓存命中路径, 否则未覆盖目标场景")
	}
	if blocked, _ := ctx.Get("filter_blocked"); blocked != true {
		t.Fatalf("缓存命中应答也必须被响应侧复检阻断")
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 1 {
		t.Fatalf("缓存应答应被替换为阻断响应, 得到 %v", ctx.Resp)
	}
}

// TestExtractResponseCheckNames 校验候选域名抽取的去重、排除自身与别名链上限。
func TestExtractResponseCheckNames(t *testing.T) {
	resp := cnameResp("cdn.example.com", "ad.tracker.com")
	names := core.ExtractResponseCheckNames(resp, "cdn.example.com.")
	if len(names) != 1 || names[0] != "ad.tracker.com" {
		t.Fatalf("候选域名抽取错误: %v", names)
	}

	// 站点自身名不应进入候选
	if got := core.ExtractResponseCheckNames(resp, "ad.tracker.com"); len(got) != 0 {
		t.Fatalf("发起查询名不应成为复检候选: %v", got)
	}

	// 别名链上限
	long := new(dns.Msg)
	long.SetQuestion("a.example.com.", dns.TypeA)
	for i := 0; i < core.MaxResponseAliasDepth*3; i++ {
		long.Answer = append(long.Answer, &dns.CNAME{
			Hdr:    dns.RR_Header{Name: dns.Fqdn("a.example.com"), Rrtype: dns.TypeCNAME, Class: dns.ClassINET, Ttl: 60},
			Target: dns.Fqdn(string(rune('a'+i%26)) + ".alias.example.com"),
		})
	}
	if got := core.ExtractResponseCheckNames(long, "a.example.com."); len(got) > core.MaxResponseAliasDepth {
		t.Fatalf("候选域名数量应受上限约束, 得到 %d", len(got))
	}
}

// TestFilterResponseGroupScoped 校验组级黑名单差异在响应侧复检中生效。
func TestFilterResponseGroupScoped(t *testing.T) {
	engine := responseFilterEngine(t, true)
	if err := engine.SetClientGroups(core.ClientGroupConfig{
		Enabled: true,
		Groups: []core.ClientGroup{
			// 访客组不绑定广告列表 → 不继承黑名单
			{ID: "guest", Name: "访客", Enabled: true, RuleListIDs: []string{"list-none"}},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}
	resolver, err := core.NewGroupResolver(core.ClientGroupConfig{
		Enabled: true,
		Groups:  []core.ClientGroup{{ID: "guest", Enabled: true, Clients: []string{"192.168.2.0/24"}}},
	})
	if err != nil {
		t.Fatalf("NewGroupResolver 失败: %v", err)
	}

	mw := NewFilterResponseMiddleware(engine, func() *core.GroupResolver { return resolver }, func() bool { return true })

	// 默认组：命中黑名单 → 阻断
	ctx := responseFilterCtx("cdn.example.com", "ad.tracker.com", "10.0.0.9")
	_ = mw(ctx, func() error { return nil })
	if blocked, _ := ctx.Get("filter_blocked"); blocked != true {
		t.Fatalf("默认组应被响应侧复检阻断")
	}

	// guest 组：未绑定广告列表 → 放行
	ctx = responseFilterCtx("cdn.example.com", "ad.tracker.com", "192.168.2.9")
	_ = mw(ctx, func() error { return nil })
	if _, ok := ctx.Get("filter_blocked"); ok {
		t.Fatalf("未绑定广告列表的组不应被阻断")
	}
}
