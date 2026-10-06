package dns

import (
	"fmt"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/miekg/dns"
)

// MetricsCallback 指标与耗时记录回调接口
type MetricsCallback func(ctx *DNSContext, duration time.Duration, err error)

// NewForwardMiddleware 创建默认上游转发处理器中间件
func NewForwardMiddleware(resolver core.Resolver) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if ctx.Req == nil {
			err := fmt.Errorf("empty request in DNSContext")
			ctx.Err = err
			return err
		}

		resp, err := resolver.Exchange(ctx.Context, ctx.Req)
		if err != nil {
			ctx.Err = err
			// 向上游转发失败时，构造通用 SERVFAIL 响应防止客户端挂起
			failMsg := new(dns.Msg)
			failMsg.SetRcode(ctx.Req, dns.RcodeServerFailure)
			failMsg.RecursionAvailable = true
			ctx.Resp = failMsg
			_ = next() // 允许后置中间件（如统计、审计）继续捕获失败事件
			return err
		}

		ctx.Resp = resp
		return next()
	}
}

// NewMetricsMiddleware 创建耗时与请求指标统计中间件
func NewMetricsMiddleware(callback MetricsCallback) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		start := time.Now()
		err := next()
		duration := time.Since(start)

		if callback != nil {
			callback(ctx, duration, err)
		}
		return err
	}
}
