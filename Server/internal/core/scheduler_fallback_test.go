package core

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/miekg/dns"
)

// fallbackExecutor 按 ID 分派的桩执行器
func fallbackExecutor(handlers map[string]func(ctx context.Context) ([]byte, error)) ProviderExecutor {
	return func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		if h, ok := handlers[p.ID]; ok {
			return h(ctx)
		}
		return makeTestDNSResponse(q, dns.RcodeSuccess, "9.9.9.9"), nil
	}
}

func okResp(q []byte, ip string) ([]byte, error) {
	return makeTestDNSResponse(q, dns.RcodeSuccess, ip), nil
}

func TestFallback_DisabledByDefault(t *testing.T) {
	rawQuery := makeTestDNSQuery("no-fallback.test.com")
	calls := 0
	s := NewScheduler(func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		calls++
		return okResp(q, "1.1.1.1")
	})

	// 未配置回退链时，主链路不得被施加任何超时或额外包装
	plan := FallbackPlan{Mode: ModeSingle, Providers: []*ConfiguredProvider{{ID: "main", Stats: NewProviderStats()}}}
	resp, err := s.resolveWithFallback(context.Background(), plan, rawQuery)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if calls != 1 {
		t.Fatalf("expected exactly 1 call, got %d", calls)
	}
	if rcode, _ := responseRcode(resp); rcode != dns.RcodeSuccess {
		t.Fatalf("unexpected rcode %d", rcode)
	}
}

func TestFallback_TriggersOnTransportError(t *testing.T) {
	rawQuery := makeTestDNSQuery("transport.test.com")
	s := NewScheduler(fallbackExecutor(map[string]func(context.Context) ([]byte, error){
		"main": func(context.Context) ([]byte, error) { return nil, errors.New("connection refused") },
		"fb":   func(ctx context.Context) ([]byte, error) { return okResp(rawQuery, "2.2.2.2") },
	}))

	plan := FallbackPlan{
		Mode:              ModeSingle,
		Providers:         []*ConfiguredProvider{{ID: "main", Stats: NewProviderStats()}},
		FallbackProviders: []*ConfiguredProvider{{ID: "fb", Stats: NewProviderStats()}},
		Timeout:           2 * time.Second,
	}
	resp, err := s.resolveWithFallback(context.Background(), plan, rawQuery)
	if err != nil {
		t.Fatalf("fallback should have answered: %v", err)
	}
	var msg dns.Msg
	if err := msg.Unpack(resp); err != nil || len(msg.Answer) != 1 {
		t.Fatalf("unexpected response")
	}
	if msg.Answer[0].(*dns.A).A.String() != "2.2.2.2" {
		t.Fatalf("expected fallback answer, got %v", msg.Answer[0])
	}
}

func TestFallback_TriggersOnServfailAndRefused(t *testing.T) {
	for _, rcode := range []int{dns.RcodeServerFailure, dns.RcodeRefused} {
		rawQuery := makeTestDNSQuery("rcode.test.com")
		fbUsed := false
		s := NewScheduler(fallbackExecutor(map[string]func(context.Context) ([]byte, error){
			"main": func(context.Context) ([]byte, error) {
				return makeTestDNSResponse(rawQuery, rcode, ""), nil
			},
			"fb": func(ctx context.Context) ([]byte, error) {
				fbUsed = true
				return okResp(rawQuery, "3.3.3.3")
			},
		}))

		plan := FallbackPlan{
			Mode:              ModeSingle,
			Providers:         []*ConfiguredProvider{{ID: "main", Stats: NewProviderStats()}},
			FallbackProviders: []*ConfiguredProvider{{ID: "fb", Stats: NewProviderStats()}},
		}
		resp, err := s.resolveWithFallback(context.Background(), plan, rawQuery)
		if err != nil {
			t.Fatalf("rcode %s: unexpected error: %v", dns.RcodeToString[rcode], err)
		}
		if !fbUsed {
			t.Fatalf("rcode %s: fallback chain was not used", dns.RcodeToString[rcode])
		}
		if got, _ := responseRcode(resp); got != dns.RcodeSuccess {
			t.Fatalf("rcode %s: expected success from fallback, got %d", dns.RcodeToString[rcode], got)
		}
	}
}

