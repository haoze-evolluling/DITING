package core

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func makeTestDNSResponse(queryBytes []byte, rcode int, ip string) []byte {
	var q dns.Msg
	_ = q.Unpack(queryBytes)

	resp := new(dns.Msg)
	resp.SetReply(&q)
	resp.Rcode = rcode
	if ip != "" && rcode == dns.RcodeSuccess {
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A %s", q.Question[0].Name, ip))
		resp.Answer = append(resp.Answer, rr)
	}
	b, _ := resp.Pack()
	return b
}

func TestScheduler_SingleMode(t *testing.T) {
	rawQuery := makeTestDNSQuery("single.test.com")

	called := 0
	executor := func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		called++
		return makeTestDNSResponse(q, dns.RcodeSuccess, "1.2.3.4"), nil
	}

	scheduler := NewScheduler(executor)
	providers := []*ConfiguredProvider{
		{ID: "p1", Stats: NewProviderStats()},
	}

	resp, err := scheduler.Resolve(context.Background(), ModeSingle, providers, rawQuery)
	if err != nil {
		t.Fatalf("single resolve failed: %v", err)
	}
	if called != 1 {
		t.Fatalf("expected 1 call, got %d", called)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil || len(respMsg.Answer) != 1 {
		t.Fatalf("unexpected response msg")
	}
}

func TestScheduler_PrimaryBackup(t *testing.T) {
	rawQuery := makeTestDNSQuery("backup.test.com")

	p1Calls, p2Calls := 0, 0
	executor := func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		if p.ID == "p1" {
			p1Calls++
			// 主提供者返回 SERVFAIL (上游故障)
			return makeTestDNSResponse(q, dns.RcodeServerFailure, ""), nil
		}
		if p.ID == "p2" {
			p2Calls++
			// 备提供者正常返回
			return makeTestDNSResponse(q, dns.RcodeSuccess, "9.9.9.9"), nil
		}
		return nil, fmt.Errorf("unknown provider")
	}

	scheduler := NewScheduler(executor)
	providers := []*ConfiguredProvider{
		{ID: "p1", Stats: NewProviderStats()},
		{ID: "p2", Stats: NewProviderStats()},
	}

	resp, err := scheduler.Resolve(context.Background(), ModePrimaryBackup, providers, rawQuery)
	if err != nil {
		t.Fatalf("backup fallback resolve failed: %v", err)
	}
	if p1Calls != 1 || p2Calls != 1 {
		t.Fatalf("expected both p1 and p2 called, got p1=%d, p2=%d", p1Calls, p2Calls)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil || len(respMsg.Answer) != 1 {
		t.Fatalf("unexpected backup answer")
	}
}

func TestScheduler_PrimaryBackupNXDomain(t *testing.T) {
	rawQuery := makeTestDNSQuery("nxdomain.test.com")

	p1Calls, p2Calls := 0, 0
	executor := func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		if p.ID == "p1" {
			p1Calls++
			// 主提供者返回 NXDOMAIN (权威域名不存在，为业务有效判定，禁止降级)
			return makeTestDNSResponse(q, dns.RcodeNameError, ""), nil
		}
		p2Calls++
		return makeTestDNSResponse(q, dns.RcodeSuccess, "9.9.9.9"), nil
	}

	scheduler := NewScheduler(executor)
	providers := []*ConfiguredProvider{
		{ID: "p1", Stats: NewProviderStats()},
		{ID: "p2", Stats: NewProviderStats()},
	}

	resp, err := scheduler.Resolve(context.Background(), ModePrimaryBackup, providers, rawQuery)
	if err != nil {
		t.Fatalf("expected NXDOMAIN passthrough without error, got: %v", err)
	}
	if p1Calls != 1 || p2Calls != 0 {
		t.Fatalf("NXDOMAIN must NOT trigger fallback! p1=%d, p2=%d", p1Calls, p2Calls)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil || respMsg.Rcode != dns.RcodeNameError {
		t.Fatalf("expected NXDOMAIN rcode in response, got %d", respMsg.Rcode)
	}
}

