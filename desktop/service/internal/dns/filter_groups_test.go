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

// groupFilterEngine 构建含单条订阅规则（||ad.tracker.com^）的过滤引擎。
func groupFilterEngine(t *testing.T) *core.RuleEngine {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "list-ads.txt"), []byte("||ad.tracker.com^\n"), 0o600); err != nil {
		t.Fatalf("写入列表缓存失败: %v", err)
	}

	cfg := core.DefaultFilterConfig()
	cfg.DataDir = dir
	cfg.CustomRules = []string{}
	cfg.Lists = []core.FilterList{{ID: "list-ads", Name: "广告", Enabled: true}}

	engine := core.NewRuleEngine(cfg)
	t.Cleanup(engine.Close)
	return engine
}

// groupCtx 构造某个客户端 IP 的 DNS 上下文。
func groupCtx(ip string) *DNSContext {
	req := new(dns.Msg)
	req.SetQuestion("ad.tracker.com.", dns.TypeA)
	return NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP(ip), Port: 54321}, "udp")
}

func TestFilterMiddlewareGroupScopedBlock(t *testing.T) {
	engine := groupFilterEngine(t)

	// kids 组不绑定广告列表（空 → 继承全部；此处改为显式空列表另建组验证隔离）
	if err := engine.SetClientGroups(core.ClientGroupConfig{
		Enabled: true,
		Groups: []core.ClientGroup{
			{ID: "kids", Name: "儿童", Enabled: true, RuleListIDs: []string{"list-ads"}},
			{ID: "guest", Name: "访客", Enabled: true, RuleListIDs: []string{"list-other"}},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}
	resolver, err := core.NewGroupResolver(core.ClientGroupConfig{
		Enabled: true,
		Groups: []core.ClientGroup{
			{ID: "kids", Enabled: true, Clients: []string{"192.168.1.0/24"}},
			{ID: "guest", Enabled: true, Clients: []string{"192.168.2.0/24"}},
		},
	})
	if err != nil {
		t.Fatalf("NewGroupResolver 失败: %v", err)
	}

	mw := NewFilterMiddlewareWithGroups(engine, func() *core.GroupResolver { return resolver })

	// kids 客户端：命中广告列表 → 拦截
	ctx := groupCtx("192.168.1.9")
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if ctx.Resp == nil || !isBlocked(ctx) {
		t.Fatalf("kids 组应被拦截, resp=%v", ctx.Resp)
	}
	if g, _ := ctx.Get("client_group"); g != "kids" {
		t.Fatalf("应标记 client_group=kids, 得到 %v", g)
	}

	// guest 客户端：未绑定广告列表 → 放行
	ctx = groupCtx("192.168.2.9")
	nextCalled := false
	if err := mw(ctx, func() error { nextCalled = true; return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if !nextCalled || ctx.Resp != nil {
		t.Fatalf("guest 组应放行, nextCalled=%v resp=%v", nextCalled, ctx.Resp)
	}
}

func TestFilterMiddlewareNilResolverUsesDefault(t *testing.T) {
	engine := groupFilterEngine(t)

	// 不带分组解析器（nil）时应按默认组评估，命中全量规则即拦截
	mw := NewFilterMiddlewareWithGroups(engine, nil)
	ctx := groupCtx("192.168.1.9")
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if ctx.Resp == nil || !isBlocked(ctx) {
		t.Fatalf("默认组应命中全量规则并拦截, resp=%v", ctx.Resp)
	}
}

func TestFilterMiddlewareGroupBlockModeOverride(t *testing.T) {
	engine := groupFilterEngine(t)

	if err := engine.SetClientGroups(core.ClientGroupConfig{
		Enabled: true,
		Groups: []core.ClientGroup{
			{ID: "strict", Name: "严格", Enabled: true, BlockMode: core.BlockModeNXDOMAIN},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}
	resolver, err := core.NewGroupResolver(core.ClientGroupConfig{
		Enabled: true,
		Groups:  []core.ClientGroup{{ID: "strict", Enabled: true, Clients: []string{"192.168.1.0/24"}}},
	})
	if err != nil {
		t.Fatalf("NewGroupResolver 失败: %v", err)
	}

	mw := NewFilterMiddlewareWithGroups(engine, func() *core.GroupResolver { return resolver })
	ctx := groupCtx("192.168.1.9")
	if err := mw(ctx, func() error { return nil }); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if ctx.Resp == nil {
		t.Fatalf("应生成拦截响应")
	}
	if ctx.Resp.Rcode != dns.RcodeNameError {
		t.Fatalf("组级覆盖应返回 NXDOMAIN, 得到 %v", dns.RcodeToString[ctx.Resp.Rcode])
	}
}

// isBlocked 读取中间件写入的拦截标记。
func isBlocked(ctx *DNSContext) bool {
	v, ok := ctx.Get("filter_blocked")
	if !ok {
		return false
	}
	b, _ := v.(bool)
	return b
}
