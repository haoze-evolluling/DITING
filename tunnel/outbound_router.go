// outbound_router.go defines the pluggable OutboundAdapter interface and Router for routing non-DNS traffic.
//
// Routing Architecture:
// - OutboundAdapter abstracts proxy protocols operating at L3 (raw IP packet routing) or L4 (stream-based).
// - Router manages the active adapter, dispatches non-DNS IP packets from the TUN interface,
//   and provides fallback handling when no adapter is configured (DNS-only mode).

package tunnel

import (
	"os"
	"sync"
)

type OutboundAdapter interface {
	Name() string

	Start() error

	Stop()

	HandlePacket(packet []byte, length int)

	SupportsStreams() bool
}

type Router struct {
	mu      sync.RWMutex
	adapter OutboundAdapter
	tunFile *os.File
	running bool
}

func NewRouter() *Router {
	return &Router{}
}

func (r *Router) SetAdapter(adapter OutboundAdapter) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.adapter != nil {
		logf("Router: stopping previous adapter '%s'", r.adapter.Name())
		r.adapter.Stop()
	}

	r.adapter = adapter
	if adapter != nil {
		logf("Router: active adapter set to '%s'", adapter.Name())
	} else {
		logf("Router: no active adapter (DNS-only mode)")
	}
}

func (r *Router) GetAdapter() OutboundAdapter {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.adapter
}

func (r *Router) SetTunFile(f *os.File) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.tunFile = f
}

func (r *Router) RoutePacket(packet []byte, length int) {
	r.mu.RLock()
	adapter := r.adapter
	r.mu.RUnlock()

	if adapter == nil {
		return
	}

	if adapter.SupportsStreams() {

		logf("Router: L4 adapter '%s' received packet but netstack not yet implemented", adapter.Name())
		return
	}

	adapter.HandlePacket(packet, length)
}

func (r *Router) WriteToTun(data []byte) {
	r.mu.RLock()
	f := r.tunFile
	r.mu.RUnlock()

	if f == nil {
		return
	}
	if _, err := f.Write(data); err != nil {
		logf("Router: TUN write error: %v", err)
	}
}

func (r *Router) Stop() {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.adapter != nil {
		logf("Router: stopping adapter '%s'", r.adapter.Name())
		r.adapter.Stop()
		r.adapter = nil
	}
	r.running = false
}
