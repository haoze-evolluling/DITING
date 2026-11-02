// resolver_smart.go implements the unified DNS upstream scheduler and the
// smart_prediction scheduling strategy.
//
// Unified Scheduler:
//   - All concurrent/staggered strategies (parallel_race, smart_prediction) share
//     a single execution loop that handles snapshot reference counting, staggered
//     hedging timers, immediate failover on error, encrypted-upstream grace window
//     against plain-UDP answers in mixed-protocol races, context cancellation,
//     censored-loser accounting, and aggregated error reporting.

package tunnel

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"time"

	"github.com/miekg/dns"
)

// encryptedPreferenceWindow is the short grace period given to in-flight
// encrypted upstreams (DoH/DoT/DoQ) when a Plain UDP upstream answers first in
// a mixed-protocol race, mitigating fast forged UDP replies.
const encryptedPreferenceWindow = 25 * time.Millisecond

type scheduleResult struct {
	provider *configuredProvider
	response []byte
	msg      *dns.Msg
	elapsed  time.Duration
	err      error
	index    int
}

type schedulePlan struct {
	strategy                string
	providerCount           int
	candidates              []*configuredProvider
	primaryID               string
	initialBatch            int
	hedgeDelayFn            func(last *configuredProvider) time.Duration
	advanceOnError          bool
	preferEncryptedWindow   time.Duration
	recordSelectedOnSuccess bool
	trackFallback           bool
}

// rankProviders orders providers by ascending score. Scores are computed once
// per query so the comparator does not take locks or read the clock.
func rankProviders(providers []*configuredProvider, now time.Time) []*configuredProvider {
	type ranked struct {
		p     *configuredProvider
		score time.Duration
	}
	items := make([]ranked, len(providers))
	for i, p := range providers {
		items[i] = ranked{p: p, score: defaultEWMA}
		if p.stats != nil {
			items[i].score = p.stats.scoreAt(now)
		}
	}
	sort.SliceStable(items, func(i, j int) bool { return items[i].score < items[j].score })
	out := make([]*configuredProvider, len(items))
	for i := range items {
		out[i] = items[i].p
	}
	return out
}

func providerHedgeDelay(p *configuredProvider) time.Duration {
	if p == nil || p.stats == nil {
		return hedgeDelayCold
	}
	return p.stats.HedgeDelay()
}

func hasMixedEncryptedAndPlain(providers []*configuredProvider) bool {
	var hasPlain, hasEnc bool
	for _, p := range providers {
		if p.protocol == ProtocolPlain {
			hasPlain = true
		} else {
			hasEnc = true
		}
		if hasPlain && hasEnc {
			return true
		}
	}
	return false
}

func (r *Resolver) resolveSmartPrediction(
	parentCtx context.Context,
	rawQuery []byte,
	parsed *parsedDNSQuery,
	queryName string,
	queryType uint16,
	startTime time.Time,
	snapshot *resolverSnapshot,
) ([]byte, *dns.Msg, error) {
	providers := snapshot.providers
	n := len(providers)
	if n == 0 {
		return nil, nil, fmt.Errorf("no providers available")
	}
	if n == 1 {
		return r.resolveSingle(parentCtx, rawQuery, parsed, queryName, queryType, startTime, providers)
	}

	candidates := rankProviders(providers, startTime)
	return r.executeSchedulePlan(parentCtx, rawQuery, parsed, queryName, queryType, startTime, snapshot, schedulePlan{
		strategy:                "smart_prediction",
		providerCount:           n,
		candidates:              candidates,
		primaryID:               candidates[0].id,
		initialBatch:            1,
		hedgeDelayFn:            providerHedgeDelay,
		advanceOnError:          true,
		recordSelectedOnSuccess: true,
		trackFallback:           true,
	})
}

