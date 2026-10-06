package main

import (
	"sync/atomic"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/ipc"
)

// metricsTracker 线程安全地收集与计算 DNS 运行时性能指标
type metricsTracker struct {
	startTime      time.Time
	totalQueries   atomic.Uint64
	successQueries atomic.Uint64
	failedQueries  atomic.Uint64
	totalLatencyNs atomic.Uint64
}

func newMetricsTracker() *metricsTracker {
	return &metricsTracker{
		startTime: time.Now(),
	}
}

// RecordQuery 记录单次 DNS 请求的耗时与状态
func (m *metricsTracker) RecordQuery(duration time.Duration, success bool) {
	m.totalQueries.Add(1)
	if success {
		m.successQueries.Add(1)
	} else {
		m.failedQueries.Add(1)
	}
	m.totalLatencyNs.Add(uint64(duration.Nanoseconds()))
}

// Snapshot 生成当前性能统计快照
func (m *metricsTracker) Snapshot() ipc.MetricsStatus {
	total := m.totalQueries.Load()
	success := m.successQueries.Load()
	failed := m.failedQueries.Load()
	totalNs := m.totalLatencyNs.Load()

	var avgLatencyMs float64
	if total > 0 {
		avgLatencyMs = float64(totalNs) / float64(total) / 1e6
	}

	uptime := time.Since(m.startTime).Seconds()
	var qps float64
	if uptime > 0 {
		qps = float64(total) / uptime
	}

	return ipc.MetricsStatus{
		TotalQueries:   total,
		SuccessQueries: success,
		FailedQueries:  failed,
		AvgLatencyMs:   avgLatencyMs,
		QPS:            qps,
	}
}
