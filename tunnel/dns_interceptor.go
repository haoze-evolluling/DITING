// dns_interceptor.go implements DnsInterceptor, reading raw packets from the TUN device and separating DNS from non-DNS traffic.
//
// Traffic Demultiplexing:
// - UDP destination port 53 queries are dispatched to the ad-block DNS engine.
// - Non-DNS traffic is forwarded to the Router's OutboundAdapter or pushed into the packet pipe for the userspace TCP/IP stack.

package tunnel

import (
	"encoding/binary"
	"os"
	"sync"
	"sync/atomic"
)

type DnsInterceptor struct {
	engine  *Engine
	router  *Router
	tunFile *os.File

	mu      sync.Mutex
	running bool

	totalQueries   *atomic.Int64
	blockedQueries *atomic.Int64

	stackPacketsPushed atomic.Int64
	stackPipeNilDrops  atomic.Int64
}

func NewDnsInterceptor(engine *Engine, router *Router) *DnsInterceptor {
	return &DnsInterceptor{
		engine:         engine,
		router:         router,
		totalQueries:   &engine.totalQueries,
		blockedQueries: &engine.blockedQueries,
	}
}

func (i *DnsInterceptor) Run(tunFile *os.File) {
	i.mu.Lock()
	i.tunFile = tunFile
	i.running = true
	i.mu.Unlock()

	i.router.SetTunFile(tunFile)

	logf("DnsInterceptor: started, reading from TUN")

	buf := make([]byte, 32767)
	for i.IsRunning() {
		n, err := tunFile.Read(buf)
		if err != nil {
			if i.IsRunning() {
				logf("DnsInterceptor: TUN read error: %v", err)
			}
			break
		}
		if n <= 0 {
			continue
		}

		if isDNSPacket(buf, n) {
			queryInfo := ParseTUNPacket(buf, n)
			if queryInfo != nil {
				go i.engine.handleDNSQuery(queryInfo)
			}
		} else if i.engine.IsUsingTcpStack() {

			pipe := i.engine.tcpStackPipe.Load()
			if pipe != nil {
				pipe.Push(buf[:n])
				if c := i.stackPacketsPushed.Add(1); c <= 10 {
					logf("DnsInterceptor: pushed packet #%d to stack (size=%d, version=%d)", c, n, buf[0]>>4)
				}
			} else {
				if c := i.stackPipeNilDrops.Add(1); c <= 5 {
					logf("DnsInterceptor: stack flag on but pipe nil (drop #%d, size=%d)", c, n)
				}
			}
		} else {

			pkt := make([]byte, n)
			copy(pkt, buf[:n])
			i.router.RoutePacket(pkt, n)
		}
	}

	logf("DnsInterceptor: stopped")
}

func (i *DnsInterceptor) Stop() {
	i.mu.Lock()
	defer i.mu.Unlock()
	i.running = false
}

func (i *DnsInterceptor) IsRunning() bool {
	i.mu.Lock()
	defer i.mu.Unlock()
	return i.running
}

func isDNSPacket(packet []byte, length int) bool {
	if length < ipv4HeaderSize+udpHeaderSize {
		return false
	}

	version := packet[0] >> 4

	switch version {
	case 4:

		if packet[9] != 17 {
			return false
		}
		ihl := int(packet[0]&0x0F) * 4
		if length < ihl+udpHeaderSize {
			return false
		}
		destPort := binary.BigEndian.Uint16(packet[ihl+2 : ihl+4])
		return destPort == 53

	case 6:

		if length < ipv6HeaderSize+udpHeaderSize {
			return false
		}
		if packet[6] != 17 {
			return false
		}
		destPort := binary.BigEndian.Uint16(packet[ipv6HeaderSize+2 : ipv6HeaderSize+4])
		return destPort == 53

	default:
		return false
	}
}
