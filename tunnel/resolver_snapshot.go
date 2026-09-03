package tunnel

import (
	"sync"
)

type configuredProvider struct {
	id       string
	protocol DNSProtocol
	server   string
	dohURL   string
	resolver *Resolver
	stats    *providerStats
}

type resolverSnapshot struct {
	mu        sync.Mutex
	providers []*configuredProvider
	mode      string
	active    int
	retired   bool
	closed    bool
}

func (s *resolverSnapshot) acquire() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.retired {
		return false
	}
	s.active++
	return true
}

func (s *resolverSnapshot) release() {
	s.mu.Lock()
	s.active--
	closeNow := s.retired && s.active == 0 && !s.closed
	if closeNow {
		s.closed = true
	}
	s.mu.Unlock()
	if closeNow {
		s.closeProviders()
	}
}

func (s *resolverSnapshot) retire() {
	s.mu.Lock()
	s.retired = true
	closeNow := s.active == 0 && !s.closed
	if closeNow {
		s.closed = true
	}
	s.mu.Unlock()
	if closeNow {
		s.closeProviders()
	}
}

func (s *resolverSnapshot) closeProviders() {
	for _, provider := range s.providers {
		provider.resolver.Shutdown()
	}
}
