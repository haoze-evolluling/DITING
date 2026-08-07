package tunnel

import (
	"os"
	"sync"

	"golang.zx2c4.com/wireguard/tun"
)

// ─────────────────────────────────────────────────────────────────────────────
// channelTUN — A virtual tun.Device backed by Go channels.
//
// Architecture:
//   Real TUN fd ──► DnsInterceptor (sole reader)
//       ├── DNS packets → adblock engine
//       └── non-DNS packets → channelTUN.inbound → wireguard-go encrypts → UDP
//                                                     UDP → wireguard-go decrypts
//       channelTUN.Write() ──► real TUN fd (decrypted responses)
//
// This avoids two readers competing for the same TUN fd, which causes
// packet loss and network lag.
// ─────────────────────────────────────────────────────────────────────────────

const defaultMTU = 1280

// channelTUN implements tun.Device using channels for inbound and writing
// directly to the real TUN for outbound (decrypted packets from WireGuard).
type channelTUN struct {
	realTUN   *os.File       // real TUN fd — only used for writing decrypted responses
	inbound   chan []byte     // non-DNS packets from DnsInterceptor → wireguard-go
	events    chan tun.Event
	closeOnce sync.Once
	closed    chan struct{}
}

// newChannelTUN creates a virtual TUN device backed by channels.
// realTUN is the actual Android VPN TUN fd (for writing decrypted responses).
func newChannelTUN(realTUN *os.File) tun.Device {
	t := &channelTUN{
		realTUN: realTUN,
		inbound: make(chan []byte, 256), // buffered to avoid blocking the interceptor
		events:  make(chan tun.Event, 1),
		closed:  make(chan struct{}),
	}
	t.events <- tun.EventUp
	return t
}

// Inject sends a packet into the virtual TUN for wireguard-go to encrypt.
// Called by WgOutbound.HandlePacket() for non-DNS packets.
func (t *channelTUN) Inject(packet []byte) {
	select {
	case t.inbound <- packet:
	case <-t.closed:
	default:
		// Channel full — drop packet rather than block the interceptor
	}
}

// Read is called by wireguard-go's receiver goroutine.
// Returns packets that the DnsInterceptor forwarded via Inject().
func (t *channelTUN) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	select {
	case pkt := <-t.inbound:
		copy(bufs[0][offset:], pkt)
		sizes[0] = len(pkt)
		return 1, nil
	case <-t.closed:
		return 0, os.ErrClosed
	}
}

// Write is called by wireguard-go to inject decrypted packets back into
// the real TUN device, making them visible to the Android network stack.
func (t *channelTUN) Write(bufs [][]byte, offset int) (int, error) {
	for i, buf := range bufs {
		packet := buf[offset:]
		if len(packet) == 0 {
			continue
		}
		if _, err := t.realTUN.Write(packet); err != nil {
			return i, err
		}
	}
	return len(bufs), nil
}

// MTU returns the MTU of the TUN device.
func (t *channelTUN) MTU() (int, error) {
	return defaultMTU, nil
}

// Name returns the name of the TUN device.
func (t *channelTUN) Name() (string, error) {
	return "channel-tun", nil
}

// Events returns a channel of TUN device events.
func (t *channelTUN) Events() <-chan tun.Event {
	return t.events
}

// File returns nil — channelTUN doesn't expose a real file descriptor.
// wireguard-go uses this for MTU detection on some platforms, but on Android
// it falls back to the MTU() method.
func (t *channelTUN) File() *os.File {
	return nil
}

// Close closes the virtual TUN device.
// Note: does NOT close the real TUN fd (the Engine owns that).
func (t *channelTUN) Close() error {
	t.closeOnce.Do(func() {
		close(t.closed)
		close(t.events)
	})
	return nil
}

// BatchSize returns 1.
func (t *channelTUN) BatchSize() int {
	return 1
}
