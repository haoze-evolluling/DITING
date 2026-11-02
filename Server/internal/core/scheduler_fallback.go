package core

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/miekg/dns"
)

// FallbackPlan 描述一次带独立回退链的解析计划。
type FallbackPlan struct {
	// Mode 为回退链内部采用的调度模式，与主链路保持一致
	Mode string
	// Providers 为主链路的上游集合
	Providers []*ConfiguredProvider
	// FallbackProviders 为回退链路；为空表示未启用回退
	FallbackProviders []*ConfiguredProvider
	// Timeout 为主链路的独立超时；<=0 表示沿用调用方 ctx 的期限
	Timeout time.Duration
	// OnRcode 指定哪些响应码触发回退；为空时采用 DefaultFallbackRcodes
	OnRcode []int
	// OnError 决定传输层故障是否触发回退；nil 表示触发（默认行为）
	OnError *bool
}

// DefaultFallbackRcodes 返回默认触发回退的响应码。
//
// 刻意不含 NXDOMAIN：域名不存在是权威的有效判定，
// 对其回退会放大上游查询量，还可能掩盖真实的解析结果。
func DefaultFallbackRcodes() []int {
	return []int{dns.RcodeServerFailure, dns.RcodeRefused}
}

// DefaultFallbackTimeoutMs 为主链路的默认独立超时（毫秒）。
//
// 取值参考客户端普遍 5s 的解析上限：留出足够余量让回退链仍有机会作答。
const DefaultFallbackTimeoutMs = 2000

// DefaultFallbackTimeout 返回主链路的默认独立超时
func DefaultFallbackTimeout() time.Duration {
	return DefaultFallbackTimeoutMs * time.Millisecond
}

// UpstreamRcodeError 表示上游以非成功响应码作答。
//
// 与传输层故障区分开是必要的：SERVFAIL / REFUSED 属于上游自身故障，
// 是否回退由响应码列表决定；而超时、连接失败等属于链路故障，
// 由 OnError 开关决定。二者混为一谈会让策略无法独立配置。
type UpstreamRcodeError struct {
	Rcode int
}

func (e *UpstreamRcodeError) Error() string {
	name := dns.RcodeToString[e.Rcode]
	if name == "" {
		name = "UNKNOWN"
	}
	return fmt.Sprintf("upstream returned rcode %s (%d)", name, e.Rcode)
}

// resolveWithFallback 先执行主链路，失败或命中指定响应码时再执行回退链路。
//
// 语义要点：
//   - 主链路使用**独立超时**，避免慢上游吃光整条链路的预算；
//     该超时耗尽后仍会转入回退链（调用方尚未取消）。
//   - 调用方主动取消/超时不触发回退，否则用户中断一个查询会白白向备用上游再发一轮。
//   - 回退链自身不再回退，杜绝递归与查询放大。
//   - 未配置回退上游时完全不施加超时，行为与旧版逐字一致。
func (s *Scheduler) resolveWithFallback(ctx context.Context, plan FallbackPlan, rawQuery []byte) ([]byte, error) {
	if len(plan.FallbackProviders) == 0 {
		return s.Resolve(ctx, plan.Mode, plan.Providers, rawQuery)
	}

	mainCtx := ctx
	var cancel context.CancelFunc
	if plan.Timeout > 0 {
		mainCtx, cancel = context.WithTimeout(ctx, plan.Timeout)
	}

	resp, err := s.Resolve(mainCtx, plan.Mode, plan.Providers, rawQuery)
	if cancel != nil {
		cancel()
	}

	needFallback, reason := needsFallback(ctx, resp, err, plan)
	if !needFallback {
		// 不满足回退条件时原样透传主链路结果——包括错误本身。
		// 这里若吞掉 err，调用方会把失败当成"上游给出了空应答"。
		return resp, err
	}

	// 回退链使用调用方原始 ctx，不被主链路的独立超时截断
	fbResp, fbErr := s.Resolve(ctx, plan.Mode, plan.FallbackProviders, rawQuery)
	if fbErr == nil {
		return fbResp, nil
	}
	if err != nil {
		return nil, fmt.Errorf("primary chain failed (%s) and fallback chain failed: %w", reason, fbErr)
	}
	return nil, fmt.Errorf("fallback chain failed (%s): %w", reason, fbErr)
}

// needsFallback 判定是否需要转入回退链，并给出原因描述
func needsFallback(ctx context.Context, resp []byte, err error, plan FallbackPlan) (bool, string) {
	// 调用方已取消（或已超时）时不再消耗备用上游
	if ctx.Err() != nil {
		return false, "caller context done"
	}

	if err != nil {
		var rcodeErr *UpstreamRcodeError
		if errors.As(err, &rcodeErr) {
			if rcodeMatches(rcodeErr.Rcode, plan.OnRcode) {
				return true, rcodeErr.Error()
			}
			return false, ""
		}
		if plan.onErrorOrDefault() {
			return true, "transport error: " + err.Error()
		}
		return false, ""
	}

	if rcode, ok := responseRcode(resp); ok && rcodeMatches(rcode, plan.OnRcode) {
		return true, fmt.Sprintf("rcode %s", dns.RcodeToString[rcode])
	}
	return false, ""
}

// onErrorOrDefault 返回传输层故障是否触发回退
func (p FallbackPlan) onErrorOrDefault() bool {
	if p.OnError == nil {
		return true
	}
	return *p.OnError
}

// rcodeMatches 判断响应码是否在触发集合内
func rcodeMatches(rcode int, configured []int) bool {
	for _, want := range fallbackRcodes(configured) {
		if rcode == want {
			return true
		}
	}
	return false
}

// fallbackRcodes 返回生效的触发码集合。
//
// nil 与空切片语义不同，必须区分：
//   - nil 表示"用户没表态"，采用默认集合；
//   - 空切片表示"用户明确取消了所有响应码触发"，即只按传输层故障回退。
//
// 若把空切片也当作默认集合，用户在界面上取消全部勾选后回退策略会静默恢复，
// 与他表达的意图相反。
func fallbackRcodes(configured []int) []int {
	if configured == nil {
		return DefaultFallbackRcodes()
	}
	return configured
}

// responseRcode 解析响应报文中的 RCODE
func responseRcode(rawResp []byte) (int, bool) {
	if len(rawResp) < 12 {
		return 0, false
	}
	var msg dns.Msg
	if err := msg.Unpack(rawResp); err != nil {
		return 0, false
	}
	return msg.Rcode, true
}
