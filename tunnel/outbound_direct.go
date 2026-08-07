package tunnel

// ─────────────────────────────────────────────────────────────────────────────
// DirectOutbound — The "no proxy" adapter for DNS-only ad-blocking mode.
//
// When this adapter is active, non-DNS packets are silently dropped.
// This preserves the original behavior of the app: only DNS queries are
// intercepted for ad-blocking, and all other traffic uses the normal network.
//
// This adapter serves as the default when no proxy is configured.
// ─────────────────────────────────────────────────────────────────────────────

// DirectOutbound implements OutboundAdapter for DNS-only mode (no proxy).
type DirectOutbound struct{}

// NewDirectOutbound creates a new DirectOutbound adapter.
func NewDirectOutbound() *DirectOutbound {
	return &DirectOutbound{}
}

// Name returns the adapter name.
func (d *DirectOutbound) Name() string {
	return "direct"
}

// Start is a no-op for direct mode.
func (d *DirectOutbound) Start() error {
	logf("DirectOutbound: started (DNS-only mode, non-DNS packets dropped)")
	return nil
}

// Stop is a no-op for direct mode.
func (d *DirectOutbound) Stop() {
	logf("DirectOutbound: stopped")
}

// HandlePacket drops non-DNS packets in DNS-only mode.
// In the original architecture, the TUN only receives DNS queries (routed
// via the fake DNS server 10.0.0.1), so this is rarely called.
func (d *DirectOutbound) HandlePacket(packet []byte, length int) {
	// Intentionally dropped — DNS-only mode has no outbound proxy.
}

// SupportsStreams returns false — direct mode is not a stream-based proxy.
func (d *DirectOutbound) SupportsStreams() bool {
	return false
}
