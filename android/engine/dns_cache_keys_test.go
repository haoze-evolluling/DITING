package tunnel

import "github.com/miekg/dns"

// cacheKey spells the key of a domain the way the cache stores it, so tests can
// look an entry up by name. The format itself lives in the Rust kernel: this
// helper packs a real query and asks for its key.
func cacheKey(domain string, qtype, qclass uint16) string {
	if qclass != dns.ClassINET {
		panic("cacheKey test helper only supports the IN class")
	}
	query := new(dns.Msg)
	query.SetQuestion(dns.Fqdn(domain), qtype)
	raw, err := query.Pack()
	if err != nil {
		panic(err)
	}
	key, _, _, _, ok := nativeQuestionKey(raw, make([]byte, maxCacheKeyLen))
	if !ok {
		panic("cache key build failed for " + domain)
	}
	return string(key)
}
