// dns_cache_flight.go implements panic-safe single-flight query coalescing
// for concurrent in-flight DNS queries.

package tunnel

import (
	"encoding/binary"
	"fmt"
	"sync"
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
	domain, qtype, qclass, queryID, ok := extractQuestionFromRaw(rawQuery)
	if !ok {
		resp, err := resolveFn()
		return resp, false, err
	}

	if cachedResp, hit, _ := c.get(rawQuery); hit {
		return cachedResp, true, nil
	}

	key := cacheKey(domain, qtype, qclass)

	val, shared, err := c.flight.Do(key, func() ([]byte, error) {
		res, resErr := resolveFn()
		if resErr == nil && len(res) > 0 {
			c.put(rawQuery, res)
		}
		return res, resErr
	})

	if err != nil {
		return nil, false, err
	}

	if shared {
		if cachedResp, hit, _ := c.get(rawQuery); hit {
			return cachedResp, true, nil
		}
		if len(val) >= 2 {
			res := make([]byte, len(val))
			copy(res, val)
			binary.BigEndian.PutUint16(res[0:2], queryID)
			return res, true, nil
		}
		return val, true, nil
	}

	return val, false, nil
}
