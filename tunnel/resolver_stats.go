package tunnel

import (
	"sync"
	"time"
)

// providerStats tracks dynamic latency metrics and health for smart prediction.
type providerStats struct {
	mu           sync.RWMutex
	ewmaRTT      time.Duration
	failureCount int
	lastFailure  time.Time
	lastSuccess  time.Time
	sampleCount  int64
}

const (
	defaultEWMA = 50 * time.Millisecond
	ewmaAlpha   = 0.3
)

func newProviderStats() *providerStats {
	return &providerStats{
		ewmaRTT: defaultEWMA,
	}
}

func (s *providerStats) RecordSuccess(rtt time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastSuccess = time.Now()
	s.failureCount = 0
	if s.sampleCount == 0 {
		s.ewmaRTT = rtt
	} else {
		s.ewmaRTT = time.Duration((1.0-ewmaAlpha)*float64(s.ewmaRTT) + ewmaAlpha*float64(rtt))
	}
	s.sampleCount++
}

func (s *providerStats) RecordFailure() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastFailure = time.Now()
	s.failureCount++
}

func (s *providerStats) Score() time.Duration {
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
