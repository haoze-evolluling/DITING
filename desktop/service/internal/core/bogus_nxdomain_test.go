package core

import (
	"net"
	"testing"

	"github.com/miekg/dns"
)

func bogusAResponse(domain string, ip string) *dns.Msg {
	resp := new(dns.Msg)
	resp.Response = true
	resp.Rcode = dns.RcodeSuccess
	resp.Answer = append(resp.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: dns.Fqdn(domain), Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
		A:   net.ParseIP(ip).To4(),
	})
	return resp
}

func TestBogusNXDomain_ExactAndCIDR(t *testing.T) {
	m, err := NewBogusNXDomainMatcher([]string{"203.0.113.7", "198.51.100.0/24"})
	if err != nil {
		t.Fatalf("NewBogusNXDomainMatcher: %v", err)
	}

	cases := map[string]bool{
		"203.0.113.7":  true,
		"203.0.113.8":  false, // 精确匹配不应扩散到同网段
		"198.51.100.5": true,
		"198.51.100.0": true, // 网段首地址
		"198.51.100.255": true,
		"198.51.101.1": false, // 网段之外
	}
	for ip, want := range cases {
		if got := m.MatchIP(net.ParseIP(ip)); got != want {
			t.Errorf("MatchIP(%s) = %v, want %v", ip, got, want)
		}
	}
}

func TestBogusNXDomain_IPv6(t *testing.T) {
	m, err := NewBogusNXDomainMatcher([]string{"::1", "2001:db8::/32"})
	if err != nil {
		t.Fatalf("NewBogusNXDomainMatcher: %v", err)
	}
	if !m.MatchIP(net.ParseIP("::1")) {
		t.Error("exact IPv6 address must match")
	}
	if !m.MatchIP(net.ParseIP("2001:db8::abcd")) {
		t.Error("IPv6 CIDR must match")
	}
	if m.MatchIP(net.ParseIP("2001:db9::1")) {
		t.Error("address outside the IPv6 CIDR must not match")
	}
}

func TestBogusNXDomain_InvalidEntriesReported(t *testing.T) {
	m, err := NewBogusNXDomainMatcher([]string{"10.0.0.1", "not-an-ip", "10.0.0.0/99"})
	if err == nil {
		t.Fatal("invalid entries must be reported")
	}
	if m.Size() != 1 {
		t.Fatalf("the valid entry must survive, got %d", m.Size())
	}
	if !m.MatchIP(net.ParseIP("10.0.0.1")) {
		t.Fatal("the valid entry must still take effect")
	}
}

func TestBogusNXDomain_EmptyAndNil(t *testing.T) {
	m, err := NewBogusNXDomainMatcher(nil)
	if err != nil {
		t.Fatalf("NewBogusNXDomainMatcher(nil): %v", err)
	}
	if m.MatchIP(net.ParseIP("1.2.3.4")) {
		t.Fatal("an empty matcher must never match")
	}
	if _, hit := m.FindInMsg(bogusAResponse("a.test", "1.2.3.4")); hit {
		t.Fatal("an empty matcher must never report a hit")
	}

	var nilM *BogusNXDomainMatcher
	if nilM.MatchIP(net.ParseIP("1.2.3.4")) {
		t.Fatal("a nil matcher must never match")
	}
	if _, hit := nilM.FindInMsg(bogusAResponse("a.test", "1.2.3.4")); hit {
		t.Fatal("a nil matcher must never report a hit")
	}
	if nilM.Size() != 0 || nilM.Hits() != 0 || nilM.Entries() != nil {
		t.Fatal("a nil matcher must report empty state")
	}
}

// 只看 Answer：Authority / Additional 里的地址属于辅助信息，
// 据此改写应答会误伤正常解析（如 NS 恰好落在被列入的网段）
func TestBogusNXDomain_OnlyAnswerSection(t *testing.T) {
	m, _ := NewBogusNXDomainMatcher([]string{"198.51.100.0/24"})

	resp := new(dns.Msg)
	resp.Response = true
	resp.Rcode = dns.RcodeSuccess
	resp.Answer = append(resp.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: "ok.test.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
		A:   net.ParseIP("93.184.216.34").To4(),
	})
	resp.Ns = append(resp.Ns, &dns.A{
		Hdr: dns.RR_Header{Name: "ns.test.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
		A:   net.ParseIP("198.51.100.9").To4(),
	})

	if _, hit := m.FindInMsg(resp); hit {
		t.Fatal("addresses outside the Answer section must not trigger a rewrite")
	}
}

func TestBogusNXDomain_AAAA(t *testing.T) {
	m, _ := NewBogusNXDomainMatcher([]string{"::1"})
	resp := new(dns.Msg)
	resp.Response = true
	resp.Rcode = dns.RcodeSuccess
	resp.Answer = append(resp.Answer, &dns.AAAA{
		Hdr:  dns.RR_Header{Name: "v6.test.", Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: 300},
		AAAA: net.ParseIP("::1"),
	})
	ip, hit := m.FindInMsg(resp)
	if !hit || ip == nil || !ip.Equal(net.ParseIP("::1")) {
		t.Fatalf("AAAA records must be inspected, got ip=%v hit=%v", ip, hit)
	}
}

func TestBogusNXDomain_HitsCounter(t *testing.T) {
	m, _ := NewBogusNXDomainMatcher([]string{"1.2.3.4"})
	if m.Hits() != 0 {
		t.Fatal("no hits before any scan")
	}
	m.FindInMsg(bogusAResponse("a.test", "1.2.3.4"))
	m.FindInMsg(bogusAResponse("b.test", "5.6.7.8"))
	if m.Hits() != 1 {
		t.Fatalf("hits = %d, want 1", m.Hits())
	}
}

