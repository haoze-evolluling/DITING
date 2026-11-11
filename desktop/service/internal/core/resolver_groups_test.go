package core

import (
	"context"
	"net"
	"testing"

	"github.com/miekg/dns"
)

// groupTestResolver 构建含两个上游节点的解析器，并注入按 ID 分派的桩执行器。
func groupTestResolver(t *testing.T, handlers map[string]func(*dns.Msg) *dns.Msg) *CoreResolver {
	t.Helper()

	bs := NewBootstrapResolver(BootstrapConfig{})
	r := &CoreResolver{bootstrap: bs, plain: NewPlainResolver(bs)}
	r.scheduler = NewScheduler(func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		var req dns.Msg
		if err := req.Unpack(q); err != nil {
			return nil, err
		}
		h, ok := handlers[p.ID]
		if !ok {
			return makeTestDNSResponse(q, dns.RcodeSuccess, "0.0.0.0"), nil
		}
		resp := h(&req)
		resp.Id = req.Id
		return resp.Pack()
	})

	if err := r.Configure(ResolverConfig{
		Mode: ModeSingle,
		Providers: []ProviderConfig{
			{ID: "main-a", Protocol: ProtocolPlain, Server: "10.0.0.1:53"},
			{ID: "main-b", Protocol: ProtocolPlain, Server: "10.0.0.2:53"},
		},
	}); err != nil {
		t.Fatalf("configure: %v", err)
	}
	return r
}

func nameResponse(host string, ip string) func(*dns.Msg) *dns.Msg {
	return func(req *dns.Msg) *dns.Msg {
		resp := new(dns.Msg)
		resp.SetReply(req)
		rr, _ := dns.NewRR(host + " 300 IN A " + ip)
		resp.Answer = append(resp.Answer, rr)
		return resp
	}
}

func TestGroupUpstreams_BindsDedicatedChain(t *testing.T) {
	r := groupTestResolver(t, map[string]func(*dns.Msg) *dns.Msg{
		"main-a": nameResponse("kids.test.", "1.1.1.1"),
		"main-b": nameResponse("kids.test.", "2.2.2.2"),
	})

	if err := r.SetGroupUpstreams(map[string][]string{"kids": {"main-b"}}); err != nil {
		t.Fatalf("SetGroupUpstreams: %v", err)
	}
	if !r.HasGroupUpstreams("kids") {
		t.Fatal("kids group should have dedicated upstreams")
	}
	if r.HasGroupUpstreams("guest") {
		t.Fatal("unbound group must not report dedicated upstreams")
	}

	req := new(dns.Msg)
	req.SetQuestion("kids.test.", dns.TypeA)
	resp, err := r.ExchangeForGroup(context.Background(), "kids", req)
	if err != nil {
		t.Fatalf("ExchangeForGroup: %v", err)
	}
	if got := resp.Answer[0].(*dns.A).A.String(); got != "2.2.2.2" {
		t.Fatalf("expected the dedicated upstream answer, got %s", got)
	}
}

func TestGroupUpstreams_UnboundGroupErrors(t *testing.T) {
	r := groupTestResolver(t, nil)

	req := new(dns.Msg)
	req.SetQuestion("x.test.", dns.TypeA)
	if _, err := r.ExchangeForGroup(context.Background(), "nobody", req); err == nil {
		t.Fatal("an unbound group must report an error rather than silently using the main chain")
	}
}

// 未知上游 ID 必须被剔除，且不能影响同批中合法的绑定。
func TestGroupUpstreams_UnknownIDsAreReported(t *testing.T) {
	r := groupTestResolver(t, nil)

	err := r.SetGroupUpstreams(map[string][]string{
		"kids":  {"main-a", "does-not-exist"},
		"empty": {"also-missing"},
	})
	if err == nil {
		t.Fatal("expected a report of the unknown upstream ID")
	}

	ids := r.GroupUpstreamIDs()
	if len(ids["kids"]) != 1 || ids["kids"][0] != "main-a" {
		t.Fatalf("the valid binding must survive: %v", ids)
	}
	if _, ok := ids["empty"]; ok {
		t.Fatalf("a group whose every upstream is unknown must not be registered: %v", ids)
	}
}

// 保留组 default 不得被绑定：它本身就是"未命中分组"的回落目标。
func TestGroupUpstreams_DefaultGroupReserved(t *testing.T) {
	r := groupTestResolver(t, nil)

	if err := r.SetGroupUpstreams(map[string][]string{DefaultClientGroupID: {"main-a"}}); err == nil {
		t.Fatal("the reserved default group must not accept a dedicated upstream")
	}
	if r.HasGroupUpstreams(DefaultClientGroupID) {
		t.Fatal("the default group must never report dedicated upstreams")
	}
}