// NXDOMAIN 是权威有效判定，回退它会放大上游查询量并掩盖真实结果。
func TestFallback_DoesNotTriggerOnNxdomain(t *testing.T) {
	rawQuery := makeTestDNSQuery("nx.test.com")
	fbUsed := false
	s := NewScheduler(fallbackExecutor(map[string]func(context.Context) ([]byte, error){
		"main": func(context.Context) ([]byte, error) {
			return makeTestDNSResponse(rawQuery, dns.RcodeNameError, ""), nil
		},
		"fb": func(ctx context.Context) ([]byte, error) {
			fbUsed = true
			return okResp(rawQuery, "4.4.4.4")
		},
	}))

	plan := FallbackPlan{
		Mode:              ModeSingle,
		Providers:         []*ConfiguredProvider{{ID: "main", Stats: NewProviderStats()}},
		FallbackProviders: []*ConfiguredProvider{{ID: "fb", Stats: NewProviderStats()}},
	}
	resp, err := s.resolveWithFallback(context.Background(), plan, rawQuery)
	if err != nil {
		// NXDOMAIN 应被判定为有效应答而非错误
		t.Fatalf("NXDOMAIN must be treated as a valid answer: %v", err)
	}
	if fbUsed {
		t.Fatal("NXDOMAIN must not trigger the fallback chain")
	}
	if rcode, _ := responseRcode(resp); rcode != dns.RcodeNameError {
		t.Fatalf("expected NXDOMAIN to pass through, got rcode %d", rcode)
	}
}

