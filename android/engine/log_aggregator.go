// log_aggregator.go provides a high-throughput, non-blocking batch aggregator for DNS and connection logs.
//
// Flow Control & Load Shedding:
// - Tier 1 (High-water mark > 75% capacity): Proactively sheds low-priority connection logs to preserve capacity for critical DNS queries.
// - Tier 2 (100% capacity): Drops incoming items silently to ensure TUN packet processing and DNS resolution are never blocked.
// - Background Flush: Buffers events and flushes to the Kotlin BatchLogCallback based on batch size thresholds or periodic timer ticks.

package tunnel

import (
	"encoding/json"
	"sync"
	"sync/atomic"
	"time"
)

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
	// No omitempty: the Kotlin cache treats a missing key as "TTL unknown" and a
	// present 0 as "upstream said do not cache". Omitting zero made every
	// zero-TTL answer look unknown and get persisted with the policy maximum.
	TTL int64 `json:"ttl"`
}

const (
	logBufferSize    = 2048
	logHighWaterMark = (logBufferSize * 3) / 4
	logBatchSize     = 50
	logFlushInterval = 100 * time.Millisecond
)

type logAggregator struct {
	mu              sync.RWMutex
	ch              chan logItem
	callback        BatchLogCallback
	stopChan        chan struct{}
	running         atomic.Bool
	droppedLogs     atomic.Uint64
	droppedConnLogs atomic.Uint64
}

func newLogAggregator() *logAggregator {
	return &logAggregator{
		ch: make(chan logItem, logBufferSize),
	}
}

func (a *logAggregator) setCallback(cb BatchLogCallback) {
	if a == nil {
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	a.callback = cb
}

func (a *logAggregator) hasCallback() bool {
	if a == nil {
		return false
	}
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.callback != nil
}

func (a *logAggregator) push(item logItem) {
	if a == nil {
		return
	}

	if !item.Blocked && item.BlockedBy == "connection" && len(a.ch) >= logHighWaterMark {
		a.droppedConnLogs.Add(1)
		a.droppedLogs.Add(1)
		return
	}

	select {
	case a.ch <- item:
	default:
		a.droppedLogs.Add(1)
	}
}

func (a *logAggregator) droppedCount() uint64 {
	if a == nil {
		return 0
	}
	return a.droppedLogs.Load()
}

func (a *logAggregator) start() {
	if a == nil || a.running.Swap(true) {
		return
	}
	a.stopChan = make(chan struct{})
	stop := a.stopChan

	go func() {
		// The flush timer is armed only while a partial batch is pending. A free
		// running 100ms ticker woke the CPU ten times a second even when the
		// tunnel was idle (screen off), which defeats deep-sleep states.
		timer := time.NewTimer(logFlushInterval)
		if !timer.Stop() {
			<-timer.C
		}
		timerArmed := false
		defer timer.Stop()

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
				} else if !timerArmed {
					timer.Reset(logFlushInterval)
					timerArmed = true
				}
			case <-timer.C:
				timerArmed = false
				flush()
			case <-stop:

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

func (a *logAggregator) stop() {
	if a == nil || !a.running.Swap(false) {
		return
	}
	close(a.stopChan)
}
