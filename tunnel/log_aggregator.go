package tunnel

import (
	"encoding/json"
	"sync"
	"sync/atomic"
	"time"
)

// logItem represents an individual DNS or connection event for batch reporting.
type logItem struct {
	Domain         string `json:"d"`
	Blocked        bool   `json:"b"`
	QueryType      int    `json:"t"`
	ResponseTimeMs int64  `json:"r"`
	AppName        string `json:"a"`
	ResolvedIPs    string `json:"i"`
	BlockedBy      string `json:"k"`
	ErrorMessage   string `json:"e"`
	Cached         bool   `json:"c"`
	Timestamp      int64  `json:"ts"`
}

const (
	logBufferSize    = 2048
	logHighWaterMark = (logBufferSize * 3) / 4 // 1536: early drop threshold for connection logs
	logBatchSize     = 50
	logFlushInterval = 100 * time.Millisecond
)

// logAggregator aggregates individual log events into batches to reduce cross-layer JNI overhead.
type logAggregator struct {
	mu             sync.RWMutex
	ch             chan logItem
	callback       BatchLogCallback
	stopChan       chan struct{}
	running        atomic.Bool
	droppedLogs    atomic.Uint64
	droppedConnLogs atomic.Uint64
}

func newLogAggregator() *logAggregator {
	return &logAggregator{
		ch: make(chan logItem, logBufferSize),
	}
}

// setCallback sets the Kotlin batch log callback receiver.
func (a *logAggregator) setCallback(cb BatchLogCallback) {
	if a == nil {
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	a.callback = cb
}

// hasCallback returns whether a batch callback is currently registered.
func (a *logAggregator) hasCallback() bool {
	if a == nil {
		return false
	}
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.callback != nil
}

// push adds an item to the aggregator channel non-blockingly with tiered backpressure protection:
// 1. High-water mark (> 75% capacity): low-priority connection logs (blockedBy == "connection")
//    are proactively dropped to safeguard capacity for critical DNS query logs.
// 2. Buffer full (100% capacity): all log items are dropped silently without blocking the caller.
// TUN data forwarding and DNS queries are never delayed or deadlocked.
func (a *logAggregator) push(item logItem) {
	if a == nil {
		return
	}

	// Tier 1: Proactive load-shedding of low-priority connection logs
	if item.BlockedBy == "connection" && len(a.ch) >= logHighWaterMark {
		a.droppedConnLogs.Add(1)
		a.droppedLogs.Add(1)
		return
	}

	// Tier 2: Non-blocking write with silent drop on overflow
	select {
	case a.ch <- item:
	default:
		a.droppedLogs.Add(1)
	}
}

// droppedCount returns total dropped log events due to buffer congestion/overflow.
func (a *logAggregator) droppedCount() uint64 {
	if a == nil {
		return 0
	}
	return a.droppedLogs.Load()
}

// droppedConnCount returns low-priority connection logs dropped by proactive backpressure.
func (a *logAggregator) droppedConnCount() uint64 {
	if a == nil {
		return 0
	}
	return a.droppedConnLogs.Load()
}

// start begins the background batching goroutine.
func (a *logAggregator) start() {
	if a == nil || a.running.Swap(true) {
		return
	}
	a.stopChan = make(chan struct{})
	stop := a.stopChan

	go func() {
		ticker := time.NewTicker(logFlushInterval)
		defer ticker.Stop()

		batch := make([]logItem, 0, logBatchSize)

		flush := func() {
			if len(batch) == 0 {
				return
			}
			a.mu.RLock()
			cb := a.callback
			a.mu.RUnlock()
			if cb != nil {
				if data, err := json.Marshal(batch); err == nil {
					cb.OnDNSQueryBatch(string(data))
				}
			}
			batch = batch[:0]
		}

		for {
			select {
			case item := <-a.ch:
				batch = append(batch, item)
				if len(batch) >= logBatchSize {
					flush()
				}
			case <-ticker.C:
				if len(batch) > 0 {
					flush()
				}
			case <-stop:
				// Drain any remaining items on stop
				for {
					select {
					case item := <-a.ch:
						batch = append(batch, item)
						if len(batch) >= logBatchSize {
							flush()
						}
					default:
						if len(batch) > 0 {
							flush()
						}
						return
					}
				}
			}
		}
	}()
}

// stop stops the background batching goroutine and flushes pending items.
func (a *logAggregator) stop() {
	if a == nil || !a.running.Swap(false) {
		return
	}
	close(a.stopChan)
}
