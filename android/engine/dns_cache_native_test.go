// dns_cache_native_test.go pins the boundary with rust/diting-dns-cache-core: the
// metadata decode, the rejection path and the ID/TTL patch round trip.

package tunnel

import (
	"encoding/binary"
	"testing"

	"github.com/miekg/dns"
)

func TestNativeDNSCacheParseResponseMeta(t *testing.T) {
	query := new(dns.Msg)
	query.SetQuestion("target.example.", dns.TypeA)
	resp := new(dns.Msg)
	resp.SetReply(query)
	cname, err := dns.NewRR("target.example. 300 IN CNAME chain.example.")
	if err != nil {
		t.Fatal(err)
	}
	answer, err := dns.NewRR("chain.example. 60 IN A 192.0.2.7")
	if err != nil {
		t.Fatal(err)
	}
	resp.Answer = append(resp.Answer, cname, answer)
	raw, err := resp.Pack()
	if err != nil {
		t.Fatal(err)
	}

	meta, ok := nativeParseResponse(raw)
	if !ok || meta == nil {
		t.Fatal("response metadata was rejected")
	}
	if meta.answerCount != 2 {
		t.Fatalf("answer count = %d, want 2", meta.answerCount)
	}
	if meta.rcode != dns.RcodeSuccess || meta.truncated {
		t.Fatalf("rcode=%d truncated=%v", meta.rcode, meta.truncated)
	}
	if !meta.minTTLFound || meta.minTTL != 60 {
		t.Fatalf("min TTL = %d (found=%v), want 60", meta.minTTL, meta.minTTLFound)
	}
	if len(meta.answerTTLOffsets) != 2 {
		t.Fatalf("TTL offsets = %d, want 2", len(meta.answerTTLOffsets))
	}
	if len(meta.authorityTTLOffsets) != 0 {
		t.Fatalf("authority TTL offsets = %d, want 0", len(meta.authorityTTLOffsets))
	}
	if len(meta.chainTargets) != 1 || meta.chainTargets[0].domain != "chain.example" || meta.chainTargets[0].kind != "cname" {
		t.Fatalf("chain targets = %+v", meta.chainTargets)
	}
	if len(meta.ipList) != 1 || meta.ipList[0] != "192.0.2.7" {
		t.Fatalf("IPs = %v", meta.ipList)
	}
	if meta.resolvedIPs != "192.0.2.7" {
		t.Fatalf("resolved IPs = %q", meta.resolvedIPs)
	}

	// Every offset must point exactly at the TTL field of the record it belongs to.
	var parsed dns.Msg
	if err := parsed.Unpack(raw); err != nil {
		t.Fatal(err)
	}
	for i, offset := range meta.answerTTLOffsets {
		if int(offset)+4 > len(raw) {
			t.Fatalf("offset %d past the wire", offset)
		}
		if got := binary.BigEndian.Uint32(raw[offset : offset+4]); got != parsed.Answer[i].Header().Ttl {
			t.Fatalf("offset %d holds %d, record TTL is %d", offset, got, parsed.Answer[i].Header().Ttl)
		}
	}
}

func TestNativeDNSCacheRejectsMalformedResponse(t *testing.T) {
	if meta, ok := nativeParseResponse([]byte{0, 1, 2}); ok || meta != nil {
		t.Fatalf("malformed response accepted: %+v", meta)
	}
}

func TestNativeDNSCachePatchResponse(t *testing.T) {
	query := new(dns.Msg)
	query.SetQuestion("patch.example.", dns.TypeA)
	resp := new(dns.Msg)
	resp.SetReply(query)
	answer, err := dns.NewRR("patch.example. 300 IN A 192.0.2.9")
	if err != nil {
		t.Fatal(err)
	}
	resp.Answer = append(resp.Answer, answer)
	raw, err := resp.Pack()
	if err != nil {
		t.Fatal(err)
	}
	meta, ok := nativeParseResponse(raw)
	if !ok {
		t.Fatal("response metadata was rejected")
	}

	patched := nativePatchResponse(raw, meta.answerTTLOffsets, 0x4242, 7)
	if patched == nil {
		t.Fatal("patch failed")
	}
	var parsed dns.Msg
	if err := parsed.Unpack(patched); err != nil {
		t.Fatal(err)
	}
	if parsed.Id != 0x4242 {
		t.Fatalf("patched ID = %d, want 0x4242", parsed.Id)
	}
	if ttl := parsed.Answer[0].Header().Ttl; ttl != 7 {
		t.Fatalf("patched TTL = %d, want 7", ttl)
	}
	// The cached wire keeps the upstream TTL for the next hit.
	var original dns.Msg
	if err := original.Unpack(raw); err != nil {
		t.Fatal(err)
	}
	if ttl := original.Answer[0].Header().Ttl; ttl != 300 {
		t.Fatalf("source TTL changed to %d", ttl)
	}

	if nativePatchResponse([]byte{0, 1}, nil, 1, 1) != nil {
		t.Fatal("short wire was patched")
	}
}
