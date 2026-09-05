package tunnel

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/miekg/dns"
)

const predictionBackupDelay = 50 * time.Millisecond

// extractDomain parses the queried domain name from a raw DNS query.
func extractDomain(rawQuery []byte) string {
	var msg dns.Msg
	if err := msg.Unpack(rawQuery); err != nil || len(msg.Question) == 0 {
		return ""
	}
	return strings.TrimSuffix(strings.ToLower(msg.Question[0].Name), ".")
}

func extractQueryInfo(rawQuery []byte) (string, uint16) {
	var msg dns.Msg
	if err := msg.Unpack(rawQuery); err != nil || len(msg.Question) == 0 {
		return "", dns.TypeA
	}
	return strings.TrimSuffix(strings.ToLower(msg.Question[0].Name), "."), msg.Question[0].Qtype
}

func (r *Resolver) resolveConfigured(rawQuery []byte, snapshot *resolverSnapshot) ([]byte, error) {
	queryName, queryType := extractQueryInfo(rawQuery)
	startTime := time.Now()
	mode := snapshot.mode
	providers := snapshot.providers

	switch mode {
	case "single":
		return r.resolveSingle(rawQuery, queryName, queryType, startTime, providers)
	case "primary_backup":
		return r.resolvePrimaryBackup(rawQuery, queryName, queryType, startTime, providers)
	case "parallel_race", "race":
		return r.resolveParallelRace(rawQuery, queryName, queryType, startTime, snapshot)
	case "smart_prediction", "prediction":
		return r.resolveSmartPrediction(rawQuery, queryName, queryType, startTime, snapshot)
	default:
		return r.resolveSingle(rawQuery, queryName, queryType, startTime, providers)
	}
}

func (r *Resolver) resolveSingle(rawQuery []byte, queryName string, queryType uint16, startTime time.Time, providers []*configuredProvider) ([]byte, error) {
	if len(providers) == 0 {
		return nil, fmt.Errorf("no providers available")
	}
	p := providers[0]
	ctx, cancel := context.WithTimeout(context.Background(), queryTimeoutPlain)
	defer cancel()

	resp, elapsed, err := r.queryConfiguredProvider(ctx, p, rawQuery)
	totalElapsed := time.Since(startTime).Milliseconds()
	if err != nil {
		r.notifyRaceLog(queryName, queryType, "single", len(providers), false, totalElapsed, p.id, elapsed.Milliseconds(), "", 0, false, false, err.Error())
		return nil, err
	}
	r.notifyRaceLog(queryName, queryType, "single", len(providers), true, totalElapsed, p.id, elapsed.Milliseconds(), p.id, elapsed.Milliseconds(), false, false, "")
	return resp, nil
}

func (r *Resolver) resolvePrimaryBackup(rawQuery []byte, queryName string, queryType uint16, startTime time.Time, providers []*configuredProvider) ([]byte, error) {
	if len(providers) == 0 {
		return nil, fmt.Errorf("no providers available")
	}
	var lastErr error
	primaryID := providers[0].id
	for i, provider := range providers {
		ctx, cancel := context.WithTimeout(context.Background(), queryTimeoutPlain)
		resp, elapsed, err := r.queryConfiguredProvider(ctx, provider, rawQuery)
		cancel()
		if err == nil {
			totalElapsed := time.Since(startTime).Milliseconds()
			fallbackUsed := i > 0
			fallbackSuccess := i > 0
			r.notifyRaceLog(queryName, queryType, "primary_backup", len(providers), true, totalElapsed, primaryID, 0, provider.id, elapsed.Milliseconds(), fallbackUsed, fallbackSuccess, "")
			return resp, nil
		}
		lastErr = err
	}
	totalElapsed := time.Since(startTime).Milliseconds()
	fallbackUsed := len(providers) > 1
	var errMsg string
	if lastErr != nil {
		errMsg = lastErr.Error()
	}
	r.notifyRaceLog(queryName, queryType, "primary_backup", len(providers), false, totalElapsed, primaryID, 0, "", 0, fallbackUsed, false, errMsg)
	return nil, lastErr
}

