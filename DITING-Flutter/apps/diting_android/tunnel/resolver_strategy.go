// resolver_strategy.go implements upstream query scheduling and failover strategies.
//
// Scheduling Strategies:
// - Single: Queries a single configured upstream with adaptive UDP retry intervals.
// - Primary-Backup: Prioritizes primary upstreams with shared query budget, per-provider adaptive timeouts,
//   and exponential-backoff circuit breaking with half-open probes.
// - Parallel-Race: Races queries across upstreams via the unified scheduler, supporting optional concurrency
//   caps and an encrypted-protocol preference window in mixed-protocol setups.
// - Smart-Prediction: Staggered hedging ordered by expected provider cost (see resolver_smart.go).

package tunnel

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/miekg/dns"
)

type parsedDNSQuery struct {
	id        uint16
	questions []dns.Question
}

type upstreamRcodeError struct {
	rcode int
}

func (e *upstreamRcodeError) Error() string {
	return fmt.Sprintf("upstream returned %s", dns.RcodeToString[e.rcode])
}

func (e *upstreamRcodeError) isPolicyRejection() bool {
	switch e.rcode {
	case dns.RcodeRefused, dns.RcodeFormatError, dns.RcodeNotImplemented:
		return true
	default:
		return false
	}
}

func parseDNSQuery(rawQuery []byte) (*parsedDNSQuery, string, uint16) {
	var msg dns.Msg
	if err := msg.Unpack(rawQuery); err != nil || msg.Response || len(msg.Question) == 0 {
		return nil, "", dns.TypeA
	}
	qName := strings.TrimSuffix(strings.ToLower(msg.Question[0].Name), ".")
	return &parsedDNSQuery{
		id:        msg.Id,
		questions: msg.Question,
	}, qName, msg.Question[0].Qtype
}

func extractQueryInfo(rawQuery []byte) (string, uint16) {
	_, name, qtype := parseDNSQuery(rawQuery)
	return name, qtype
}

// resolveConfigured returns the raw answer plus the *dns.Msg that validation
// already unpacked, so callers do not have to unpack the same bytes again.
func (r *Resolver) resolveConfigured(ctx context.Context, rawQuery []byte, snapshot *resolverSnapshot) ([]byte, *dns.Msg, error) {
	parsed, queryName, queryType := parseDNSQuery(rawQuery)
	startTime := time.Now()
	mode := snapshot.mode
	providers := snapshot.providers

	switch mode {
	case "single":
		return r.resolveSingle(ctx, rawQuery, parsed, queryName, queryType, startTime, providers)
	case "primary_backup":
		return r.resolvePrimaryBackup(ctx, rawQuery, parsed, queryName, queryType, startTime, providers)
	case "parallel_race", "race":
		return r.resolveParallelRace(ctx, rawQuery, parsed, queryName, queryType, startTime, snapshot)
	case "smart_prediction", "prediction":
		return r.resolveSmartPrediction(ctx, rawQuery, parsed, queryName, queryType, startTime, snapshot)
	default:
		return r.resolveSingle(ctx, rawQuery, parsed, queryName, queryType, startTime, providers)
	}
}

func (r *Resolver) resolveSingle(
	parentCtx context.Context,
	rawQuery []byte,
	parsed *parsedDNSQuery,
	queryName string,
	queryType uint16,
	startTime time.Time,
	providers []*configuredProvider,
) ([]byte, *dns.Msg, error) {
	if len(providers) == 0 {
		return nil, nil, fmt.Errorf("no providers available")
	}
	p := providers[0]
	ctx, cancel := context.WithTimeout(parentCtx, queryTimeoutPlain)
	defer cancel()

	resp, msg, elapsed, err := r.queryConfiguredProviderParsed(ctx, p, rawQuery, parsed)
	totalElapsed := time.Since(startTime).Milliseconds()
	selectedMs := elapsed.Milliseconds()
	if err != nil {
		r.notifyRaceLog(raceLogEvent{
			queryName:          queryName,
			queryType:          queryType,
			strategy:           "single",
			providerCount:      len(providers),
			success:            false,
			elapsedMs:          totalElapsed,
			selectedProviderID: p.id,
			selectedElapsedMs:  selectedMs,
			errorMessage:       err.Error(),
		})
		return nil, nil, err
	}
	r.notifyRaceLog(raceLogEvent{
		queryName:          queryName,
		queryType:          queryType,
		strategy:           "single",
		providerCount:      len(providers),
		success:            true,
		elapsedMs:          totalElapsed,
		selectedProviderID: p.id,
		selectedElapsedMs:  selectedMs,
		winnerProviderID:   p.id,
		winnerElapsedMs:    selectedMs,
	})
	return resp, msg, nil
}