func TestScheduler_ParallelRace(t *testing.T) {
	rawQuery := makeTestDNSQuery("race.test.com")

	executor := func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		if p.ID == "slow" {
			select {
			case <-time.After(150 * time.Millisecond):
				return makeTestDNSResponse(q, dns.RcodeSuccess, "1.1.1.1"), nil
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		// fast
		time.Sleep(10 * time.Millisecond)
		return makeTestDNSResponse(q, dns.RcodeSuccess, "2.2.2.2"), nil
	}

	scheduler := NewScheduler(executor)
	providers := []*ConfiguredProvider{
		{ID: "slow", Stats: NewProviderStats()},
		{ID: "fast", Stats: NewProviderStats()},
	}

	start := time.Now()
	resp, err := scheduler.Resolve(context.Background(), ModeParallelRace, providers, rawQuery)
	elapsed := time.Since(start)

	if err != nil {
		t.Fatalf("parallel race resolve failed: %v", err)
	}
	if elapsed >= 100*time.Millisecond {
		t.Fatalf("expected fast response around 10ms, took %v", elapsed)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil || len(respMsg.Answer) != 1 {
		t.Fatalf("unexpected race answer")
	}
	if a, ok := respMsg.Answer[0].(*dns.A); !ok || a.A.String() != "2.2.2.2" {
		t.Fatalf("expected answer from fast provider (2.2.2.2), got %v", respMsg.Answer[0])
	}
}

func TestValidateDNSResponse(t *testing.T) {
	rawQuery := makeTestDNSQuery("valid.test.com")

	// 正常响应
	validResp := makeTestDNSResponse(rawQuery, dns.RcodeSuccess, "1.2.3.4")
	if err := ValidateDNSResponse(rawQuery, validResp); err != nil {
		t.Fatalf("expected valid response to pass, got: %v", err)
	}

	// ID 不匹配响应
	var badIDMsg dns.Msg
	_ = badIDMsg.Unpack(validResp)
	badIDMsg.Id = 9999
	badIDBytes, _ := badIDMsg.Pack()
	if err := ValidateDNSResponse(rawQuery, badIDBytes); err == nil {
		t.Fatalf("expected error on ID mismatch, got nil")
	}

	// 响应标志未置位
	var notRespMsg dns.Msg
	_ = notRespMsg.Unpack(validResp)
	notRespMsg.Response = false
	notRespBytes, _ := notRespMsg.Pack()
	if err := ValidateDNSResponse(rawQuery, notRespBytes); err == nil {
		t.Fatalf("expected error when Response flag is false")
	}

	// 损坏字节
	if err := ValidateDNSResponse(rawQuery, []byte{1, 2, 3}); err == nil {
		t.Fatalf("expected error on corrupt response bytes")
	}
}

func TestProviderStats_Score(t *testing.T) {
	stats := NewProviderStats()
	if stats.Score() != defaultStatsEWMA {
		t.Fatalf("expected default score %v, got %v", defaultStatsEWMA, stats.Score())
	}

	stats.RecordSuccess(20 * time.Millisecond)
	stats.RecordFailure()
	stats.RecordFailure()
	if stats.failureCount != 2 {
		t.Fatalf("expected 2 failures, got %d", stats.failureCount)
	}
	if stats.Score() <= 20*time.Millisecond {
		t.Fatalf("expected penalty in score")
	}

	stats.RecordSuccess(10 * time.Millisecond)
	if stats.failureCount != 0 {
		t.Fatalf("expected failures reset after success")
	}
}

func TestValidateDNSResponse_DoH_ZeroID(t *testing.T) {
	rawQuery := makeTestDNSQuery("doh-zero.test.com")
	validResp := makeTestDNSResponse(rawQuery, dns.RcodeSuccess, "1.2.3.4")

	// Upstream DoH responds with ID = 0 per RFC 8484
	var zeroIDMsg dns.Msg
	_ = zeroIDMsg.Unpack(validResp)
	zeroIDMsg.Id = 0
	zeroIDBytes, _ := zeroIDMsg.Pack()

	if err := ValidateDNSResponse(rawQuery, zeroIDBytes); err != nil {
		t.Fatalf("expected DoH response with ID 0 to be accepted, got: %v", err)
	}
}

func TestScheduler_ParallelRace_ContextCanceledNoPenalty(t *testing.T) {
	pFast := &ConfiguredProvider{
		ID:       "fast",
		Protocol: ProtocolPlain,
		Stats:    NewProviderStats(),
	}
	pSlow := &ConfiguredProvider{
		ID:       "slow",
		Protocol: ProtocolPlain,
		Stats:    NewProviderStats(),
	}

	rawQuery := makeTestDNSQuery("race-penalty.test.com")
	fastResp := makeTestDNSResponse(rawQuery, dns.RcodeSuccess, "1.1.1.1")

	sched := NewScheduler(func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		if p.ID == "fast" {
			return fastResp, nil
		}
		// 慢速 provider 等待 context cancel
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(500 * time.Millisecond):
			return fastResp, nil
		}
	})

	resp, err := sched.Resolve(context.Background(), ModeParallelRace, []*ConfiguredProvider{pFast, pSlow}, rawQuery)
	if err != nil || resp == nil {
		t.Fatalf("expected race to succeed: %v", err)
	}

	time.Sleep(20 * time.Millisecond) // 等待慢速协程退出并处理结果

	if pSlow.Stats.failureCount != 0 {
		t.Fatalf("expected canceled provider to not have failure recorded, got: %d", pSlow.Stats.failureCount)
	}
}
