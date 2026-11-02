package dns

import (
	"context"
	"errors"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// stubGroupResolver 记录调用并返回预设应答的桩
type stubGroupResolver struct {
	bound   map[string]bool
	answer  map[string]string
	err     error
	calls   []string
	lastCtx context.Context
}

func (s *stubGroupResolver) HasGroupUpstreams(group string) bool {
	return s.bound[group]
}

func (s *stubGroupResolver) ExchangeForGroup(ctx context.Context, group string, req *dns.Msg) (*dns.Msg, error) {
	s.calls = append(s.calls, group)
	s.lastCtx = ctx
	if s.err != nil {
		return nil, s.err
	}
	ip, ok := s.answer[group]
	if !ok {
		return nil, errors.New("no answer configured")
	}
	resp := new(dns.Msg)
	resp.SetReply(req)
	rr, _ := dns.NewRR("route.test. 300 IN A " + ip)
	resp.Answer = append(resp.Answer, rr)
	return resp, nil
}

func routeGroups(t *testing.T, members map[string]string) *core.GroupResolver {
	t.Helper()
	groups := make([]core.ClientGroup, 0, len(members))
	for id, cidr := range members {
		groups = append(groups, core.ClientGroup{ID: id, Enabled: true, Clients: []string{cidr}})
	}
	gr, err := core.NewGroupResolver(core.ClientGroupConfig{Enabled: true, Groups: groups})
	if err != nil {
		t.Fatalf("NewGroupResolver: %v", err)
	}
	return gr
}

func routeCtx(ip string) *DNSContext {
	req := new(dns.Msg)
	req.SetQuestion("route.test.", dns.TypeA)
	return NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP(ip), Port: 5555}, "udp")
}

// 分组标记由 client 中间件写入，取答中间件依赖它做判定
func markGroup(ctx *DNSContext, groups *core.GroupResolver) {
	_ = NewClientMiddlewareWithGroups(nil, func() *core.GroupResolver { return groups })(ctx, func() error { return nil })
}

