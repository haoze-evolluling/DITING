package tunnel

import (
	"encoding/binary"
	"net"
	"strings"

	"github.com/miekg/dns"
)

// ResponseType determines how blocked domains are responded to.
type ResponseType int

const (
	ResponseCustomIP ResponseType = iota // 0.0.0.0
	ResponseNXDomain                     // NXDOMAIN
	ResponseRefused                      // REFUSED
	ResponseNoData                       // NOERROR with an empty answer
)

// ParseResponseType converts a string to ResponseType.
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

const (
	ipv4HeaderSize = 20
	ipv6HeaderSize = 40
	udpHeaderSize  = 8
)

// DNSQueryInfo holds parsed DNS query information from a raw TUN packet.
type DNSQueryInfo struct {
	SourceIP      net.IP
	DestIP        net.IP
	SourcePort    uint16
	DestPort      uint16
	RawDNSPayload []byte
	Domain        string
	QueryType     uint16
	IsIPv6        bool
}

// ParseTUNPacket parses a raw IP packet from the TUN device and extracts DNS query info.
// Returns nil if the packet is not a valid DNS query.
func ParseTUNPacket(packet []byte, length int) *DNSQueryInfo {
	if length < ipv4HeaderSize {
		return nil
	}

	version := packet[0] >> 4
	var info *DNSQueryInfo

	switch version {
	case 4:
		info = parseIPv4Packet(packet, length)
	case 6:
		info = parseIPv6Packet(packet, length)
	default:
		return nil
	}

	if info == nil {
		return nil
	}

	// Parse DNS message to get domain and query type
	var msg dns.Msg
	if err := msg.Unpack(info.RawDNSPayload); err != nil {
		return nil
	}

	if len(msg.Question) == 0 {
		return nil
	}

	q := msg.Question[0]
	info.Domain = strings.TrimSuffix(q.Name, ".")
	info.QueryType = q.Qtype

	return info
}

func parseIPv4Packet(packet []byte, length int) *DNSQueryInfo {
	if length < ipv4HeaderSize+udpHeaderSize {
		return nil
	}

	// Check protocol (17 = UDP)
	if packet[9] != 17 {
		return nil
	}

	ihl := int(packet[0]&0x0F) * 4
	if length < ihl+udpHeaderSize {
		return nil
	}

	sourceIP := make(net.IP, 4)
	copy(sourceIP, packet[12:16])
	destIP := make(net.IP, 4)
	copy(destIP, packet[16:20])

	udpStart := ihl
	sourcePort := binary.BigEndian.Uint16(packet[udpStart : udpStart+2])
	destPort := binary.BigEndian.Uint16(packet[udpStart+2 : udpStart+4])

	dnsStart := udpStart + udpHeaderSize
	if length <= dnsStart {
		return nil
	}

	dnsPayload := make([]byte, length-dnsStart)
	copy(dnsPayload, packet[dnsStart:length])

	return &DNSQueryInfo{
		SourceIP:      sourceIP,
		DestIP:        destIP,
		SourcePort:    sourcePort,
		DestPort:      destPort,
		RawDNSPayload: dnsPayload,
		IsIPv6:        false,
	}
}

func parseIPv6Packet(packet []byte, length int) *DNSQueryInfo {
	if length < ipv6HeaderSize+udpHeaderSize {
		return nil
	}

	// Check next header (17 = UDP)
	if packet[6] != 17 {
		return nil
	}

	sourceIP := make(net.IP, 16)
	copy(sourceIP, packet[8:24])
	destIP := make(net.IP, 16)
	copy(destIP, packet[24:40])

	udpStart := ipv6HeaderSize
	sourcePort := binary.BigEndian.Uint16(packet[udpStart : udpStart+2])
	destPort := binary.BigEndian.Uint16(packet[udpStart+2 : udpStart+4])

	dnsStart := udpStart + udpHeaderSize
	if length <= dnsStart {
		return nil
	}

	dnsPayload := make([]byte, length-dnsStart)
	copy(dnsPayload, packet[dnsStart:length])

	return &DNSQueryInfo{
		SourceIP:      sourceIP,
		DestIP:        destIP,
		SourcePort:    sourcePort,
		DestPort:      destPort,
		RawDNSPayload: dnsPayload,
		IsIPv6:        true,
	}
}

