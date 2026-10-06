package core

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
)

const (
	// ModeSingle 单节点策略
	ModeSingle = "single"
	// ModePrimaryBackup 主备切换容灾策略
	ModePrimaryBackup = "primary_backup"
	// ModeParallelRace 并发竞速策略
	ModeParallelRace = "parallel_race"
)

// CanonicalMode 规整调度模式名称
func CanonicalMode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "primary_backup", "backup":
		return ModePrimaryBackup
	case "parallel_race", "race":
		return ModeParallelRace
	default:
		return ModeSingle
	}
}

// ProviderStats 记录上游提供者的健康与延迟指标
type ProviderStats struct {
	mu           sync.RWMutex
	ewmaRTT      time.Duration
	failureCount int
	lastFailure  time.Time
	lastSuccess  time.Time
	sampleCount  int64
}

const (
	defaultStatsEWMA = 50 * time.Millisecond
	statsEWMAAlpha   = 0.3
)

// NewProviderStats 创建统计对象
func NewProviderStats() *ProviderStats {
	return &ProviderStats{
		ewmaRTT: defaultStatsEWMA,
	}
}

// RecordSuccess 记录一次成功解析及耗时
func (s *ProviderStats) RecordSuccess(rtt time.Duration) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastSuccess = time.Now()
	s.failureCount = 0
	if s.sampleCount == 0 {
		s.ewmaRTT = rtt
	} else {
		s.ewmaRTT = time.Duration((1.0-statsEWMAAlpha)*float64(s.ewmaRTT) + statsEWMAAlpha*float64(rtt))
	}
	s.sampleCount++
}

// RecordFailure 记录一次解析失败
func (s *ProviderStats) RecordFailure() {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastFailure = time.Now()
	s.failureCount++
}

// Score 计算当前上游得分（延迟越低得分越优）
func (s *ProviderStats) Score() time.Duration {
	if s == nil {
		return defaultStatsEWMA
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	score := s.ewmaRTT
	if s.failureCount > 0 {
		penalty := time.Duration(s.failureCount) * 100 * time.Millisecond
		if penalty > 5*time.Second {
			penalty = 5 * time.Second
		}
		if !s.lastFailure.IsZero() && time.Since(s.lastFailure) > 30*time.Second {
			penalty /= 2
		}
		score += penalty
	}
	return score
}

// ConfiguredProvider 包装已配置的上游信息与状态
type ConfiguredProvider struct {
	ID       string
	Protocol DNSProtocol
	Server   string
	URL      string
	Stats    *ProviderStats
}

// ProviderExecutor 定义上游执行回调
type ProviderExecutor func(ctx context.Context, p *ConfiguredProvider, rawQuery []byte) ([]byte, error)

// Scheduler 调度协调器
type Scheduler struct {
	execute ProviderExecutor
}

// NewScheduler 创建调度协调器
func NewScheduler(executor ProviderExecutor) *Scheduler {
	return &Scheduler{
		execute: executor,
	}
}

// Resolve 根据模式和上游列表调度执行请求
func (s *Scheduler) Resolve(ctx context.Context, mode string, providers []*ConfiguredProvider, rawQuery []byte) ([]byte, error) {
	if len(providers) == 0 {
		return nil, fmt.Errorf("no upstream providers configured")
	}

	canon := CanonicalMode(mode)
	switch canon {
	case ModePrimaryBackup:
		return s.resolvePrimaryBackup(ctx, providers, rawQuery)
	case ModeParallelRace:
		return s.resolveParallelRace(ctx, providers, rawQuery)
	default:
		return s.resolveSingle(ctx, providers, rawQuery)
	}
}

func (s *Scheduler) resolveSingle(ctx context.Context, providers []*ConfiguredProvider, rawQuery []byte) ([]byte, error) {
	p := providers[0]
	resp, err := s.queryWithValidation(ctx, p, rawQuery)
	if err != nil {
		return nil, fmt.Errorf("upstream %s failed: %w", p.ID, err)
	}
	return resp, nil
}

func (s *Scheduler) resolvePrimaryBackup(ctx context.Context, providers []*ConfiguredProvider, rawQuery []byte) ([]byte, error) {
	var lastErr error
	for _, p := range providers {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		resp, err := s.queryWithValidation(ctx, p, rawQuery)
		if err == nil {
			return resp, nil
		}
		lastErr = err
	}
	return nil, fmt.Errorf("all %d backup providers failed, last error: %w", len(providers), lastErr)
}

type raceResult struct {
	provider *ConfiguredProvider
	response []byte
	err      error
}

func (s *Scheduler) resolveParallelRace(ctx context.Context, providers []*ConfiguredProvider, rawQuery []byte) ([]byte, error) {
	n := len(providers)
	if n == 1 {
		return s.resolveSingle(ctx, providers, rawQuery)
	}

	raceCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	resultCh := make(chan raceResult, n)
	for _, p := range providers {
		go func(prov *ConfiguredProvider) {
			resp, err := s.queryWithValidation(raceCtx, prov, rawQuery)
			resultCh <- raceResult{
				provider: prov,
				response: resp,
				err:      err,
			}
		}(p)
	}

	var lastErr error
	for i := 0; i < n; i++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case res := <-resultCh:
			if res.err == nil && res.response != nil {
				cancel()
				return res.response, nil
			}
			lastErr = res.err
		}
	}

	return nil, fmt.Errorf("all %d race providers failed, last error: %w", n, lastErr)
}

