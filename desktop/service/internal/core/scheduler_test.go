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

func TestScheduler_SmartPrediction(t *testing.T) {
	rawQuery := makeTestDNSQuery("smart.test.com")

	p1Calls, p2Calls := 0, 0
	executor := func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		if p.ID == "fast-healthy" {
			p1Calls++
			return makeTestDNSResponse(q, dns.RcodeSuccess, "1.1.1.1"), nil
		}
		if p.ID == "slow-penalized" {
			p2Calls++
			return makeTestDNSResponse(q, dns.RcodeSuccess, "2.2.2.2"), nil
		}
		return nil, fmt.Errorf("unknown provider")
	}

	scheduler := NewScheduler(executor)

	pFast := &ConfiguredProvider{
		ID:    "fast-healthy",
		Stats: NewProviderStats(),
	}
	pSlow := &ConfiguredProvider{
		ID:    "slow-penalized",
		Stats: NewProviderStats(),
	}

	// 记录 pFast 极低延迟，pSlow 多次失败被惩罚
	pFast.Stats.RecordSuccess(10 * time.Millisecond)
	pSlow.Stats.RecordFailure()
	pSlow.Stats.RecordFailure()

	// 此时 pFast 得分显著优于 pSlow，应该优先调度 pFast
	resp, err := scheduler.Resolve(context.Background(), ModeSmartPrediction, []*ConfiguredProvider{pSlow, pFast}, rawQuery)
	if err != nil {
		t.Fatalf("smart prediction resolve failed: %v", err)
	}
	if p1Calls != 1 || p2Calls != 0 {
		t.Fatalf("expected only fast-healthy called, got pFast=%d, pSlow=%d", p1Calls, p2Calls)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil || len(respMsg.Answer) != 1 {
		t.Fatalf("unexpected smart prediction answer")
	}
}

func TestMode_ValidationAndCanonical(t *testing.T) {
	validModes := []string{
		"single", "SINGLE",
		"primary_backup", "PRIMARY_BACKUP", "backup",
		"parallel_race", "PARALLEL_RACE", "race", "fastest",
		"smart_prediction", "SMART_PREDICTION", "prediction", "smart", "load_balance", "LOAD_BALANCE",
	}
	for _, m := range validModes {
		if !IsValidMode(m) {
			t.Errorf("expected %q to be valid mode", m)
		}
	}

	invalidModes := []string{"", "invalid", "random_mode", "foo_bar"}
	for _, m := range invalidModes {
		if IsValidMode(m) {
			t.Errorf("expected %q to be invalid mode", m)
		}
	}

	if CanonicalMode("SMART_PREDICTION") != ModeSmartPrediction {
		t.Errorf("expected %s, got %s", ModeSmartPrediction, CanonicalMode("SMART_PREDICTION"))
	}
	if CanonicalMode("LOAD_BALANCE") != ModeSmartPrediction {
		t.Errorf("expected %s, got %s", ModeSmartPrediction, CanonicalMode("LOAD_BALANCE"))
	}
}

func TestScheduler_SmartPrediction_NilStatsAndWeight(t *testing.T) {
	rawQuery := makeTestDNSQuery("weight.test.com")

	executor := func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		return makeTestDNSResponse(q, dns.RcodeSuccess, "1.2.3.4"), nil
	}
	scheduler := NewScheduler(executor)

	// 1. 测试 nil stats 节点不会以 0 延迟错误击败已测得低延迟节点 (10ms)
	pFast := &ConfiguredProvider{ID: "fast", Stats: NewProviderStats(), Weight: 1}
	pFast.Stats.RecordSuccess(10 * time.Millisecond)
	pNilStats := &ConfiguredProvider{ID: "untested-nil", Stats: nil, Weight: 1}

	// 传入顺序：pNilStats 在前，pFast 在后
	candidates := []*ConfiguredProvider{pNilStats, pFast}
	// 在 smart_prediction 下，pFast 得分 (10ms) 应优于未测试的 pNilStats (默认 50ms)
	resp, err := scheduler.Resolve(context.Background(), ModeSmartPrediction, candidates, rawQuery)
	if err != nil {
		t.Fatalf("resolve failed: %v", err)
	}
	if resp == nil {
		t.Fatalf("expected response")
	}

	// 2. 测试权重加权：延迟相近时，权重高者具有更高调度优先级
	calledID := ""
	weighedExec := func(ctx context.Context, p *ConfiguredProvider, q []byte) ([]byte, error) {
		if calledID == "" {
			calledID = p.ID
		}
		return makeTestDNSResponse(q, dns.RcodeSuccess, "1.2.3.4"), nil
	}
	schedWeight := NewScheduler(weighedExec)

	pW1 := &ConfiguredProvider{ID: "weight-1", Stats: NewProviderStats(), Weight: 1}
	pW1.Stats.RecordSuccess(20 * time.Millisecond) // 加权得分 20ms

	pW3 := &ConfiguredProvider{ID: "weight-3", Stats: NewProviderStats(), Weight: 3}
	pW3.Stats.RecordSuccess(20 * time.Millisecond) // 加权得分 20ms / 3 ≈ 6.6ms

	// 将 pW1 排在前，pW3 排在后
	_, err = schedWeight.Resolve(context.Background(), ModeSmartPrediction, []*ConfiguredProvider{pW1, pW3}, rawQuery)
	if err != nil {
		t.Fatalf("resolve failed: %v", err)
	}
	if calledID != "weight-3" {
		t.Fatalf("expected high-weight provider weight-3 to be selected first, got %s", calledID)
	}
}

func TestProtocol_Validation(t *testing.T) {
	valid := []string{"PLAIN", "plain", "UDP", "udp", "TCP", "tcp", "DOH", "doh", "HTTPS", "https", "DOT", "dot", "TLS", "tls", ""}
	for _, p := range valid {
		if !IsValidProtocol(p) {
			t.Errorf("expected protocol %q to be valid", p)
		}
	}

	invalid := []string{"FTP", "invalid", "DHO", "HTTP", "ws"}
	for _, p := range invalid {
		if IsValidProtocol(p) {
			t.Errorf("expected protocol %q to be invalid", p)
		}
	}
}

