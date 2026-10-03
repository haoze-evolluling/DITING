// DirectOutbound implements the OutboundAdapter interface for DNS-only ad-blocking mode.
// When active, non-DNS packets routed to the TUN interface are silently dropped, as only
// DNS queries (directed to the fake DNS server) are intercepted for filtering, while all
// other traffic flows directly through the native network. It serves as the default outbound
// adapter when no upstream proxy is configured.

package tunnel

type DirectOutbound struct{}

func NewDirectOutbound() *DirectOutbound {
	return &DirectOutbound{}
}

func (d *DirectOutbound) Name() string {
	return "direct"
}

func (d *DirectOutbound) Start() error {
	logf("DirectOutbound: started (DNS-only mode, non-DNS packets dropped)")
	return nil
}

func (d *DirectOutbound) Stop() {
	logf("DirectOutbound: stopped")
}

func (d *DirectOutbound) HandlePacket(packet []byte, length int) {

}

func (d *DirectOutbound) SupportsStreams() bool {
	return false
}