func providerAttemptTimeout(p *configuredProvider) time.Duration {
	if p == nil || p.stats == nil {
		return attemptTimeoutCold
	}
	return p.stats.AttemptTimeout()
}

func providerAllowsAttempt(p *configuredProvider, now time.Time) bool {
	if p == nil || p.stats == nil {
		return true
	}
	return p.stats.AllowAttempt(now)
}

func (r *Resolver) resolvePrimaryBackup(
	parentCtx context.Context,
	rawQuery []byte,
	parsed *parsedDNSQuery,
	queryName string,
	queryType uint16,
	startTime time.Time,
	providers []*configuredProvider,
) ([]byte, *dns.Msg, error) {
	n := len(providers)
	if n == 0 {
		return nil, nil, fmt.Errorf("no providers available")
	}
	if n == 1 {
		return r.resolveSingle(parentCtx, rawQuery, parsed, queryName, queryType, startTime, providers)
	}

	budgetCtx, budgetCancel := context.WithTimeout(parentCtx, queryTimeoutPlain)
	defer budgetCancel()

	// Build attempt order: active providers first in configured order, followed
	// by circuit-broken providers as a last-resort safety net so we never fail
	// without trying at least one upstream.
	now := startTime
	type indexedProvider struct {
		p   *configuredProvider
		idx int
	}
	order := make([]indexedProvider, 0, n)
	var skipped []indexedProvider
	for i, p := range providers {
		if providerAllowsAttempt(p, now) {
			order = append(order, indexedProvider{p: p, idx: i})
		} else {
			skipped = append(skipped, indexedProvider{p: p, idx: i})
		}
	}
	order = append(order, skipped...)

	primaryID := providers[0].id
	var primaryElapsed int64
	var errs []error

	for pos, item := range order {
		if budgetCtx.Err() != nil {
			break
		}
		provider := item.p
		attemptTimeout := providerAttemptTimeout(provider)
		if deadline, ok := budgetCtx.Deadline(); ok {
			remaining := time.Until(deadline)
			if pos == len(order)-1 || attemptTimeout > remaining {
				attemptTimeout = remaining
			}
		}
		if attemptTimeout <= 0 {
			break
		}

		attemptCtx, cancel := context.WithTimeout(budgetCtx, attemptTimeout)
		resp, msg, elapsed, err := r.queryConfiguredProviderParsed(attemptCtx, provider, rawQuery, parsed)
		cancel()
		if item.idx == 0 {
			primaryElapsed = elapsed.Milliseconds()
		}
		if err == nil && resp != nil {
			totalElapsed := time.Since(startTime).Milliseconds()
			fallbackUsed := item.idx > 0 || pos > 0
			fallbackSuccess := item.idx > 0
			r.notifyRaceLog(raceLogEvent{
				queryName:          queryName,
				queryType:          queryType,
				strategy:           "primary_backup",
				providerCount:      n,
				success:            true,
				elapsedMs:          totalElapsed,
				selectedProviderID: primaryID,
				selectedElapsedMs:  primaryElapsed,
				winnerProviderID:   provider.id,
				winnerElapsedMs:    elapsed.Milliseconds(),
				fallbackUsed:       fallbackUsed,
				fallbackSuccess:    fallbackSuccess,
			})
			return resp, msg, nil
		}
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", provider.id, err))
		}
	}

	totalElapsed := time.Since(startTime).Milliseconds()
	joinedErr := errors.Join(errs...)
	var errMsg string
	if joinedErr != nil {
		errMsg = joinedErr.Error()
	}
	r.notifyRaceLog(raceLogEvent{
		queryName:          queryName,
		queryType:          queryType,
		strategy:           "primary_backup",
		providerCount:      n,
		success:            false,
		elapsedMs:          totalElapsed,
		selectedProviderID: primaryID,
		selectedElapsedMs:  primaryElapsed,
		fallbackUsed:       n > 1,
		errorMessage:       errMsg,
	})
	return nil, nil, joinedErr
}

func (r *Resolver) resolveParallelRace(
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

	candidates := providers
	batch := n
	if snapshot.raceMaxParallel > 0 && snapshot.raceMaxParallel < n {
		candidates = rankProviders(providers, startTime)
		batch = snapshot.raceMaxParallel
	}

	var prefWindow time.Duration
	if hasMixedEncryptedAndPlain(candidates) {
		prefWindow = encryptedPreferenceWindow
	}

	return r.executeSchedulePlan(parentCtx, rawQuery, parsed, queryName, queryType, startTime, snapshot, schedulePlan{
		strategy:              "parallel_race",
		providerCount:         n,
		candidates:            candidates,
		initialBatch:          batch,
		advanceOnError:        batch < n,
		preferEncryptedWindow: prefWindow,
	})
}