type providerRaceResult struct {
	provider *configuredProvider
	response []byte
	elapsed  time.Duration
	err      error
}

func (r *Resolver) resolveParallelRace(rawQuery []byte, queryName string, queryType uint16, startTime time.Time, snapshot *resolverSnapshot) ([]byte, error) {
	providers := snapshot.providers
	n := len(providers)
	if n == 0 {
		return nil, fmt.Errorf("no providers available")
	}
	if n == 1 {
		return r.resolveSingle(rawQuery, queryName, queryType, startTime, providers)
	}

	ctx, cancel := context.WithTimeout(context.Background(), queryTimeoutPlain)
	defer cancel()

	resultCh := make(chan providerRaceResult, n)
	spawned := 0
	for _, p := range providers {
		if !snapshot.acquire() {
			continue
		}
		spawned++
		go func(prov *configuredProvider) {
			defer snapshot.release()
			resp, elapsed, err := r.queryConfiguredProvider(ctx, prov, rawQuery)
			resultCh <- providerRaceResult{
				provider: prov,
				response: resp,
				elapsed:  elapsed,
				err:      err,
			}
		}(p)
	}

	if spawned == 0 {
		return nil, fmt.Errorf("snapshot retired: no race providers could be acquired")
	}

	var lastErr error
	completed := 0
	for completed < spawned {
		res := <-resultCh
		completed++
		if res.err == nil && res.response != nil {
			cancel()
			totalElapsed := time.Since(startTime).Milliseconds()
			r.notifyRaceLog(queryName, queryType, "parallel_race", spawned, true, totalElapsed, "", 0, res.provider.id, res.elapsed.Milliseconds(), false, false, "")
			return res.response, nil
		}
		lastErr = res.err
	}

	totalElapsed := time.Since(startTime).Milliseconds()
	var errMsg string
	if lastErr != nil {
		errMsg = lastErr.Error()
	}
	r.notifyRaceLog(queryName, queryType, "parallel_race", spawned, false, totalElapsed, "", 0, "", 0, false, false, errMsg)
	return nil, lastErr
}

type predResult struct {
	provider *configuredProvider
	response []byte
	elapsed  time.Duration
	err      error
	isBackup bool
}