// 调用方主动取消不得触发回退：否则用户中断一个查询会白白向备用上游再发一轮。
func TestFallback_DoesNotTriggerOnCallerCancel(t *testing.T) {
	rawQuery := makeTestDNSQuery("cancel.test.com")
	fbUsed := false
	s := NewScheduler(fallbackExecutor(map[string]func(context.Context) ([]byte, error){
		"main": func(ctx context.Context) ([]byte, error) { return nil, ctx.Err() },
		"fb": func(ctx context.Context) ([]byte, error) {
			fbUsed = true
			return okResp(rawQuery, "5.5.5.5")
		},
	}))

	plan := FallbackPlan{
		Mode:              ModeSingle,
		Providers:         []*ConfiguredProvider{{ID: "main", Stats: NewProviderStats()}},
		FallbackProviders: []*ConfiguredProvider{{ID: "fb", Stats: NewProviderStats()}},
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	if _, err := s.resolveWithFallback(ctx, plan, rawQuery); err == nil {
		t.Fatal("expected an error from a canceled caller")
	}
	if fbUsed {
		t.Fatal("caller cancellation must not trigger the fallback chain")
	}
}

// 主链路超时（而非调用方取消）应当转入回退链。
func TestFallback_TriggersOnMainChainTimeout(t *testing.T) {
	rawQuery := makeTestDNSQuery("slow.test.com")
	s := NewScheduler(fallbackExecutor(map[string]func(context.Context) ([]byte, error){
		"main": func(ctx context.Context) ([]byte, error) {
			<-ctx.Done()
			return nil, ctx.Err()
		},
		"fb": func(ctx context.Context) ([]byte, error) { return okResp(rawQuery, "6.6.6.6") },
	}))

	plan := FallbackPlan{
		Mode:              ModeSingle,
		Providers:         []*ConfiguredProvider{{ID: "main", Stats: NewProviderStats()}},
		FallbackProviders: []*ConfiguredProvider{{ID: "fb", Stats: NewProviderStats()}},
		Timeout:           50 * time.Millisecond,
	}
	resp, err := s.resolveWithFallback(context.Background(), plan, rawQuery)
	if err != nil {
		t.Fatalf("main-chain timeout should divert to fallback: %v", err)
	}
	var msg dns.Msg
	if err := msg.Unpack(resp); err != nil {
		t.Fatalf("unpack: %v", err)
	}
	if msg.Answer[0].(*dns.A).A.String() != "6.6.6.6" {
		t.Fatalf("expected fallback answer, got %v", msg.Answer[0])
	}
}

// 回退链自身不得再回退，否则会形成递归与查询放大。
func TestFallback_NoRecursiveFallback(t *testing.T) {
	rawQuery := makeTestDNSQuery("recursive.test.com")
	mainCalls, fbCalls := 0, 0
	s := NewScheduler(fallbackExecutor(map[string]func(context.Context) ([]byte, error){
		"main": func(context.Context) ([]byte, error) { mainCalls++; return nil, errors.New("down") },
		"fb":   func(context.Context) ([]byte, error) { fbCalls++; return nil, errors.New("also down") },
	}))

	plan := FallbackPlan{
		Mode:              ModeSingle,
		Providers:         []*ConfiguredProvider{{ID: "main", Stats: NewProviderStats()}},
		FallbackProviders: []*ConfiguredProvider{{ID: "fb", Stats: NewProviderStats()}},
	}
	if _, err := s.resolveWithFallback(context.Background(), plan, rawQuery); err == nil {
		t.Fatal("expected both chains to fail")
	}
	if mainCalls != 1 || fbCalls != 1 {
		t.Fatalf("expected one call per chain, got main=%d fb=%d", mainCalls, fbCalls)
	}
}

func TestFallback_OnErrorDisabled(t *testing.T) {
	rawQuery := makeTestDNSQuery("onerror.test.com")
	fbUsed := false
	s := NewScheduler(fallbackExecutor(map[string]func(context.Context) ([]byte, error){
		"main": func(context.Context) ([]byte, error) { return nil, errors.New("down") },
		"fb": func(ctx context.Context) ([]byte, error) {
			fbUsed = true
			return okResp(rawQuery, "7.7.7.7")
		},
	}))

	off := false
	plan := FallbackPlan{
		Mode:              ModeSingle,
		Providers:         []*ConfiguredProvider{{ID: "main", Stats: NewProviderStats()}},
		FallbackProviders: []*ConfiguredProvider{{ID: "fb", Stats: NewProviderStats()}},
		OnError:           &off,
	}
	if _, err := s.resolveWithFallback(context.Background(), plan, rawQuery); err == nil {
		t.Fatal("expected the transport error to surface")
	}
	if fbUsed {
		t.Fatal("OnError=false must keep transport failures on the primary chain")
	}
}

// 只把 NOTIMP 列为触发码时，SERVFAIL 不得回退，NOTIMP 必须回退。
func TestFallback_CustomRcodeSet(t *testing.T) {
	rawQuery := makeTestDNSQuery("custom-rcode.test.com")

	run := func(mainRcode int) (fbUsed bool, err error) {
		s := NewScheduler(fallbackExecutor(map[string]func(context.Context) ([]byte, error){
			"main": func(context.Context) ([]byte, error) {
				return makeTestDNSResponse(rawQuery, mainRcode, ""), nil
			},
			"fb": func(ctx context.Context) ([]byte, error) {
				fbUsed = true
				return okResp(rawQuery, "8.8.8.8")
			},
		}))
		plan := FallbackPlan{
			Mode:              ModeSingle,
			Providers:         []*ConfiguredProvider{{ID: "main", Stats: NewProviderStats()}},
			FallbackProviders: []*ConfiguredProvider{{ID: "fb", Stats: NewProviderStats()}},
			OnRcode:           []int{dns.RcodeNotImplemented},
		}
		_, err = s.resolveWithFallback(context.Background(), plan, rawQuery)
		return fbUsed, err
	}

	// SERVFAIL 不在配置集合内：不回退，且主链路的错误必须原样上抛
	if fbUsed, err := run(dns.RcodeServerFailure); fbUsed || err == nil {
		t.Fatalf("SERVFAIL must not fall back under a NOTIMP-only set (fbUsed=%v, err=%v)", fbUsed, err)
	}

	// NOTIMP 在配置集合内：回退并作答
	fbUsed, err := run(dns.RcodeNotImplemented)
	if err != nil {
		t.Fatalf("NOTIMP should divert to the fallback chain: %v", err)
	}
	if !fbUsed {
		t.Fatal("NOTIMP must trigger the fallback chain")
	}
}

func TestFallbackRcodes_Defaults(t *testing.T) {
	got := fallbackRcodes(nil)
	if len(got) != 2 || got[0] != dns.RcodeServerFailure || got[1] != dns.RcodeRefused {
		t.Fatalf("unexpected defaults: %v", got)
	}
	for _, rc := range got {
		if rc == dns.RcodeNameError || rc == dns.RcodeSuccess {
			t.Fatalf("defaults must not include NXDOMAIN or NOERROR")
		}
	}
	if custom := fallbackRcodes([]int{dns.RcodeNotImplemented}); len(custom) != 1 {
		t.Fatalf("explicit set must win: %v", custom)
	}
}

// 端到端：经 CoreResolver 的公开入口验证回退链确实生效。
func TestFallback_CoreResolverEndToEnd(t *testing.T) {
	rawQuery := makeTestDNSQuery("e2e-fallback.test.com")
	mainUsed, fbUsed := 0, 0

	bs := NewBootstrapResolver(BootstrapConfig{})
	r := &CoreResolver{bootstrap: bs, plain: NewPlainResolver(bs)}
	r.scheduler = NewScheduler(func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		if p.ID == "fb" {
			fbUsed++
			return okResp(q, "10.0.0.1")
		}
		mainUsed++
		return makeTestDNSResponse(q, dns.RcodeServerFailure, ""), nil
	})

	onError := true
	cfg := ResolverConfig{
		Mode:              ModeSingle,
		Providers:         []ProviderConfig{{ID: "main", Protocol: ProtocolPlain, Server: "127.0.0.1:53"}},
		FallbackProviders: []ProviderConfig{{ID: "fb", Protocol: ProtocolPlain, Server: "127.0.0.2:53"}},
		FallbackOnError:   &onError,
	}
	if err := r.Configure(cfg); err != nil {
		t.Fatalf("configure: %v", err)
	}

	resp, err := r.Resolve(context.Background(), rawQuery)
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if mainUsed != 1 || fbUsed != 1 {
		t.Fatalf("expected both chains to run once, got main=%d fb=%d", mainUsed, fbUsed)
	}
	var msg dns.Msg
	if err := msg.Unpack(resp); err != nil {
		t.Fatalf("unpack: %v", err)
	}
	if len(msg.Answer) == 0 || msg.Answer[0].(*dns.A).A.String() != "10.0.0.1" {
		t.Fatalf("expected the fallback answer, got %v", msg.Answer)
	}
}

// 回退链上的上游同样参与证书固定表，否则加密回退会静默跳过固定校验。
func TestFallback_PinLookupIncludesFallbackProviders(t *testing.T) {
	bs := NewBootstrapResolver(BootstrapConfig{})
	r := &CoreResolver{bootstrap: bs}
	if err := r.Configure(ResolverConfig{
		Mode:              ModeSingle,
		Providers:         []ProviderConfig{{ID: "main", Protocol: ProtocolDoT, Server: "main.test:853"}},
		FallbackProviders: []ProviderConfig{{ID: "fb", Protocol: ProtocolDoT, Server: "fb.test:853", Pin: strings.Repeat("ab", 32)}},
	}); err != nil {
		t.Fatalf("configure: %v", err)
	}

	lookup := r.PinLookup()
	if lookup == nil {
		t.Fatal("expected a pin lookup including the fallback provider")
	}
	if lookup("fb.test") == nil {
		t.Fatal("fallback provider pin must be registered")
	}
	if lookup("main.test") != nil {
		t.Fatal("unpinned main provider must stay unpinned")
	}
}