func (r *Resolver) queryConfiguredProvider(ctx context.Context, provider *configuredProvider, rawQuery []byte) (resp []byte, elapsed time.Duration, err error) {
	parsed, _, _ := parseDNSQuery(rawQuery)
	resp, _, elapsed, err = r.queryConfiguredProviderParsed(ctx, provider, rawQuery, parsed)
	return resp, elapsed, err
}

func (r *Resolver) queryConfiguredProviderParsed(
	ctx context.Context,
	provider *configuredProvider,
	rawQuery []byte,
	parsed *parsedDNSQuery,
) (resp []byte, msg *dns.Msg, elapsed time.Duration, err error) {
	start := time.Now()
	defer func() {
		if rec := recover(); rec != nil {
			err = fmt.Errorf("provider %s panicked: %v", provider.id, rec)
			if provider.stats != nil {
				provider.stats.RecordFailure()
			}
		}
	}()

	callCtx := ctx
	if provider.protocol == ProtocolPlain && provider.stats != nil {
		callCtx = withPlainUDPRetryDelay(ctx, provider.stats.UDPRetryDelay())
	}

	if provider.resolver != nil {
		resp, err = provider.resolver.queryWithContext(callCtx, rawQuery, provider.protocol, provider.server, provider.dohURL)
	} else {
		err = fmt.Errorf("provider resolver is nil")
	}
	elapsed = time.Since(start)
	if err != nil {
		// Cancelled by the caller because another provider already won: the
		// provider is not broken, it was merely slower than the winner.
		if errors.Is(ctx.Err(), context.Canceled) {
			if provider.stats != nil {
				provider.stats.RecordCensored(elapsed)
			}
			return nil, nil, elapsed, err
		}
		if provider.stats != nil {
			provider.stats.RecordFailure()
		}
		return nil, nil, elapsed, err
	}
	msg, err = validateDNSResponseParsed(parsed, rawQuery, resp)
	if err != nil {
		if provider.stats != nil {
			var rcodeErr *upstreamRcodeError
			if errors.As(err, &rcodeErr) && rcodeErr.isPolicyRejection() {
				provider.stats.RecordPolicyFailure()
			} else {
				provider.stats.RecordFailure()
			}
		}
		return nil, nil, elapsed, err
	}
	if provider.stats != nil {
		provider.stats.RecordSuccess(elapsed)
	}
	return resp, msg, elapsed, nil
}

func validateDNSResponse(rawQuery, rawResponse []byte) error {
	parsed, _, _ := parseDNSQuery(rawQuery)
	_, err := validateDNSResponseParsed(parsed, rawQuery, rawResponse)
	return err
}

// validateDNSResponseParsed checks the answer against the query and returns the
// unpacked response for reuse by the cache and the engine.
func validateDNSResponseParsed(parsed *parsedDNSQuery, rawQuery, rawResponse []byte) (*dns.Msg, error) {
	if parsed == nil {
		var query dns.Msg
		if err := query.Unpack(rawQuery); err != nil {
			return nil, fmt.Errorf("invalid DNS query: %w", err)
		}
		if query.Response || len(query.Question) == 0 {
			return nil, fmt.Errorf("invalid DNS query flags or empty question")
		}
		parsed = &parsedDNSQuery{id: query.Id, questions: query.Question}
	}
	response := new(dns.Msg)
	if err := response.Unpack(rawResponse); err != nil {
		return nil, fmt.Errorf("invalid DNS response: %w", err)
	}
	if !response.Response || response.Id != parsed.id {
		return nil, fmt.Errorf("DNS response transaction mismatch")
	}
	if len(response.Question) != len(parsed.questions) {
		return nil, fmt.Errorf("DNS response question count mismatch")
	}
	for i := range parsed.questions {
		q, a := parsed.questions[i], response.Question[i]
		if !strings.EqualFold(q.Name, a.Name) || q.Qtype != a.Qtype || q.Qclass != a.Qclass {
			return nil, fmt.Errorf("DNS response question mismatch")
		}
	}
	// Upstream failure codes must be treated as provider failure so failover
	// strategies escalate to the next provider. NXDOMAIN is a valid negative
	// answer and must NOT trigger fallback.
	switch response.Rcode {
	case dns.RcodeSuccess, dns.RcodeNameError:
		return response, nil
	default:
		return nil, &upstreamRcodeError{rcode: response.Rcode}
	}
}
