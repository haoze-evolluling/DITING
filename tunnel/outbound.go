package tunnel

import (
	"os"
	"sync"
)

// ─────────────────────────────────────────────────────────────────────────────
// OutboundAdapter — The pluggable interface for routing non-DNS traffic.
//
// L3 adapters (WireGuard):   HandlePacket() receives raw IP packets.
// L4 adapters (future SS/VLESS): SupportsStreams()=true, Router feeds them
//                                net.Conn/net.PacketConn via a user-space
//                                network stack (gVisor netstack / tun2socks).
// ─────────────────────────────────────────────────────────────────────────────

// OutboundAdapter is the interface every proxy protocol must implement.
type OutboundAdapter interface {
	// Name returns a human-readable name for logging (e.g., "wireguard", "shadowsocks").
	Name() string

	// Start initializes the adapter and makes it ready to accept traffic.
	// Called once when the adapter is activated.
	Start() error

	// Stop shuts down the adapter and releases all resources.
	Stop()

	// HandlePacket receives a raw IP packet (L3) for outbound routing.
	// L3 adapters forward this to their tunnel device.
	// L4 adapters may ignore this (the Router uses netstack to convert
	// packets into streams before handing them to the L4 adapter).
	HandlePacket(packet []byte, length int)

	// SupportsStreams returns true if this adapter operates at Layer 4.
	// When true, the Router will insert a user-space network stack (e.g.,
	// gVisor netstack) between the TUN reader and this adapter, converting
	// raw IP packets into net.Conn (TCP) and net.PacketConn (UDP) streams.
	SupportsStreams() bool
}

// ─────────────────────────────────────────────────────────────────────────────
// Router — Dispatches non-DNS packets to the active OutboundAdapter.
// ─────────────────────────────────────────────────────────────────────────────

// Router manages the active outbound adapter and dispatches traffic to it.
// It also holds the TUN file for writing responses back to the device.
type Router struct {
	mu      sync.RWMutex
	adapter OutboundAdapter
	tunFile *os.File
	running bool
}

// NewRouter creates a new Router.
func NewRouter() *Router {
	return &Router{}
}

// SetAdapter switches the active outbound adapter.
// If an adapter was already active, it is stopped first.
func (r *Router) SetAdapter(adapter OutboundAdapter) {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Stop previous adapter
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

// GetAdapter returns the current active adapter (nil if none).
func (r *Router) GetAdapter() OutboundAdapter {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.adapter
}

// SetTunFile sets the TUN file descriptor for writing responses back.
func (r *Router) SetTunFile(f *os.File) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.tunFile = f
}

// RoutePacket dispatches a non-DNS IP packet to the active outbound adapter.
// If no adapter is active (DNS-only mode), the packet is silently dropped.
func (r *Router) RoutePacket(packet []byte, length int) {
	r.mu.RLock()
	adapter := r.adapter
	r.mu.RUnlock()

	if adapter == nil {
		// DNS-only mode — non-DNS packets are dropped (expected behavior).
		return
	}

	// For L4 adapters, we would feed the packet through netstack here.
	// For now, only L3 adapters are supported — pass raw packets directly.
	if adapter.SupportsStreams() {
		// FUTURE: Feed packet into gVisor netstack.
		// netstack reassembles TCP/UDP and calls adapter's stream handlers.
		// This is the insertion point for tun2socks / netstack.
		logf("Router: L4 adapter '%s' received packet but netstack not yet implemented", adapter.Name())
		return
	}

	// L3 path — forward raw IP packet directly to adapter.
	adapter.HandlePacket(packet, length)
}

// WriteToTun writes a packet back to the TUN device.
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

// Stop shuts down the router and its active adapter.
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
