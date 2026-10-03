// socket_uid_resolver.go bridges socket 5-tuple ownership lookups to Android's ConnectivityManager.
//
// SELinux & Direction Inversion:
// - Android 10+ (API 29+) enforces SELinux restrictions on /proc/net, requiring ConnectivityManager.getConnectionOwnerUid().
// - Direction Translation: Maps tun2socks stack-oriented endpoints (local=server, remote=app) to Android OS parameters.
// - UIDUnknown (-1): Handled conservatively to prevent misattribution or unintended MITM interception.

package tunnel

import (
	"net"

	"github.com/xjasonlyu/tun2socks/v2/core/adapter"
)

const (
	ProtocolTCP = 6
	ProtocolUDP = 17
)

const UIDUnknown = -1

type UIDResolver interface {
	ResolveUID(protocol int, localIP string, localPort int, remoteIP string, remotePort int) int
}

func resolveFlowUID(r UIDResolver, protocol int, id flowID) int {
	if r == nil {
		return UIDUnknown
	}
	return r.ResolveUID(
		protocol,

		id.appIP.String(), id.appPort,

		id.serverIP.String(), id.serverPort,
	)
}

type flowID struct {
	appIP      net.IP
	appPort    int
	serverIP   net.IP
	serverPort int
}

func tcpFlowID(c adapter.TCPConn) flowID {
	id := c.ID()
	return flowID{
		appIP:      net.IP(id.RemoteAddress.AsSlice()),
		appPort:    int(id.RemotePort),
		serverIP:   net.IP(id.LocalAddress.AsSlice()),
		serverPort: int(id.LocalPort),
	}
}

func udpFlowID(c adapter.UDPConn) flowID {
	id := c.ID()
	return flowID{
		appIP:      net.IP(id.RemoteAddress.AsSlice()),
		appPort:    int(id.RemotePort),
		serverIP:   net.IP(id.LocalAddress.AsSlice()),
		serverPort: int(id.LocalPort),
	}
}
