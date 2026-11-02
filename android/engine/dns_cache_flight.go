// dns_cache_flight.go implements panic-safe single-flight query coalescing
// for concurrent in-flight DNS queries.

package tunnel

import (
	"encoding/binary"
	"fmt"
	"sync"

	"github.com/miekg/dns"
)

type flightCall struct {
	wg       sync.WaitGroup
	val      []byte
	err      error
	panicked bool
}

type singleFlightGroup struct {
	mu    sync.Mutex
	calls map[string]*flightCall
}

func (g *singleFlightGroup) Do(key string, fn func() ([]byte, error)) (val []byte, shared bool, err error) {
	g.mu.Lock()
	if c, ok := g.calls[key]; ok {
		g.mu.Unlock()
		c.wg.Wait()
		if c.panicked {
			return nil, true, fmt.Errorf("singleflight panic in query for %s", key)
		}
		if len(c.val) > 0 {
			res := make([]byte, len(c.val))
			copy(res, c.val)
			return res, true, c.err
		}
		return nil, true, c.err
	}

	c := &flightCall{}
	c.wg.Add(1)
	g.calls[key] = c
	g.mu.Unlock()

	defer func() {
		if r := recover(); r != nil {
			c.panicked = true
			c.err = fmt.Errorf("singleflight panic: %v", r)
			err = c.err
		}
		g.mu.Lock()
		delete(g.calls, key)
		g.mu.Unlock()
		c.wg.Done()
	}()

	c.val, c.err = fn()
	return c.val, false, c.err
}

func (c *dnsCache) singleFlight(rawQuery []byte, resolveFn func() ([]byte, error)) ([]byte, bool, error) {
	resp, _, cached, err := c.singleFlightMsg(rawQuery, func() ([]byte, *dns.Msg, error) {
		raw, err := resolveFn()
		return raw, nil, err
	})
	return resp, cached, err
}

// singleFlightMsg coalesces concurrent identical queries and caches the answer.
//
// The returned *dns.Msg is the unpacked upstream answer and is only non-nil for
// the caller that actually performed the resolve: it was unpacked once (by the
// resolver's validation or here for the cache) and is owned by that caller, so
// it may be mutated. Shared and cached results return nil and must be unpacked
// by the caller if needed.
func (c *dnsCache) singleFlightMsg(rawQuery []byte, resolveFn func() ([]byte, *dns.Msg, error)) ([]byte, *dns.Msg, bool, error) {
	keyBytes, _, ok := appendQuestionKey(make([]byte, 0, 64), rawQuery)
	if !ok {
		resp, msg, err := resolveFn()
		return resp, msg, false, err
	}
	queryID := binary.BigEndian.Uint16(rawQuery[0:2])

	// Re-check without touching the counters: the caller's getFast already
	// recorded this query as a miss.
	if entry, cachedResp, stale := c.lookup(rawQuery, false); entry != nil && !stale {
		return cachedResp, nil, true, nil
	}

	key := string(keyBytes)

	var leaderMsg *dns.Msg
	val, shared, err := c.flight.Do(key, func() ([]byte, error) {
		res, msg, resErr := resolveFn()
		if resErr == nil && len(res) > 0 {
			if msg == nil {
				msg = new(dns.Msg)
				if msg.Unpack(res) != nil {
					msg = nil
				}
			}
			if msg != nil {
				c.putMsg(rawQuery, res, msg)
			}
		}
		leaderMsg = msg
		return res, resErr
	})

	if err != nil {
		return nil, nil, false, err
	}

	if shared {
		if entry, cachedResp, stale := c.lookup(rawQuery, false); entry != nil && !stale {
			return cachedResp, nil, true, nil
		}
		if len(val) >= 2 {
			res := make([]byte, len(val))
			copy(res, val)
			binary.BigEndian.PutUint16(res[0:2], queryID)
			return res, nil, true, nil
		}
		return val, nil, true, nil
	}

	return val, leaderMsg, false, nil
}
