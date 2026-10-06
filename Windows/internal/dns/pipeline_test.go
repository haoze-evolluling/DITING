package dns

import (
	"context"
	"errors"
	"net"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	miekgdns "github.com/miekg/dns"
)

type mockResolver struct {
	exchangeFunc func(ctx context.Context, req *miekgdns.Msg) (*miekgdns.Msg, error)
}

func (m *mockResolver) Resolve(ctx context.Context, raw []byte) ([]byte, error) {
	return nil, nil
}

func (m *mockResolver) Exchange(ctx context.Context, req *miekgdns.Msg) (*miekgdns.Msg, error) {
	if m.exchangeFunc != nil {
		return m.exchangeFunc(ctx, req)
	}
	resp := new(miekgdns.Msg)
	resp.SetReply(req)
	return resp, nil
}

func (m *mockResolver) Configure(cfg core.ResolverConfig) error {
	return nil
}

func (m *mockResolver) Shutdown() error {
	return nil
}

func TestPipeline_ExecutionOrder(t *testing.T) {
	var trace []string

	m1 := func(ctx *DNSContext, next func() error) error {
		trace = append(trace, "m1:start")
		err := next()
		trace = append(trace, "m1:end")
		return err
	}

	m2 := func(ctx *DNSContext, next func() error) error {
		trace = append(trace, "m2:start")
		err := next()
		trace = append(trace, "m2:end")
		return err
	}

	p := NewPipeline(m1, m2)
	ctx := NewDNSContext(context.Background(), new(miekgdns.Msg), nil, "udp")

	if err := p.Execute(ctx); err != nil {
		t.Fatalf("pipeline execute failed: %v", err)
	}

	expected := []string{"m1:start", "m2:start", "m2:end", "m1:end"}
	if len(trace) != len(expected) {
		t.Fatalf("unexpected trace length: %v", trace)
	}
	for i := range expected {
		if trace[i] != expected[i] {
			t.Fatalf("trace[%d] = %s, expected %s", i, trace[i], expected[i])
		}
	}
}

func TestPipeline_ShortCircuit(t *testing.T) {
	var trace []string

	m1 := func(ctx *DNSContext, next func() error) error {
		trace = append(trace, "m1:block")
		return nil // 不调用 next()
	}

	m2 := func(ctx *DNSContext, next func() error) error {
		trace = append(trace, "m2:never")
		return next()
	}

	p := NewPipeline(m1, m2)
	ctx := NewDNSContext(context.Background(), new(miekgdns.Msg), nil, "udp")

	_ = p.Execute(ctx)
	if len(trace) != 1 || trace[0] != "m1:block" {
		t.Fatalf("expected short-circuit at m1, got trace: %v", trace)
	}
}

func TestPipeline_ForwardAndMetrics(t *testing.T) {
	res := &mockResolver{
		exchangeFunc: func(ctx context.Context, req *miekgdns.Msg) (*miekgdns.Msg, error) {
			resp := new(miekgdns.Msg)
			resp.SetReply(req)
			rr, _ := miekgdns.NewRR("example.com. 300 IN A 1.2.3.4")
			resp.Answer = append(resp.Answer, rr)
			return resp, nil
		},
	}

	metricsCalled := false
	var recordedDuration time.Duration

	metricsMw := NewMetricsMiddleware(func(ctx *DNSContext, duration time.Duration, err error) {
		metricsCalled = true
		recordedDuration = duration
		if err != nil {
			t.Errorf("expected no metrics error, got: %v", err)
		}
	})

	forwardMw := NewForwardMiddleware(res)

	p := NewPipeline(metricsMw, forwardMw)

	req := new(miekgdns.Msg)
	req.SetQuestion("example.com.", miekgdns.TypeA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 12345}, "udp")

	err := p.Execute(ctx)
	if err != nil {
		t.Fatalf("pipeline execution failed: %v", err)
	}
	if !metricsCalled {
		t.Fatalf("metrics middleware was not called")
	}
	if recordedDuration < 0 {
		t.Fatalf("recorded duration should be non-negative")
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 1 {
		t.Fatalf("expected 1 answer in ctx.Resp, got %v", ctx.Resp)
	}
}

func TestPipeline_ForwardFailureServFail(t *testing.T) {
	res := &mockResolver{
		exchangeFunc: func(ctx context.Context, req *miekgdns.Msg) (*miekgdns.Msg, error) {
			return nil, errors.New("upstream timeout")
		},
	}

	forwardMw := NewForwardMiddleware(res)
	p := NewPipeline(forwardMw)

	req := new(miekgdns.Msg)
	req.SetQuestion("fail.example.com.", miekgdns.TypeA)
	ctx := NewDNSContext(context.Background(), req, nil, "udp")

	err := p.Execute(ctx)
	if err == nil {
		t.Fatalf("expected error from forwarder, got nil")
	}
	if ctx.Resp == nil || ctx.Resp.Rcode != miekgdns.RcodeServerFailure {
		t.Fatalf("expected SERVFAIL response set on error, got: %v", ctx.Resp)
	}
}

func TestDNSContext_Methods(t *testing.T) {
	clientAddr := &net.TCPAddr{IP: net.ParseIP("192.168.1.100"), Port: 54321}
	ctx := NewDNSContext(nil, new(miekgdns.Msg), clientAddr, "tcp")

	if ctx.Protocol != "tcp" {
		t.Fatalf("expected protocol tcp, got %s", ctx.Protocol)
	}
	if ctx.ClientPort != 54321 {
		t.Fatalf("expected client port 54321, got %d", ctx.ClientPort)
	}
	if !ctx.ClientIP.Equal(net.ParseIP("192.168.1.100")) {
		t.Fatalf("expected client IP 192.168.1.100, got %s", ctx.ClientIP)
	}

	ctx.Set("tag", "test-tag")
	val, ok := ctx.Get("tag")
	if !ok || val != "test-tag" {
		t.Fatalf("expected tag attribute 'test-tag', got %v", val)
	}

	if _, ok := ctx.Get("not-found"); ok {
		t.Fatalf("expected not-found attribute to return false")
	}

	time.Sleep(5 * time.Millisecond)
	if ctx.Duration() < 4*time.Millisecond {
		t.Fatalf("expected Duration to be at least 4ms")
	}
}
