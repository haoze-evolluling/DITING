package core

import (
	"fmt"
	"math"
	"sync"
	"time"
)

const (
	bsDefaultLatencyMs         = 250.0
	bsMinLatencyMs             = 20.0
	bsMaxLatencyMs             = 5000.0
	bsMinWeight                = 0.05
	bsMaxWeight                = 3.0
	bsJitterWeight             = 0.5
	bsCooldownPenalty          = 0.1
	bsConsecutiveFailPenalty   = 0.2
	bsEwmaAlpha                = 0.25
	bsJitterAlpha              = 0.20
	bsBaseExplorationRate      = 0.02
	bsLowSampleExplorationRate = 0.08
	bsRecoveryExplorationRate  = 0.10
	bsLowSampleThreshold       = 10.0
	bsCooldownFailureThreshold = 3
	bsCooldownDuration         = 30 * time.Second
	bsHealthHalfLifeDuration   = 30 * time.Minute
	bsDefaultCacheTTL          = 60 * time.Second
)

type bootstrapHealth struct {
	mu                  sync.RWMutex
	successes           int
	failures            int
	ewmaMs              float64
	jitterMs            float64
	consecutiveFailures int
	cooldownUntil       time.Time
	decayedSuccesses    float64
	decayedFailures     float64
	lastUpdatedAt       time.Time
}

func newBootstrapHealth() *bootstrapHealth {
	return &bootstrapHealth{
		ewmaMs:        bsDefaultLatencyMs,
		lastUpdatedAt: time.Now(),
	}
}

func (h *bootstrapHealth) applyDecayLocked(now time.Time) {
	if h.lastUpdatedAt.IsZero() {
		h.lastUpdatedAt = now
		return
	}
	elapsed := now.Sub(h.lastUpdatedAt)
	if elapsed <= 0 {
		return
	}
	factor := math.Pow(0.5, float64(elapsed)/float64(bsHealthHalfLifeDuration))
	h.decayedSuccesses *= factor
	h.decayedFailures *= factor
	h.lastUpdatedAt = now
}

func (h *bootstrapHealth) RecordResult(success bool, elapsedMs int64, now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.applyDecayLocked(now)

	safeElapsed := float64(elapsedMs)
	if safeElapsed < 1.0 {
		safeElapsed = 1.0
	}

	if success {
		h.successes++
		h.decayedSuccesses += 1.0
		h.consecutiveFailures = 0
		h.cooldownUntil = time.Time{}

		h.ewmaMs = h.ewmaMs*(1.0-bsEwmaAlpha) + safeElapsed*bsEwmaAlpha
		h.jitterMs = h.jitterMs*(1.0-bsJitterAlpha) + math.Abs(safeElapsed-h.ewmaMs)*bsJitterAlpha
	} else {
		h.failures++
		h.decayedFailures += 1.0
		h.consecutiveFailures++
		if h.consecutiveFailures >= bsCooldownFailureThreshold {
			h.cooldownUntil = now.Add(bsCooldownDuration)
		}
	}
	h.lastUpdatedAt = now
}

type bootstrapScore struct {
	index       int
	entry       BootstrapServer
	weight      float64
	coolingDown bool
	sampleCount float64
}

func serverKey(s BootstrapServer, idx int) string {
	if s.ID != "" {
		return s.ID
	}
	if s.Address != "" {
		return s.Address
	}
	return fmt.Sprintf("server-%d", idx)
}

func (h *bootstrapHealth) GetScore(entry BootstrapServer, now time.Time) bootstrapScore {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.applyDecayLocked(now)

	decayedAttempts := h.decayedSuccesses + h.decayedFailures
	coolingDown := !h.cooldownUntil.IsZero() && now.Before(h.cooldownUntil)

	if decayedAttempts <= 0 {
		initialWeight := entry.Weight
		if initialWeight <= 0 {
			initialWeight = 1.0
		}
		return bootstrapScore{
			entry:       entry,
			weight:      initialWeight,
			coolingDown: coolingDown,
			sampleCount: 0,
		}
	}

	correctness := (h.decayedSuccesses + 2.0) / (decayedAttempts + 3.0)

	speed := 1.0
	if h.successes > 0 {
		effectiveLatency := h.ewmaMs + h.jitterMs*bsJitterWeight
		if effectiveLatency < bsMinLatencyMs {
			effectiveLatency = bsMinLatencyMs
		} else if effectiveLatency > bsMaxLatencyMs {
			effectiveLatency = bsMaxLatencyMs
		}
		speed = bsDefaultLatencyMs / effectiveLatency
	}

	cPenalty := 1.0
	if coolingDown {
		cPenalty = bsCooldownPenalty
	}

	fPenalty := 1.0 / (1.0 + float64(h.consecutiveFailures)*bsConsecutiveFailPenalty)

	w := correctness * speed * cPenalty * fPenalty
	if w < bsMinWeight {
		w = bsMinWeight
	} else if w > bsMaxWeight {
		w = bsMaxWeight
	}

	return bootstrapScore{
		entry:       entry,
		weight:      w,
		coolingDown: coolingDown,
		sampleCount: decayedAttempts,
	}
}
