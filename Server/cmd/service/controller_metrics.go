package main

import (
	"time"

	ditingdns "github.com/haoze-evolluling/diting/server/internal/dns"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
	"github.com/haoze-evolluling/diting/server/internal/querylog"
	miekgdns "github.com/miekg/dns"
)

// newMetricsMiddleware 构造 DNS 热路径的指标采集中间件。
//
// 该回调同时承担三件事：更新运行时指标、写入查询日志、向 IPC 广播实时查询事件。
// 由于位于每个查询的关键路径上，内部不再获取 p.mu（所需引用由此处提前捕获）。
func (p *program) newMetricsMiddleware() ditingdns.Middleware {
	// 提前捕获引用：查询日志记录位于 DNS 热路径，回调内不得再取 p.mu
	ql := p.queryLog
	metrics := p.metrics

	return ditingdns.NewMetricsMiddleware(func(dctx *ditingdns.DNSContext, duration time.Duration, err error) {
		qName := ""
		qType := ""
		if dctx.Req != nil && len(dctx.Req.Question) > 0 {
			qName = dctx.Req.Question[0].Name
			qType = miekgdns.TypeToString[dctx.Req.Question[0].Qtype]
		}
		success := (err == nil)
		metrics.RecordQuery(duration, success)

		cacheHitStr := ""
		if val, ok := dctx.Get("cache_hit"); ok {
			if s, ok := val.(string); ok {
				cacheHitStr = s
			}
		}
		rcodeStr := ""
		if dctx.Resp != nil {
			rcodeStr = miekgdns.RcodeToString[dctx.Resp.Rcode]
		}

		filterBlocked := false
		filterRule := ""
		filterReason := ""
		if val, ok := dctx.Get("filter_blocked"); ok {
			if b, ok := val.(bool); ok {
				filterBlocked = b
			}
		}
		if val, ok := dctx.Get("rebinding_blocked"); ok {
			if b, ok := val.(bool); ok && b {
				filterBlocked = true
				if filterRule == "" {
					filterRule = "REBIND_PROTECTION"
				}
			}
		}
		if val, ok := dctx.Get("access_blocked"); ok {
			if b, ok := val.(bool); ok && b {
				filterBlocked = true
				if filterRule == "" {
					filterRule = "CLIENT_ACCESS_CONTROL"
				}
			}
		}
		if val, ok := dctx.Get("ratelimit_blocked"); ok {
			if b, ok := val.(bool); ok && b {
				filterBlocked = true
				if filterRule == "" {
					filterRule = "RATE_LIMIT_EXCEEDED"
				}
			}
		}
		if val, ok := dctx.Get("unqualified_blocked"); ok {
			if b, ok := val.(bool); ok && b {
				filterBlocked = true
				if filterRule == "" {
					filterRule = "BLOCK_UNQUALIFIED"
				}
			}
		}
		if val, ok := dctx.Get("filter_rule"); ok {
			if s, ok := val.(string); ok {
				filterRule = s
			}
		}
		if val, ok := dctx.Get("filter_reason"); ok {
			if s, ok := val.(string); ok {
				filterReason = s
			}
		}

		// 查询历史与统计收集：复用本回调已算好的字段，无需新增中间件
		if ql != nil {
			errStr := ""
			if err != nil {
				errStr = err.Error()
			}
			status := querylog.StatusAllowed
			switch {
			case err != nil:
				status = querylog.StatusError
			case filterBlocked:
				status = querylog.StatusBlocked
			case cacheHitStr == "stale":
				status = querylog.StatusStale
			case cacheHitStr != "":
				status = querylog.StatusCached
			}
			ql.Record(querylog.Record{
				Timestamp:    time.Now().UnixMilli(),
				Domain:       qName,
				QType:        qType,
				ClientIP:     formatIP(dctx.ClientIP),
				ClientName:   dctx.ClientName,
				DurationMs:   float64(duration.Nanoseconds()) / 1e6,
				RCode:        rcodeStr,
				Status:       status,
				Cached:       cacheHitStr != "",
				CacheHit:     cacheHitStr,
				Blocked:      filterBlocked,
				FilterRule:   filterRule,
				FilterReason: filterReason,
				Protocol:     dctx.Protocol,
				Error:        errStr,
			})
		}

		if srv := p.currentIPCServer(); srv != nil {
			errStr := ""
			if err != nil {
				errStr = err.Error()
			}
			srv.Broadcast(ipc.Event{
				Type:      "query",
				Timestamp: time.Now().UnixMilli(),
				Data: ipc.QueryEventData{
					Domain:       qName,
					QType:        qType,
					ClientIP:     formatIP(dctx.ClientIP),
					ClientName:   dctx.ClientName,
					DurationMs:   float64(duration.Nanoseconds()) / 1e6,
					Success:      success,
					RCode:        rcodeStr,
					CacheHit:     cacheHitStr,
					Blocked:      filterBlocked,
					FilterRule:   filterRule,
					FilterReason: filterReason,
					ErrorMessage: errStr,
				},
			})
		}
	})
}