// 上游列表热重建后，分组绑定必须重新指向新节点对象，而不是停留在旧指针上。
func TestGroupUpstreams_RebindAfterReconfigure(t *testing.T) {
	r := groupTestResolver(t, map[string]func(*dns.Msg) *dns.Msg{
		"main-a": nameResponse("re.test.", "1.1.1.1"),
		"main-b": nameResponse("re.test.", "2.2.2.2"),
	})
	if err := r.SetGroupUpstreams(map[string][]string{"kids": {"main-b"}}); err != nil {
		t.Fatalf("SetGroupUpstreams: %v", err)
	}

	// 热更新：节点被整体重建
	if err := r.Configure(ResolverConfig{
		Mode: ModeSingle,
		Providers: []ProviderConfig{
			{ID: "main-a", Protocol: ProtocolPlain, Server: "10.0.0.1:53"},
			{ID: "main-b", Protocol: ProtocolPlain, Server: "10.0.0.2:53"},
		},
	}); err != nil {
		t.Fatalf("reconfigure: %v", err)
	}

	if !r.HasGroupUpstreams("kids") {
		t.Fatal("the group binding must survive a reconfigure")
	}

	req := new(dns.Msg)
	req.SetQuestion("re.test.", dns.TypeA)
	resp, err := r.ExchangeForGroup(context.Background(), "kids", req)
	if err != nil {
		t.Fatalf("ExchangeForGroup after reconfigure: %v", err)
	}
	if got := resp.Answer[0].(*dns.A).A.String(); got != "2.2.2.2" {
		t.Fatalf("the binding must point at the rebuilt node, got %s", got)
	}
}

func TestGroupUpstreams_EmptyMapDisables(t *testing.T) {
	r := groupTestResolver(t, nil)
	if err := r.SetGroupUpstreams(map[string][]string{"kids": {"main-a"}}); err != nil {
		t.Fatalf("SetGroupUpstreams: %v", err)
	}
	if err := r.SetGroupUpstreams(nil); err != nil {
		t.Fatalf("clearing: %v", err)
	}
	if r.HasGroupUpstreams("kids") {
		t.Fatal("clearing the map must unbind every group")
	}
	if r.GroupUpstreamIDs() != nil {
		t.Fatal("cleared state must report nil")
	}
}

func TestCacheKeyForGroup_DefaultMatchesLegacy(t *testing.T) {
	base := CacheKey("Example.COM.", dns.TypeA, dns.ClassINET)
	for _, group := range []string{"", DefaultClientGroupID, "  "} {
		if got := CacheKeyForGroup("Example.COM.", dns.TypeA, dns.ClassINET, group); got != base {
			t.Fatalf("group %q must fall back to the legacy key: %q != %q", group, got, base)
		}
	}
	if got := CacheKeyForGroup("Example.COM.", dns.TypeA, dns.ClassINET, "kids"); got == base {
		t.Fatal("a real group must produce a distinct key")
	}
}

func TestGroupUpstreamMap_SkipsUnboundAndDisabled(t *testing.T) {
	cfg := ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{ID: "kids", Enabled: true, Clients: []string{"192.168.1.0/24"}, UpstreamIDs: []string{"main-a", "main-a", " "}},
			{ID: "off", Enabled: false, UpstreamIDs: []string{"main-b"}},
			{ID: "plain", Enabled: true, Clients: []string{"10.0.0.0/8"}},
		},
	}

	got := cfg.GroupUpstreamMap()
	if len(got) != 1 {
		t.Fatalf("only the enabled bound group should appear: %v", got)
	}
	if ids := got["kids"]; len(ids) != 1 || ids[0] != "main-a" {
		t.Fatalf("duplicates and blanks must be dropped: %v", ids)
	}

	// 未启用分组功能时整体关闭
	cfg.Enabled = false
	if m := cfg.GroupUpstreamMap(); m != nil {
		t.Fatalf("disabling groups must disable the whole mapping: %v", m)
	}
}

func TestGroupResolver_LongestPrefixStillWins(t *testing.T) {
	gr, err := NewGroupResolver(ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{ID: "wide", Enabled: true, Clients: []string{"192.168.0.0/16"}},
			{ID: "narrow", Enabled: true, Clients: []string{"192.168.1.0/24"}},
		},
	})
	if err != nil {
		t.Fatalf("NewGroupResolver: %v", err)
	}
	if got := gr.Resolve(net.ParseIP("192.168.1.9")); got != "narrow" {
		t.Fatalf("longest prefix must win, got %s", got)
	}
	if got := gr.Resolve(net.ParseIP("192.168.9.9")); got != "wide" {
		t.Fatalf("expected the wide group, got %s", got)
	}
}