func TestUpstreamRoute_ShortCircuitsForBoundGroup(t *testing.T) {
	groups := routeGroups(t, map[string]string{"kids": "192.168.1.0/24"})
	stub := &stubGroupResolver{
		bound:  map[string]bool{"kids": true},
		answer: map[string]string{"kids": "9.9.9.9"},
	}

	ctx := routeCtx("192.168.1.9")
	markGroup(ctx, groups)

	nextCalled := false
	mw := NewUpstreamRouteMiddleware(stub, func() *core.GroupResolver { return groups })
	if err := mw(ctx, func() error { nextCalled = true; return nil }); err != nil {
		t.Fatalf("middleware error: %v", err)
	}

	if nextCalled {
		t.Fatal("a bound group must short-circuit and not reach the forward middleware")
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 1 {
		t.Fatalf("expected a response from the dedicated upstream, got %v", ctx.Resp)
	}
	if got := ctx.Resp.Answer[0].(*dns.A).A.String(); got != "9.9.9.9" {
		t.Fatalf("unexpected answer %s", got)
	}
	if v, _ := ctx.Get("upstream_route"); v != "kids" {
		t.Fatalf("expected the route marker, got %v", v)
	}
	if len(stub.calls) != 1 {
		t.Fatalf("expected exactly one exchange, got %v", stub.calls)
	}
}

// 未绑定专属上游的分组必须原样放行，行为与未注册本中间件一致
func TestUpstreamRoute_PassesThroughUnboundGroup(t *testing.T) {
	groups := routeGroups(t, map[string]string{"guest": "192.168.2.0/24"})
	stub := &stubGroupResolver{bound: map[string]bool{}, answer: map[string]string{}}

	ctx := routeCtx("192.168.2.9")
	markGroup(ctx, groups)

	nextCalled := false
	if err := NewUpstreamRouteMiddleware(stub, func() *core.GroupResolver { return groups })(ctx, func() error {
		nextCalled = true
		return nil
	}); err != nil {
		t.Fatalf("middleware error: %v", err)
	}
	if !nextCalled || ctx.Resp != nil {
		t.Fatalf("unbound group must pass through, nextCalled=%v resp=%v", nextCalled, ctx.Resp)
	}
	if len(stub.calls) != 0 {
		t.Fatalf("no exchange should happen for an unbound group, got %v", stub.calls)
	}
}

// 默认组永远不参与专属路由——它是"未命中分组"的回落目标
func TestUpstreamRoute_DefaultGroupNeverRoutes(t *testing.T) {
	groups := routeGroups(t, map[string]string{"kids": "192.168.1.0/24"})
	stub := &stubGroupResolver{
		bound:  map[string]bool{core.DefaultClientGroupID: true},
		answer: map[string]string{core.DefaultClientGroupID: "8.8.8.8"},
	}

	ctx := routeCtx("10.1.2.3") // 未命中任何分组
	markGroup(ctx, groups)

	nextCalled := false
	if err := NewUpstreamRouteMiddleware(stub, func() *core.GroupResolver { return groups })(ctx, func() error {
		nextCalled = true
		return nil
	}); err != nil {
		t.Fatalf("middleware error: %v", err)
	}
	if !nextCalled {
		t.Fatal("the default group must not be served by a dedicated upstream")
	}
	if len(stub.calls) != 0 {
		t.Fatalf("the default group must never be dispatched, got %v", stub.calls)
	}
}

// 专属上游故障时应回落默认链路，而不是让整次解析失败
func TestUpstreamRoute_FallsBackOnError(t *testing.T) {
	groups := routeGroups(t, map[string]string{"kids": "192.168.1.0/24"})
	stub := &stubGroupResolver{bound: map[string]bool{"kids": true}, err: errors.New("upstream down")}

	ctx := routeCtx("192.168.1.9")
	markGroup(ctx, groups)

	nextCalled := false
	if err := NewUpstreamRouteMiddleware(stub, func() *core.GroupResolver { return groups })(ctx, func() error {
		nextCalled = true
		return nil
	}); err != nil {
		t.Fatalf("a failing dedicated upstream must not surface as an error: %v", err)
	}
	if !nextCalled {
		t.Fatal("expected a fallback to the default chain")
	}
	if ctx.Resp != nil {
		t.Fatalf("the middleware must not fabricate a response, got %v", ctx.Resp)
	}
}

// nil 参数必须等价于空操作，使调用方可以无条件注册
func TestUpstreamRoute_NilDependenciesAreNoOps(t *testing.T) {
	groups := routeGroups(t, map[string]string{"kids": "192.168.1.0/24"})

	for name, mw := range map[string]Middleware{
		"nil resolver": NewUpstreamRouteMiddleware(nil, func() *core.GroupResolver { return groups }),
		"nil groups":   NewUpstreamRouteMiddleware(&stubGroupResolver{}, nil),
	} {
		ctx := routeCtx("192.168.1.9")
		markGroup(ctx, groups)
		nextCalled := false
		if err := mw(ctx, func() error { nextCalled = true; return nil }); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if !nextCalled {
			t.Fatalf("%s must be a no-op", name)
		}
	}
}

// 缓存中间件必须按分组隔离：不同分组可能被路由到不同上游
func TestCacheMiddleware_IsolatesGroups(t *testing.T) {
	cache := core.NewDNSCache(core.DefaultCacheConfig())
	t.Cleanup(cache.Close)

	groups := routeGroups(t, map[string]string{
		"kids":  "192.168.1.0/24",
		"guest": "192.168.2.0/24",
	})

	answers := map[string]string{"192.168.1.9": "1.1.1.1", "192.168.2.9": "2.2.2.2"}
	var inner int
	innerMw := func(ctx *DNSContext, next func() error) error {
		inner++
		resp := new(dns.Msg)
		resp.SetReply(ctx.Req)
		rr, _ := dns.NewRR("iso.test. 300 IN A " + answers[ctx.ClientIP.String()])
		resp.Answer = append(resp.Answer, rr)
		ctx.Resp = resp
		return nil
	}

	pipeline := NewPipeline(
		NewClientMiddlewareWithGroups(nil, func() *core.GroupResolver { return groups }),
		NewCacheMiddlewareWithGroups(cache, nil, func() *core.GroupResolver { return groups }),
		innerMw,
	)

	lookup := func(ip string) string {
		ctx := routeCtx(ip)
		ctx.Req.Question[0].Name = "iso.test."
		if err := pipeline.Execute(ctx); err != nil {
			t.Fatalf("pipeline: %v", err)
		}
		return ctx.Resp.Answer[0].(*dns.A).A.String()
	}

	// 两组各查一次，各自应拿到自己的应答
	if got := lookup("192.168.1.9"); got != "1.1.1.1" {
		t.Fatalf("kids answer = %s", got)
	}
	if got := lookup("192.168.2.9"); got != "2.2.2.2" {
		t.Fatalf("guest answer = %s", got)
	}
	if inner != 2 {
		t.Fatalf("expected two upstream calls, got %d", inner)
	}

	// 再次查询应命中各自分组的缓存，且内容不得串组
	if got := lookup("192.168.1.9"); got != "1.1.1.1" {
		t.Fatalf("kids cached answer = %s", got)
	}
	if got := lookup("192.168.2.9"); got != "2.2.2.2" {
		t.Fatalf("guest cached answer = %s", got)
	}
	if inner != 2 {
		t.Fatalf("cache hits must not reach the upstream, got %d inner calls", inner)
	}
}
