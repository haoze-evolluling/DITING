// dns_cache_wire.go implements high-performance DNS wire-format parsing,
// zero-copy ID and TTL patching, and pre-indexed record metadata extraction.

package tunnel

import (
	"encoding/binary"
	"fmt"
	"strings"

	"github.com/miekg/dns"
)

func extractQuestionFromRaw(rawQuery []byte) (string, uint16, uint16, uint16, bool) {
	if len(rawQuery) < 12 {
		return "", 0, 0, 0, false
	}
	queryID := binary.BigEndian.Uint16(rawQuery[0:2])
	qdCount := binary.BigEndian.Uint16(rawQuery[4:6])
	if qdCount == 0 {
		return "", 0, 0, 0, false
	}

	offset, ok := skipDNSName(rawQuery, 12)
	if !ok || offset+4 > len(rawQuery) {
		return "", 0, 0, 0, false
	}

	qtype := binary.BigEndian.Uint16(rawQuery[offset : offset+2])
	qclass := binary.BigEndian.Uint16(rawQuery[offset+2 : offset+4])

	name, err := parseDNSName(rawQuery, 12)
	if err != nil {
		return "", 0, 0, 0, false
	}

	return strings.ToLower(strings.TrimSuffix(name, ".")), qtype, qclass, queryID, true
}

func parseDNSName(wire []byte, offset int) (string, error) {
	var sb strings.Builder
	visited := 0
	curr := offset
	for curr < len(wire) {
		length := int(wire[curr])
		if length == 0 {
			break
		}
		if (length & 0xc0) == 0xc0 {
			if curr+2 > len(wire) {
				return "", fmt.Errorf("truncated compression pointer")
			}
			ptr := int(binary.BigEndian.Uint16(wire[curr:curr+2]) & 0x3fff)
			curr = ptr
			visited++
			if visited > 64 {
				return "", fmt.Errorf("compression loop")
			}
			continue
		}
		if (length & 0xc0) != 0 {
			return "", fmt.Errorf("invalid label length format")
		}
		curr++
		if curr+length > len(wire) {
			return "", fmt.Errorf("truncated label")
		}
		if sb.Len() > 0 {
			sb.WriteByte('.')
		}
		sb.Write(wire[curr : curr+length])
		curr += length
	}
	return sb.String(), nil
}

func skipDNSName(wire []byte, offset int) (int, bool) {
	visited := 0
	for offset < len(wire) {
		length := int(wire[offset])
		if length == 0 {
			return offset + 1, true
		}
		if (length & 0xc0) == 0xc0 {
			if offset+2 > len(wire) {
				return 0, false
			}
			return offset + 2, true
		}
		if (length & 0xc0) != 0 {
			return 0, false
		}
		offset += 1 + length
		visited++
		if visited > 128 {
			return 0, false
		}
	}
	return 0, false
}

func extractTtlOffsetsFromWire(wire []byte, isNegative bool) []uint16 {
	if len(wire) < 12 {
		return nil
	}
	qdCount := int(binary.BigEndian.Uint16(wire[4:6]))
	anCount := int(binary.BigEndian.Uint16(wire[6:8]))
	nsCount := int(binary.BigEndian.Uint16(wire[8:10]))

	offset := 12
	for i := 0; i < qdCount; i++ {
		next, ok := skipDNSName(wire, offset)
		if !ok || next+4 > len(wire) {
			return nil
		}
		offset = next + 4
	}

	totalRRs := anCount
	if isNegative && totalRRs == 0 {
		totalRRs = nsCount
	}
	if totalRRs <= 0 {
		return nil
	}

	offsets := make([]uint16, 0, totalRRs)
	for i := 0; i < totalRRs; i++ {
		next, ok := skipDNSName(wire, offset)
		if !ok || next+10 > len(wire) {
			break
		}
		rrType := binary.BigEndian.Uint16(wire[next : next+2])
		rdLen := int(binary.BigEndian.Uint16(wire[next+8 : next+10]))
		if rrType != dns.TypeOPT {
			offsets = append(offsets, uint16(next+4))
		}
		offset = next + 10 + rdLen
		if offset > len(wire) {
			break
		}
	}
	return offsets
}

func patchWireResponse(wire []byte, ttlOffsets []uint16, queryID uint16, ttl uint32) []byte {
	if len(wire) < 12 {
		return nil
	}
	patched := make([]byte, len(wire))
	copy(patched, wire)
	binary.BigEndian.PutUint16(patched[0:2], queryID)
	for _, offset := range ttlOffsets {
		if int(offset)+4 <= len(patched) {
			binary.BigEndian.PutUint32(patched[offset:offset+4], ttl)
		}
	}
	return patched
}

func extractChainTargetsFromMsg(respMsg *dns.Msg) []chainTarget {
	if respMsg == nil || len(respMsg.Answer) == 0 {
		return nil
	}
	var targets []chainTarget
	for _, rr := range respMsg.Answer {
		switch record := rr.(type) {
		case *dns.CNAME:
			domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(record.Target)), ".")
			if domain != "" {
				targets = append(targets, chainTarget{domain: domain, kind: "cname"})
			}
		case *dns.SVCB:
			domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(record.Target)), ".")
			if domain != "" {
				targets = append(targets, chainTarget{domain: domain, kind: "svcb"})
			}
		case *dns.HTTPS:
			domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(record.SVCB.Target)), ".")
			if domain != "" {
				targets = append(targets, chainTarget{domain: domain, kind: "svcb"})
			}
		}
	}
	return targets
}

func extractIPsFromMsg(respMsg *dns.Msg) ([]string, string) {
	if respMsg == nil || len(respMsg.Answer) == 0 {
		return nil, ""
	}
	seen := make(map[string]struct{})
	var ips []string
	for _, answer := range respMsg.Answer {
		var address string
		switch record := answer.(type) {
		case *dns.A:
			if record.A != nil {
				address = record.A.String()
			}
		case *dns.AAAA:
			if record.AAAA != nil {
				address = record.AAAA.String()
			}
		}
		if address == "" {
			continue
		}
		if _, exists := seen[address]; exists {
			continue
		}
		seen[address] = struct{}{}
		ips = append(ips, address)
	}
	return ips, strings.Join(ips, ",")
}

func extractMinTTL(msg *dns.Msg) (uint32, bool) {
	if msg == nil {
		return 0, false
	}

	var minTTL uint32
	found := false

	// RFC 2181 §5.2: TTL for answers is governed by the Answer section.
	if len(msg.Answer) > 0 {
		for _, rr := range msg.Answer {
			if rr == nil || rr.Header() == nil || rr.Header().Rrtype == dns.TypeOPT {
				continue
			}
			ttl := rr.Header().Ttl
			if !found || ttl < minTTL {
				minTTL = ttl
				found = true
			}
		}
		if found {
			return minTTL, true
		}
	}

	// For Negative Caching (NODATA or NXDOMAIN), check SOA in Authority section.
	for _, rr := range msg.Ns {
		if soa, ok := rr.(*dns.SOA); ok && soa.Header() != nil {
			ttl := soa.Minttl
			if ttl == 0 || (soa.Header().Ttl > 0 && soa.Header().Ttl < ttl) {
				ttl = soa.Header().Ttl
			}
			return ttl, true
		}
	}

	return 0, false
}
