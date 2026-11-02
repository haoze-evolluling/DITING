// dns_cache_wire.go implements high-performance DNS wire-format parsing,
// zero-copy ID and TTL patching, and pre-indexed record metadata extraction.

package tunnel

import (
	"encoding/binary"
	"strconv"
	"strings"

	"github.com/miekg/dns"
)

// appendQuestionKey appends the cache key of the first question in wire to dst
// and returns it with the length of the name part. The key has the same
// "name:qtype:qclass" form as cacheKey, with the name lowercased (ASCII) and
// labels joined by '.'. Building it straight from the wire bytes into a caller
// buffer lets the hit path look the entry up without allocating.
func appendQuestionKey(dst, wire []byte) ([]byte, int, bool) {
	if len(wire) < 12 || binary.BigEndian.Uint16(wire[4:6]) == 0 {
		return dst, 0, false
	}
	start := len(dst)
	curr, end, jumps := 12, -1, 0
	for {
		if curr >= len(wire) {
			return dst, 0, false
		}
		length := int(wire[curr])
		if length == 0 {
			if end < 0 {
				end = curr + 1
			}
			break
		}
		switch length & 0xc0 {
		case 0xc0:
			if curr+2 > len(wire) {
				return dst, 0, false
			}
			if end < 0 {
				end = curr + 2
			}
			jumps++
			if jumps > 64 {
				return dst, 0, false
			}
			curr = int(binary.BigEndian.Uint16(wire[curr:curr+2]) & 0x3fff)
			continue
		case 0:
		default:
			return dst, 0, false
		}
		curr++
		if curr+length > len(wire) {
			return dst, 0, false
		}
		if len(dst) > start {
			dst = append(dst, '.')
		}
		for _, b := range wire[curr : curr+length] {
			if 'A' <= b && b <= 'Z' {
				b += 'a' - 'A'
			}
			dst = append(dst, b)
		}
		curr += length
	}
	if end+4 > len(wire) {
		return dst, 0, false
	}
	nameLen := len(dst) - start
	dst = append(dst, ':')
	dst = strconv.AppendUint(dst, uint64(binary.BigEndian.Uint16(wire[end:end+2])), 10)
	dst = append(dst, ':')
	dst = strconv.AppendUint(dst, uint64(binary.BigEndian.Uint16(wire[end+2:end+4])), 10)
	return dst, nameLen, true
}

// parseKeyQuestion splits a key built by appendQuestionKey back into its parts.
func parseKeyQuestion(key string, nameLen int) (domain string, qtype, qclass uint16) {
	domain = key[:nameLen]
	rest := key[nameLen+1:]
	sep := strings.IndexByte(rest, ':')
	t, _ := strconv.ParseUint(rest[:sep], 10, 16)
	cl, _ := strconv.ParseUint(rest[sep+1:], 10, 16)
	return domain, uint16(t), uint16(cl)
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