// BuildBlockedResponse builds a DNS response that returns 0.0.0.0 for a blocked domain.
func BuildBlockedResponse(queryInfo *DNSQueryInfo) []byte {
	var msg dns.Msg
	msg.Unpack(queryInfo.RawDNSPayload)

	resp := new(dns.Msg)
	resp.SetReply(&msg)
	resp.RecursionAvailable = true

	if len(msg.Question) > 0 {
		q := msg.Question[0]
		switch q.Qtype {
		case dns.TypeA:
			resp.Answer = append(resp.Answer, &dns.A{
				Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
				A:   net.IPv4zero,
			})
		case dns.TypeAAAA:
			resp.Answer = append(resp.Answer, &dns.AAAA{
				Hdr:  dns.RR_Header{Name: q.Name, Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: 300},
				AAAA: net.IPv6zero,
			})
		}
	}

	dnsResp, _ := resp.Pack()
	return buildIPUDPPacket(queryInfo, dnsResp)
}

// BuildNXDomainResponse builds a DNS NXDOMAIN response.
func BuildNXDomainResponse(queryInfo *DNSQueryInfo) []byte {
	var msg dns.Msg
	msg.Unpack(queryInfo.RawDNSPayload)

	resp := new(dns.Msg)
	resp.SetRcode(&msg, dns.RcodeNameError) // NXDOMAIN
	resp.RecursionAvailable = true

	dnsResp, _ := resp.Pack()
	return buildIPUDPPacket(queryInfo, dnsResp)
}

// BuildRefusedResponse builds a DNS REFUSED response.
func BuildRefusedResponse(queryInfo *DNSQueryInfo) []byte {
	var msg dns.Msg
	msg.Unpack(queryInfo.RawDNSPayload)

	resp := new(dns.Msg)
	resp.SetRcode(&msg, dns.RcodeRefused)
	resp.RecursionAvailable = true

	dnsResp, _ := resp.Pack()
	return buildIPUDPPacket(queryInfo, dnsResp)
}

// BuildServfailResponse builds a DNS SERVFAIL response.
func BuildServfailResponse(queryInfo *DNSQueryInfo) []byte {
	var msg dns.Msg
	msg.Unpack(queryInfo.RawDNSPayload)

	resp := new(dns.Msg)
	resp.SetRcode(&msg, dns.RcodeServerFailure)
	resp.RecursionAvailable = true

	dnsResp, _ := resp.Pack()
	return buildIPUDPPacket(queryInfo, dnsResp)
}

// BuildRedirectResponse builds a DNS response that redirects to a specific IPv4 address.
func BuildRedirectResponse(queryInfo *DNSQueryInfo, ip net.IP) []byte {
	var msg dns.Msg
	msg.Unpack(queryInfo.RawDNSPayload)

	resp := new(dns.Msg)
	resp.SetReply(&msg)
	resp.RecursionAvailable = true

	if len(msg.Question) > 0 {
		q := msg.Question[0]
		if q.Qtype == dns.TypeA {
			resp.Answer = append(resp.Answer, &dns.A{
				Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
				A:   ip.To4(),
			})
		}
		// For AAAA queries when redirecting to IPv4, return empty response
	}

	dnsResp, _ := resp.Pack()
	return buildIPUDPPacket(queryInfo, dnsResp)
}

// BuildForwardedResponse wraps a raw DNS response in IP+UDP headers.
func BuildForwardedResponse(queryInfo *DNSQueryInfo, dnsResp []byte) []byte {
	return buildIPUDPPacket(queryInfo, dnsResp)
}

// buildIPUDPPacket wraps a DNS payload in IP+UDP headers for writing back to TUN.
// Source/dest are SWAPPED (response goes back to the original sender).
func buildIPUDPPacket(queryInfo *DNSQueryInfo, payload []byte) []byte {
	if queryInfo.IsIPv6 {
		return buildIPv6UDPPacket(queryInfo.DestIP, queryInfo.SourceIP, queryInfo.DestPort, queryInfo.SourcePort, payload)
	}
	return buildIPv4UDPPacket(queryInfo.DestIP, queryInfo.SourceIP, queryInfo.DestPort, queryInfo.SourcePort, payload)
}