func (s *Scheduler) queryWithValidation(ctx context.Context, p *ConfiguredProvider, rawQuery []byte) ([]byte, error) {
	start := time.Now()
	resp, err := s.execute(ctx, p, rawQuery)
	elapsed := time.Since(start)

	if err != nil {
		if p.Stats != nil {
			p.Stats.RecordFailure()
		}
		return nil, err
	}

	if vErr := ValidateDNSResponse(rawQuery, resp); vErr != nil {
		if p.Stats != nil {
			p.Stats.RecordFailure()
		}
		return nil, vErr
	}

	if p.Stats != nil {
		p.Stats.RecordSuccess(elapsed)
	}
	return resp, nil
}

// ValidateDNSResponse 严格校验响应报文格式，区分业务否定应答与上游故障
func ValidateDNSResponse(rawQuery, rawResponse []byte) error {
	var query, response dns.Msg
	if err := query.Unpack(rawQuery); err != nil {
		return fmt.Errorf("invalid query packet: %w", err)
	}
	if query.Response || len(query.Question) == 0 {
		return fmt.Errorf("invalid query flags or empty question")
	}

	if err := response.Unpack(rawResponse); err != nil {
		return fmt.Errorf("invalid response packet: %w", err)
	}
	if !response.Response || response.Id != query.Id {
		return fmt.Errorf("response ID mismatch (query: %d, resp: %d)", query.Id, response.Id)
	}
	if len(response.Question) != len(query.Question) {
		return fmt.Errorf("question count mismatch")
	}

	for i := range query.Question {
		q, a := query.Question[i], response.Question[i]
		if !strings.EqualFold(q.Name, a.Name) || q.Qtype != a.Qtype || q.Qclass != a.Qclass {
			return fmt.Errorf("response question mismatch (%s != %s)", q.Name, a.Name)
		}
	}

	// NXDOMAIN 是权威有效的域名不存在判定，禁止触发容灾降级；
	// SERVFAIL、REFUSED 等错误码代表上游故障，须触发回退。
	switch response.Rcode {
	case dns.RcodeSuccess, dns.RcodeNameError:
		return nil
	default:
		return fmt.Errorf("upstream returned rcode %s (%d)", dns.RcodeToString[response.Rcode], response.Rcode)
	}
}
