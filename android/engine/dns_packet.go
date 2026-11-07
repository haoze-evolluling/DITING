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

// ParseResponseType maps the block-response name to its mode. The table (case-sensitive, unknown
// means CUSTOM_IP) lives in rust/diting-config-core; without the kernel it falls back to CUSTOM_IP.
func ParseResponseType(s string) ResponseType {
	return parseResponseTypeNative(s)
}
