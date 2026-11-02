// dns_packet.go defines the block response modes shared by every DNS entry point.
//
// The raw IP/UDP packet parser and response synthesizer that used to live here
// served the removed legacy TUN reader (Engine.Start + DnsInterceptor); DNS now
// only arrives through gVisor flows (full tunnel) or the standalone server.

package tunnel

type ResponseType int

const (
	ResponseCustomIP ResponseType = iota
	ResponseNXDomain
	ResponseRefused
	ResponseNoData
)

func ParseResponseType(s string) ResponseType {
	switch s {
	case "NXDOMAIN":
		return ResponseNXDomain
	case "REFUSED":
		return ResponseRefused
	case "NODATA":
		return ResponseNoData
	default:
		return ResponseCustomIP
	}
}
