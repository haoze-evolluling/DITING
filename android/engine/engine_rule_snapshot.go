// engine_rule_snapshot.go keeps the lock-free resolver view used by the DNS hot path.
//
// Writers update e.resolver under e.mu and mirror it into an atomic pointer, so DNS
// goroutines read the current resolver with one atomic load instead of the engine mutex.

package tunnel

// setResolverLocked must be called with e.mu held; it keeps the lock-free
// resolver view in sync with e.resolver.
func (e *Engine) setResolverLocked(r *Resolver) {
	e.resolver = r
	e.resolverView.Store(r)
}

// currentResolver is the hot-path read of e.resolver. The atomic view is the
// fast path; the locked read covers code (tests) that assigns e.resolver
// directly without going through setResolverLocked.
func (e *Engine) currentResolver() *Resolver {
	if r := e.resolverView.Load(); r != nil {
		return r
	}
	e.mu.Lock()
	r := e.resolver
	e.mu.Unlock()
	return r
}
