package tunnel

import (
	"encoding/json"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

// TrafficCallback is the gomobile-compatible callback interface for receiving periodic traffic delta statistics in Kotlin.
type TrafficCallback interface {
	OnTrafficStatsTick(jsonDeltas string)
}

type uidTrafficCounters struct {
	txDelta atomic.Uint64
	rxDelta atomic.Uint64
	txTotal atomic.Uint64
	rxTotal atomic.Uint64
}

// TrafficTracker provides lock-free streaming traffic accounting per Android UID.
type TrafficTracker struct {
	mu           sync.RWMutex
	uids         map[int]*uidTrafficCounters
	callback     TrafficCallback
	stopChan     chan struct{}
	wakeChan     chan struct{}
	running      atomic.Bool
	tickInterval atomic.Int64 // nanoseconds
}

// defaultTickInterval is the 1s heartbeat used while the screen is on.
// Kotlin lowers it when the screen turns off (screen-state driven
// SetTickIntervalMs) so an idle device stops per-second wakeups and the
// SoC can reach its deepest idle states.
const defaultTickInterval = 1 * time.Second

func newTrafficTracker() *TrafficTracker {
	t := &TrafficTracker{
		uids:     make(map[int]*uidTrafficCounters),
		wakeChan: make(chan struct{}, 1),
	}
	t.tickInterval.Store(int64(defaultTickInterval))
	return t
}

// SetTickInterval adjusts the periodic tick interval. Safe to call at any
// time (before or after Start); takes effect on the pending timer
// immediately. Deltas accumulated in the per-UID atomics are never lost by
// interval changes — the next tick flushes them (aggregated).
func (t *TrafficTracker) SetTickInterval(d time.Duration) {
	if t == nil || d <= 0 {
		return
	}
	t.tickInterval.Store(int64(d))
	select {
	case t.wakeChan <- struct{}{}:
	default:
	}
}

func (t *TrafficTracker) SetCallback(cb TrafficCallback) {
	if t == nil {
		return
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	t.callback = cb
}

func (t *TrafficTracker) getOrCreateCounters(uid int) *uidTrafficCounters {
	t.mu.RLock()
	c, ok := t.uids[uid]
	t.mu.RUnlock()
	if ok {
		return c
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	if c, ok = t.uids[uid]; ok {
		return c
	}
	c = &uidTrafficCounters{}
	t.uids[uid] = c
	return c
}

func (t *TrafficTracker) RecordTx(uid int, n int64) {
	if t == nil || n <= 0 || uid <= 0 {
		return
	}
	c := t.getOrCreateCounters(uid)
	c.txDelta.Add(uint64(n))
	c.txTotal.Add(uint64(n))
}

func (t *TrafficTracker) RecordRx(uid int, n int64) {
	if t == nil || n <= 0 || uid <= 0 {
		return
	}
	c := t.getOrCreateCounters(uid)
	c.rxDelta.Add(uint64(n))
	c.rxTotal.Add(uint64(n))
}

type countingConn struct {
	net.Conn
	tracker *TrafficTracker
	uid     int
}

func (c *countingConn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	if n > 0 && c.tracker != nil {
		c.tracker.RecordTx(c.uid, int64(n))
	}
	return n, err
}

func (c *countingConn) Write(b []byte) (int, error) {
	n, err := c.Conn.Write(b)
	if n > 0 && c.tracker != nil {
		c.tracker.RecordRx(c.uid, int64(n))
	}
	return n, err
}

func (t *TrafficTracker) WrapClientConn(conn net.Conn, uid int) net.Conn {
	if t == nil || conn == nil || uid <= 0 {
		return conn
	}
	return &countingConn{
		Conn:    conn,
		tracker: t,
		uid:     uid,
	}
}

type uidDeltaJson struct {
	UID int    `json:"uid"`
	Tx  uint64 `json:"tx"`
	Rx  uint64 `json:"rx"`
}

func (t *TrafficTracker) Start() {
	if t == nil || t.running.Swap(true) {
		return
	}
	t.stopChan = make(chan struct{})
	// Capture the channel locally: re-reading the t.stopChan field on every
	// select would let a stale goroutine (mid-tick during a Stop→Start
	// handoff) attach to the NEW channel and leak until the next Stop.
	stop := t.stopChan

	go func() {
		timer := time.NewTimer(time.Duration(t.tickInterval.Load()))
		defer timer.Stop()
		for {
			select {
			case <-timer.C:
				t.tick()
				timer.Reset(time.Duration(t.tickInterval.Load()))
			case <-t.wakeChan:
				// Interval changed: reset the pending timer so the new
				// cadence applies immediately (shorter AND longer).
				if !timer.Stop() {
					select {
					case <-timer.C:
					default:
					}
				}
				timer.Reset(time.Duration(t.tickInterval.Load()))
			case <-stop:
				return
			}
		}
	}()
}

func (t *TrafficTracker) Stop() {
	if t == nil || !t.running.Swap(false) {
		return
	}
	// Closing stopChan ends the timer goroutine; the final tick() flushes
	// whatever deltas accumulated since the last periodic tick, so totals
	// are conserved regardless of the current interval.
	close(t.stopChan)
	t.tick()
}

func (t *TrafficTracker) tick() {
	t.mu.RLock()
	cb := t.callback
	keys := make([]int, 0, len(t.uids))
	for k := range t.uids {
		keys = append(keys, k)
	}
	t.mu.RUnlock()

	if cb == nil || len(keys) == 0 {
		return
	}

	var deltas []uidDeltaJson
	for _, uid := range keys {
		c := t.getOrCreateCounters(uid)
		tx := c.txDelta.Swap(0)
		rx := c.rxDelta.Swap(0)
		if tx > 0 || rx > 0 {
			deltas = append(deltas, uidDeltaJson{
				UID: uid,
				Tx:  tx,
				Rx:  rx,
			})
		}
	}

	if len(deltas) > 0 {
		if data, err := json.Marshal(deltas); err == nil {
			cb.OnTrafficStatsTick(string(data))
		}
	}
}