func buildIPv4UDPPacket(srcIP, dstIP net.IP, srcPort, dstPort uint16, payload []byte) []byte {
	udpLen := udpHeaderSize + len(payload)
	totalLen := ipv4HeaderSize + udpLen
	packet := make([]byte, totalLen)

	// IPv4 header
	packet[0] = 0x45 // Version + IHL
	binary.BigEndian.PutUint16(packet[2:4], uint16(totalLen))
	packet[8] = 64  // TTL
	packet[9] = 17  // Protocol (UDP)
	copy(packet[12:16], srcIP.To4())
	copy(packet[16:20], dstIP.To4())

	// Calculate IPv4 header checksum
	csum := calculateChecksum(packet[:ipv4HeaderSize])
	binary.BigEndian.PutUint16(packet[10:12], csum)

	// UDP header
	udpOffset := ipv4HeaderSize
	binary.BigEndian.PutUint16(packet[udpOffset:udpOffset+2], srcPort)
	binary.BigEndian.PutUint16(packet[udpOffset+2:udpOffset+4], dstPort)
	binary.BigEndian.PutUint16(packet[udpOffset+4:udpOffset+6], uint16(udpLen))
	// UDP checksum = 0 (optional for IPv4)

	// Payload
	copy(packet[udpOffset+udpHeaderSize:], payload)

	return packet
}

func buildIPv6UDPPacket(srcIP, dstIP net.IP, srcPort, dstPort uint16, payload []byte) []byte {
	udpLen := udpHeaderSize + len(payload)
	totalLen := ipv6HeaderSize + udpLen
	packet := make([]byte, totalLen)

	// IPv6 header
	packet[0] = 0x60                                                    // Version 6
	binary.BigEndian.PutUint16(packet[4:6], uint16(udpLen))             // Payload length
	packet[6] = 17                                                      // Next header (UDP)
	packet[7] = 64                                                      // Hop limit
	copy(packet[8:24], srcIP.To16())
	copy(packet[24:40], dstIP.To16())

	// UDP header
	udpOffset := ipv6HeaderSize
	binary.BigEndian.PutUint16(packet[udpOffset:udpOffset+2], srcPort)
	binary.BigEndian.PutUint16(packet[udpOffset+2:udpOffset+4], dstPort)
	binary.BigEndian.PutUint16(packet[udpOffset+4:udpOffset+6], uint16(udpLen))

	// Calculate UDP checksum (mandatory for IPv6)
	csum := calculateUDPIPv6Checksum(srcIP.To16(), dstIP.To16(), packet, udpOffset, udpLen)
	binary.BigEndian.PutUint16(packet[udpOffset+6:udpOffset+8], csum)

	// Payload
	copy(packet[udpOffset+udpHeaderSize:], payload)

	return packet
}

func calculateChecksum(data []byte) uint16 {
	var sum uint32
	for i := 0; i+1 < len(data); i += 2 {
		sum += uint32(binary.BigEndian.Uint16(data[i : i+2]))
	}
	if len(data)%2 != 0 {
		sum += uint32(data[len(data)-1]) << 8
	}
	for sum > 0xFFFF {
		sum = (sum >> 16) + (sum & 0xFFFF)
	}
	return ^uint16(sum)
}

func calculateUDPIPv6Checksum(srcIP, dstIP []byte, packet []byte, udpOffset, udpLen int) uint16 {
	// Pseudo-header for IPv6 UDP checksum
	var sum uint32

	// Source address (16 bytes)
	for i := 0; i < 16; i += 2 {
		sum += uint32(srcIP[i])<<8 | uint32(srcIP[i+1])
	}
	// Dest address (16 bytes)
	for i := 0; i < 16; i += 2 {
		sum += uint32(dstIP[i])<<8 | uint32(dstIP[i+1])
	}
	// UDP length (4 bytes, big-endian)
	sum += uint32(udpLen)
	// Next header = 17 (4 bytes, big-endian)
	sum += 17

	// UDP header + data (clear checksum field first)
	saved := binary.BigEndian.Uint16(packet[udpOffset+6 : udpOffset+8])
	binary.BigEndian.PutUint16(packet[udpOffset+6:udpOffset+8], 0)
	for i := udpOffset; i+1 < udpOffset+udpLen; i += 2 {
		sum += uint32(binary.BigEndian.Uint16(packet[i : i+2]))
	}
	if udpLen%2 != 0 {
		sum += uint32(packet[udpOffset+udpLen-1]) << 8
	}
	binary.BigEndian.PutUint16(packet[udpOffset+6:udpOffset+8], saved)

	for sum > 0xFFFF {
		sum = (sum >> 16) + (sum & 0xFFFF)
	}
	result := ^uint16(sum)
	if result == 0 {
		result = 0xFFFF // RFC 2460: checksum of 0 must be transmitted as 0xFFFF
	}
	return result
}