func TestBogusNXDomain_CountLimit(t *testing.T) {
	entries := make([]string, 0, maxBogusNXDomainNetworks+5)
	for i := 0; i < maxBogusNXDomainNetworks+5; i++ {
		entries = append(entries, "10."+string(rune('0'+i%10))+"."+string(rune('0'+i/10%10))+"."+string(rune('0'+i/100%10)))
	}
	m, err := NewBogusNXDomainMatcher(entries)
	if err == nil {
		t.Fatal("exceeding the entry cap must be reported")
	}
	if m.Size() != maxBogusNXDomainNetworks {
		t.Fatalf("size = %d, want the cap %d", m.Size(), maxBogusNXDomainNetworks)
	}
}

func TestBogusNXDomain_DefaultNetworks(t *testing.T) {
	m, err := NewBogusNXDomainMatcher(DefaultBogusNXDomainNetworks())
	if err != nil {
		t.Fatalf("the built-in defaults must all be valid: %v", err)
	}
	for _, ip := range []string{"0.0.0.0", "127.0.0.1", "::", "::1"} {
		if !m.MatchIP(net.ParseIP(ip)) {
			t.Errorf("%s should be covered by the defaults", ip)
		}
	}
	// 私网地址刻意不在默认清单内：内网服务大量使用，列入会直接误伤
	for _, ip := range []string{"192.168.1.1", "10.0.0.1", "fd00::1"} {
		if m.MatchIP(net.ParseIP(ip)) {
			t.Errorf("%s must not be in the defaults", ip)
		}
	}
}

func TestRuleEngine_BogusMatcherLifecycle(t *testing.T) {
	cfg := DefaultFilterConfig()
	cfg.Lists = []FilterList{} // 避免测试触发订阅列表加载
	cfg.BogusNXDomain = false

	engine := NewRuleEngine(cfg)
	defer engine.Close()

	if engine.BogusNXDomainMatcher() != nil {
		t.Fatal("the matcher must be nil while the feature is off")
	}

	next := engine.GetConfig()
	next.BogusNXDomain = true
	next.BogusNXDomainNetworks = []string{"203.0.113.9"}
	if err := engine.UpdateConfig(next); err != nil {
		t.Fatalf("UpdateConfig: %v", err)
	}
	m := engine.BogusNXDomainMatcher()
	if m == nil || !m.MatchIP(net.ParseIP("203.0.113.9")) {
		t.Fatal("enabling the feature must build a working matcher")
	}

	// 关闭后必须真的失效，否则开关形同虚设
	off := engine.GetConfig()
	off.BogusNXDomain = false
	if err := engine.UpdateConfig(off); err != nil {
		t.Fatalf("UpdateConfig: %v", err)
	}
	if engine.BogusNXDomainMatcher() != nil {
		t.Fatal("disabling the feature must clear the matcher")
	}
}

// 关闭规则拦截总开关必须同时停掉伪应答纠正，
// 否则会出现"拦截已关闭却仍在改写应答"的矛盾状态
func TestRuleEngine_BogusMatcherFollowsMasterSwitch(t *testing.T) {
	cfg := DefaultFilterConfig()
	cfg.Lists = []FilterList{}
	cfg.BogusNXDomain = true
	cfg.BogusNXDomainNetworks = []string{"203.0.113.9"}

	engine := NewRuleEngine(cfg)
	defer engine.Close()

	if engine.BogusNXDomainMatcher() == nil {
		t.Fatal("setup failed")
	}

	engine.SetEnabled(false)
	if engine.BogusNXDomainMatcher() != nil {
		t.Fatal("the master switch must disable the bogus matcher")
	}

	engine.SetEnabled(true)
	if engine.BogusNXDomainMatcher() == nil {
		t.Fatal("re-enabling the master switch must restore the bogus matcher")
	}
}

// 配置里全部条目非法时必须清空，避免界面展示与实际生效不一致
func TestRuleEngine_BogusMatcherAllInvalidClears(t *testing.T) {
	cfg := DefaultFilterConfig()
	cfg.Lists = []FilterList{}
	cfg.BogusNXDomain = true
	cfg.BogusNXDomainNetworks = []string{"203.0.113.9"}

	engine := NewRuleEngine(cfg)
	defer engine.Close()
	if engine.BogusNXDomainMatcher() == nil {
		t.Fatal("setup failed")
	}

	next := engine.GetConfig()
	next.BogusNXDomainNetworks = []string{"not-an-ip-at-all"}
	if err := engine.UpdateConfig(next); err != nil {
		t.Fatalf("UpdateConfig: %v", err)
	}
	if engine.BogusNXDomainMatcher() != nil {
		t.Fatal("an all-invalid list must clear the matcher")
	}
}

func TestNormalizeFilterConfig_BogusNetworks(t *testing.T) {
	cfg := DefaultFilterConfig()
	cfg.BogusNXDomainNetworks = []string{" 10.0.0.1 ", "10.0.0.1", "", "   ", "10.0.0.2/24"}
	NormalizeFilterConfig(&cfg)

	want := []string{"10.0.0.1", "10.0.0.2/24"}
	if len(cfg.BogusNXDomainNetworks) != len(want) {
		t.Fatalf("normalized = %v, want %v", cfg.BogusNXDomainNetworks, want)
	}
	for i, w := range want {
		if cfg.BogusNXDomainNetworks[i] != w {
			t.Fatalf("normalized = %v, want %v", cfg.BogusNXDomainNetworks, want)
		}
	}

	// 默认配置必须带上一组可直接使用的清单
	def := DefaultFilterConfig()
	if len(def.BogusNXDomainNetworks) == 0 {
		t.Fatal("the default config should ship with a usable network list")
	}
	if def.BogusNXDomain {
		t.Fatal("the feature must default to off")
	}
}