func (r *Resolver) executeSchedulePlan(
	parentCtx context.Context,
	rawQuery []byte,
	parsed *parsedDNSQuery,
	queryName string,
	queryType uint16,
	startTime time.Time,
	snapshot *resolverSnapshot,
	plan schedulePlan,
) ([]byte, *dns.Msg, error) {
	candidates := plan.candidates
	n := len(candidates)
	if n == 0 {
		return nil, nil, fmt.Errorf("no providers available")
	}

	ctx, cancel := context.WithTimeout(parentCtx, queryTimeoutPlain)
	defer cancel()

	resultCh := make(chan scheduleResult, n)
	next := 0
	inflight := 0
	inflightEncrypted := 0
	spawned := 0
	var lastLaunched *configuredProvider

	launchOne := func() bool {
		for next < n {
			idx := next
			prov := candidates[idx]
			next++
			if !snapshot.acquire() {
				continue
			}
			spawned++
			inflight++
			if prov.protocol != ProtocolPlain {
				inflightEncrypted++
			}
			lastLaunched = prov
			go func(p *configuredProvider, i int) {
				defer snapshot.release()
				resp, msg, elapsed, err := r.queryConfiguredProviderParsed(ctx, p, rawQuery, parsed)
				resultCh <- scheduleResult{
					provider: p,
					response: resp,
					msg:      msg,
					elapsed:  elapsed,
					err:      err,
					index:    i,
				}
			}(prov, idx)
			return true
		}
		return false
	}

	batch := plan.initialBatch
	if batch < 1 {
		batch = 1
	}
	for i := 0; i < batch; i++ {
		if !launchOne() {
			break
		}
	}
	if spawned == 0 {
		return nil, nil, fmt.Errorf("snapshot retired: no providers could be acquired")
	}

	var hedgeTimer *time.Timer
	var hedgeC <-chan time.Time
	armHedge := func() {
		if hedgeTimer != nil {
			hedgeTimer.Stop()
			hedgeTimer, hedgeC = nil, nil
		}
		if plan.hedgeDelayFn != nil && next < n && lastLaunched != nil {
			hedgeTimer = time.NewTimer(plan.hedgeDelayFn(lastLaunched))
			hedgeC = hedgeTimer.C
		}
	}
	defer func() {
		if hedgeTimer != nil {
			hedgeTimer.Stop()
		}
	}()
	armHedge()

	var plainGraceTimer *time.Timer
	var plainGraceC <-chan time.Time
	defer func() {
		if plainGraceTimer != nil {
			plainGraceTimer.Stop()
		}
	}()

	var winner *scheduleResult
	var bufferedPlain *scheduleResult
	var primaryElapsed int64
	var errs []error

	for winner == nil && (inflight > 0 || bufferedPlain != nil) {
		if bufferedPlain != nil && inflightEncrypted == 0 {
			winner = bufferedPlain
			cancel()
			break
		}
		select {
		case <-hedgeC:
			if launchOne() {
				armHedge()
			} else {
				hedgeTimer, hedgeC = nil, nil
			}

		case <-plainGraceC:
			winner = bufferedPlain
			cancel()

		case res := <-resultCh:
			inflight--
			if res.provider.protocol != ProtocolPlain {
				inflightEncrypted--
			}
			if res.index == 0 {
				primaryElapsed = res.elapsed.Milliseconds()
			}
			if res.err == nil && res.response != nil {
				resCopy := res
				if plan.preferEncryptedWindow > 0 && res.provider.protocol == ProtocolPlain && inflightEncrypted > 0 {
					if bufferedPlain == nil {
						bufferedPlain = &resCopy
						plainGraceTimer = time.NewTimer(plan.preferEncryptedWindow)
						plainGraceC = plainGraceTimer.C
					}
					continue
				}
				winner = &resCopy
				cancel()
				break
			}
			if res.err != nil {
				errs = append(errs, fmt.Errorf("%s: %w", res.provider.id, res.err))
			}
			if plan.advanceOnError && launchOne() {
				armHedge()
			}
		}
	}

	fallbackTriggered := plan.trackFallback && spawned > 1
	totalElapsed := time.Since(startTime).Milliseconds()
	if winner != nil {
		fallbackSuccess := plan.trackFallback && winner.index > 0
		var selectedElapsed int64
		if plan.recordSelectedOnSuccess {
			if winner.index == 0 {
				selectedElapsed = winner.elapsed.Milliseconds()
			} else {
				selectedElapsed = primaryElapsed
			}
		}
		r.notifyRaceLog(raceLogEvent{
			queryName:          queryName,
			queryType:          queryType,
			strategy:           plan.strategy,
			providerCount:      plan.providerCount,
			success:            true,
			elapsedMs:          totalElapsed,
			selectedProviderID: plan.primaryID,
			selectedElapsedMs:  selectedElapsed,
			winnerProviderID:   winner.provider.id,
			winnerElapsedMs:    winner.elapsed.Milliseconds(),
			fallbackUsed:       fallbackTriggered,
			fallbackSuccess:    fallbackSuccess,
		})
		return winner.response, winner.msg, nil
	}

	joinedErr := errors.Join(errs...)
	var errMsg string
	if joinedErr != nil {
		errMsg = joinedErr.Error()
	}
	r.notifyRaceLog(raceLogEvent{
		queryName:          queryName,
		queryType:          queryType,
		strategy:           plan.strategy,
		providerCount:      plan.providerCount,
		success:            false,
		elapsedMs:          totalElapsed,
		selectedProviderID: plan.primaryID,
		selectedElapsedMs:  primaryElapsed,
		fallbackUsed:       fallbackTriggered,
		errorMessage:       errMsg,
	})
	return nil, nil, joinedErr
}