func (r *Resolver) resolveSmartPrediction(rawQuery []byte, queryName string, queryType uint16, startTime time.Time, snapshot *resolverSnapshot) ([]byte, error) {
	providers := snapshot.providers
	n := len(providers)
	if n == 0 {
		return nil, fmt.Errorf("no providers available")
	}
	if n == 1 {
		return r.resolveSingle(rawQuery, queryName, queryType, startTime, providers)
	}

	candidates := make([]*configuredProvider, n)
	copy(candidates, providers)
	sort.SliceStable(candidates, func(i, j int) bool {
		var scoreI, scoreJ time.Duration
		if candidates[i].stats != nil {
			scoreI = candidates[i].stats.Score()
		}
		if candidates[j].stats != nil {
			scoreJ = candidates[j].stats.Score()
		}
		return scoreI < scoreJ
	})

	primary := candidates[0]
	rest := candidates[1:]

	ctx, cancel := context.WithTimeout(context.Background(), queryTimeoutPlain)
	defer cancel()

	resultCh := make(chan predResult, n)

	if !snapshot.acquire() {
		return nil, fmt.Errorf("snapshot retired: primary provider could not be acquired")
	}
	go func() {
		defer snapshot.release()
		resp, elapsed, err := r.queryConfiguredProvider(ctx, primary, rawQuery)
		resultCh <- predResult{
			provider: primary,
			response: resp,
			elapsed:  elapsed,
			err:      err,
			isBackup: false,
		}
	}()

	backupTimer := time.NewTimer(predictionBackupDelay)
	defer backupTimer.Stop()

	var fallbackTriggered bool
	var winner *predResult
	var lastErr error
	completed := 0
	expected := 1

	triggerBackups := func() {
		if fallbackTriggered {
			return
		}
		fallbackTriggered = true
		for _, b := range rest {
			if !snapshot.acquire() {
				continue
			}
			expected++
			go func(prov *configuredProvider) {
				defer snapshot.release()
				resp, elapsed, err := r.queryConfiguredProvider(ctx, prov, rawQuery)
				resultCh <- predResult{
					provider: prov,
					response: resp,
					elapsed:  elapsed,
					err:      err,
					isBackup: true,
				}
			}(b)
		}
	}

	for {
		select {
		case <-backupTimer.C:
			triggerBackups()

		case res := <-resultCh:
			completed++
			if res.err == nil && res.response != nil {
				resCopy := res
				winner = &resCopy
				cancel()
				goto DONE
			}
			lastErr = res.err
			if !res.isBackup && !fallbackTriggered {
				backupTimer.Stop()
				triggerBackups()
			}
			if fallbackTriggered && completed >= expected {
				goto DONE
			} else if !fallbackTriggered && completed >= 1 {
				// Primary failed and triggered backups, wait for backups
			}
		}
	}

DONE:
	totalElapsed := time.Since(startTime).Milliseconds()
	if winner != nil {
		fallbackSuccess := winner.isBackup
		var selectedElapsed int64
		if !winner.isBackup {
			selectedElapsed = winner.elapsed.Milliseconds()
		}
		r.notifyRaceLog(
			queryName,
			queryType,
			"smart_prediction",
			n,
			true,
			totalElapsed,
			primary.id,
			selectedElapsed,
			winner.provider.id,
			winner.elapsed.Milliseconds(),
			fallbackTriggered,
			fallbackSuccess,
			"",
		)
		return winner.response, nil
	}

	var errMsg string
	if lastErr != nil {
		errMsg = lastErr.Error()
	}
	r.notifyRaceLog(
		queryName,
		queryType,
		"smart_prediction",
		n,
		false,
		totalElapsed,
		primary.id,
		0,
		"",
		0,
		fallbackTriggered,
		false,
		errMsg,
	)
	return nil, lastErr
}

func (r *Resolver) queryConfiguredProvider(ctx context.Context, provider *configuredProvider, rawQuery []byte) (resp []byte, elapsed time.Duration, err error) {
	start := time.Now()
	defer func() {
		if rec := recover(); rec != nil {
			err = fmt.Errorf("provider %s panicked: %v", provider.id, rec)
			if provider.stats != nil {
				provider.stats.RecordFailure()
			}
		}
	}()

	if provider.resolver != nil {
		resp, err = provider.resolver.queryWithContext(ctx, rawQuery, provider.protocol, provider.server, provider.dohURL)
	} else {
		err = fmt.Errorf("provider resolver is nil")
	}
	elapsed = time.Since(start)
	if err != nil {
		if provider.stats != nil {
			provider.stats.RecordFailure()
		}
		return nil, elapsed, err
	}
	if err := validateDNSResponse(rawQuery, resp); err != nil {
		if provider.stats != nil {
			provider.stats.RecordFailure()
		}
		return nil, elapsed, err
	}
	if provider.stats != nil {
		provider.stats.RecordSuccess(elapsed)
	}
	return resp, elapsed, nil
}

func validateDNSResponse(rawQuery, rawResponse []byte) error {
	var query, response dns.Msg
	if err := query.Unpack(rawQuery); err != nil {
		return fmt.Errorf("invalid DNS query: %w", err)
	}
	if query.Response || len(query.Question) == 0 {
		return fmt.Errorf("invalid DNS query flags or empty question")
	}
	if err := response.Unpack(rawResponse); err != nil {
		return fmt.Errorf("invalid DNS response: %w", err)
	}
	if !response.Response || response.Id != query.Id {
		return fmt.Errorf("DNS response transaction mismatch")
	}
	if len(response.Question) != len(query.Question) {
		return fmt.Errorf("DNS response question count mismatch")
	}
	for i := range query.Question {
		q, a := query.Question[i], response.Question[i]
		if !strings.EqualFold(q.Name, a.Name) || q.Qtype != a.Qtype || q.Qclass != a.Qclass {
			return fmt.Errorf("DNS response question mismatch")
		}
	}
	return nil
}
