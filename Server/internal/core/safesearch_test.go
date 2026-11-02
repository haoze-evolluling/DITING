package core

import (
	"net"
	"testing"

	"github.com/miekg/dns"
)

// TestSafeSearchDefaultDisabled 校验默认配置下引擎不生效。
func TestSafeSearchDefaultDisabled(t *testing.T) {
	e := NewSafeSearchEngine(DefaultSafeSearchConfig())
	if e.IsEnabled() {
		t.Fatalf("默认配置总开关应为关闭")
	}
	if _, ok := e.Lookup("www.google.com", dns.TypeA); ok {
		t.Fatalf("总开关关闭时不应命中")
	}
}

// TestSafeSearchGoogleCNAME 校验 Google 各 TLD 映射到强制安全搜索入口。
func TestSafeSearchGoogleCNAME(t *testing.T) {
	cfg := DefaultSafeSearchConfig()
	cfg.Enabled = true
	e := NewSafeSearchEngine(cfg)

	for _, domain := range []string{"www.google.com", "www.google.co.uk", "www.google.de"} {
		res, ok := e.Lookup(domain, dns.TypeA)
		if !ok {
			t.Fatalf("%s 应命中安全搜索", domain)
		}
		if res.CNAME != "forcesafesearch.google.com." {
			t.Fatalf("%s 应重写为 forcesafesearch, 得到 %q", domain, res.CNAME)
		}
		if res.Service != SafeSearchGoogle {
			t.Fatalf("服务商应为 google, 得到 %q", res.Service)
		}
	}
}

// TestSafeSearchYandexIPRewrite 校验 Yandex 走 A 记录重写而非 CNAME。
func TestSafeSearchYandexIPRewrite(t *testing.T) {
	cfg := DefaultSafeSearchConfig()
	cfg.Enabled = true
	e := NewSafeSearchEngine(cfg)

	res, ok := e.Lookup("yandex.ru", dns.TypeA)
	if !ok {
		t.Fatalf("yandex.ru 应命中")
	}
	if res.CNAME != "" || !res.IP.Equal(net.ParseIP("213.180.193.56")) {
		t.Fatalf("Yandex 应重写为固定 IP, 得到 cname=%q ip=%v", res.CNAME, res.IP)
	}

	// AAAA 查询无对应记录 → NODATA
	res, ok = e.Lookup("yandex.ru", dns.TypeAAAA)
	if !ok || !res.NODATA {
		t.Fatalf("Yandex AAAA 查询应为 NODATA, 得到 ok=%v res=%+v", ok, res)
	}
}

// TestSafeSearchPerServiceToggle 校验服务商黑名单可单独关闭。
func TestSafeSearchPerServiceToggle(t *testing.T) {
	cfg := DefaultSafeSearchConfig()
	cfg.Enabled = true
	cfg.Disabled = []string{SafeSearchGoogle}
	e := NewSafeSearchEngine(cfg)

	if _, ok := e.Lookup("www.google.com", dns.TypeA); ok {
		t.Fatalf("已关闭的 Google 不应命中")
	}
	if _, ok := e.Lookup("www.bing.com", dns.TypeA); !ok {
		t.Fatalf("未关闭的 Bing 应命中")
	}
}

// TestSafeSearchQTypeScope 校验仅 A/AAAA/HTTPS 参与强制安全搜索。
func TestSafeSearchQTypeScope(t *testing.T) {
	cfg := DefaultSafeSearchConfig()
	cfg.Enabled = true
	e := NewSafeSearchEngine(cfg)

	for _, qt := range []uint16{dns.TypeA, dns.TypeAAAA, dns.TypeHTTPS} {
		if _, ok := e.Lookup("www.bing.com", qt); !ok {
			t.Fatalf("查询类型 %d 应命中", qt)
		}
	}
	for _, qt := range []uint16{dns.TypeMX, dns.TypeTXT, dns.TypeNS} {
		if _, ok := e.Lookup("www.bing.com", qt); ok {
			t.Fatalf("查询类型 %d 不应命中", qt)
		}
	}
}

// TestSafeSearchAllProvidersCovered 校验 7 家服务商均成功编译出规则。
func TestSafeSearchAllProvidersCovered(t *testing.T) {
	cfg := DefaultSafeSearchConfig()
	cfg.Enabled = true
	e := NewSafeSearchEngine(cfg)

	samples := map[string]string{
		SafeSearchBing:       "www.bing.com",
		SafeSearchDuckDuckGo: "duckduckgo.com",
		SafeSearchEcosia:     "www.ecosia.org",
		SafeSearchGoogle:     "www.google.com",
		SafeSearchPixabay:    "pixabay.com",
		SafeSearchYandex:     "ya.ru",
		SafeSearchYouTube:    "www.youtube.com",
	}
	for service, domain := range samples {
		res, ok := e.Lookup(domain, dns.TypeA)
		if !ok {
			t.Fatalf("服务商 %s 的样例域名 %s 未命中", service, domain)
		}
		if res.Service != service {
			t.Fatalf("域名 %s 应归属 %s, 得到 %s", domain, service, res.Service)
		}
	}
}

// TestSafeSearchConfigureHotSwap 校验运行时改配置即时生效。
func TestSafeSearchConfigureHotSwap(t *testing.T) {
	e := NewSafeSearchEngine(DefaultSafeSearchConfig())
	cfg := DefaultSafeSearchConfig()
	cfg.Enabled = true
	e.Configure(cfg)
	if _, ok := e.Lookup("www.google.com", dns.TypeA); !ok {
		t.Fatalf("热更新后应命中")
	}
	cfg.Enabled = false
	e.Configure(cfg)
	if _, ok := e.Lookup("www.google.com", dns.TypeA); ok {
		t.Fatalf("关闭后不应命中")
	}
}

// TestParseSafeSearchRuleLine 校验规则行解析容错。
func TestParseSafeSearchRuleLine(t *testing.T) {
	if _, ok := parseSafeSearchRuleLine("", SafeSearchGoogle); ok {
		t.Fatalf("空行不应解析成功")
	}
	if _, ok := parseSafeSearchRuleLine("! comment", SafeSearchGoogle); ok {
		t.Fatalf("注释行不应解析成功")
	}
	if _, ok := parseSafeSearchRuleLine("|www.google.com^$dnsrewrite=NOERROR;CNAME;", SafeSearchGoogle); ok {
		t.Fatalf("空重写目标不应解析成功")
	}
	r, ok := parseSafeSearchRuleLine("|www.google.com^$dnsrewrite=noerror;CNAME;forcesafesearch.google.com", SafeSearchGoogle)
	if !ok || r.domain != "www.google.com" || r.cname != "forcesafesearch.google.com." {
		t.Fatalf("正常规则解析异常: %+v ok=%v", r, ok)
	}
}
