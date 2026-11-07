//go:build cgo

// config_native_test.go covers the Go half of the configuration kernel (rust/diting-config-core).
//
// The kernel's own corpus (`rust/diting-config-core/tests/corpus.rs`) pins every table against the
// pre-migration Go implementation; these cases prove the Go wiring: the request/response layout, the
// values the `Engine` ends up storing, and the degraded paths.

package tunnel

import "testing"

func TestConfigPayloadLayout(t *testing.T) {
	if configPayloadLayoutVersion != 1 {
		t.Fatalf("layout version = %d", configPayloadLayoutVersion)
	}
	payload := newConfigPayload(configOpRewrite).int64(2).text("a").text("bc")
	want := []byte{configOpRewrite}
	want = append(want, 2, 0, 0, 0, 0, 0, 0, 0)
	want = append(want, 1, 0, 0, 0, 'a')
	want = append(want, 2, 0, 0, 0, 'b', 'c')
	if string(payload.body) != string(want) {
		t.Fatalf("payload = %v, want %v", payload.body, want)
	}

	reader := configPayloadReader{payload: want[9:]}
	if text, ok := reader.text(); !ok || text != "a" {
		t.Fatalf("first text = %q, %v", text, ok)
	}
	if text, ok := reader.text(); !ok || text != "bc" {
		t.Fatalf("second text = %q, %v", text, ok)
	}
	if !reader.atEnd() {
		t.Fatal("reader did not consume the payload")
	}
	// A length that runs past the end must fail instead of reading into the next field.
	truncated := configPayloadReader{payload: []byte{8, 0, 0, 0, 'a'}}
	if _, ok := truncated.text(); ok {
		t.Fatal("a text longer than the payload was accepted")
	}
}

func TestNormalizeDNSConfigReturnsTheKernelValues(t *testing.T) {
	providers := []dnsProviderConfig{
		{ID: "p1", Protocol: "plain", Server: "8.8.8.8:53", Weight: 2},
		{ID: "p2", Protocol: "doh", URL: "https://dns.google/dns-query"},
	}
	normalized, err := normalizeDNSConfig("race", "nxdomain", dynamicBlockConfig{Enabled: true}, providers)
	if err != nil {
		t.Fatalf("normalize DNS config: %v", err)
	}
	if normalized.mode != "parallel_race" {
		t.Fatalf("mode = %q", normalized.mode)
	}
	if normalized.blockResponse != ResponseNXDomain {
		t.Fatalf("block response = %v", normalized.blockResponse)
	}
	if !normalized.dynamic.Enabled {
		t.Fatal("dynamic response should stay enabled")
	}
	if normalized.dynamic.RequestThreshold != 5 ||
		normalized.dynamic.WindowSeconds != 60 ||
		normalized.dynamic.NXDomainSeconds != 300 {
		t.Fatalf("dynamic defaults = %+v", normalized.dynamic)
	}
	if len(normalized.providers) != 2 {
		t.Fatalf("providers = %+v", normalized.providers)
	}
	// The upper-cased name is what `statsKey` and the log lines use.
	if normalized.providers[0].Protocol != "PLAIN" || normalized.providers[0].Weight != 2 {
		t.Fatalf("first provider = %+v", normalized.providers[0])
	}
	if normalized.providers[1].Protocol != "DOH" || normalized.providers[1].URL == "" {
		t.Fatalf("second provider = %+v", normalized.providers[1])
	}
}

func TestNormalizeDNSConfigRejectsTheSameThings(t *testing.T) {
	single := []dnsProviderConfig{{Protocol: "PLAIN", Server: "1.1.1.1:53"}}
	for _, testCase := range []struct {
		mode      string
		providers []dnsProviderConfig
		want      string
	}{
		{"nope", single, `unsupported DNS mode "nope"`},
		{"race", nil, "DNS config has no providers"},
		{"single", append(single, single...), "single DNS mode requires exactly one provider"},
		{"race", []dnsProviderConfig{{Protocol: "PLAIN", Server: "1.1.1.1"}},
			`provider 0: invalid PLAIN endpoint "1.1.1.1": address 1.1.1.1: missing port in address`},
		{"race", []dnsProviderConfig{{Protocol: "hyper", Server: "1.1.1.1:53"}},
			`provider 0: unsupported protocol "HYPER"`},
		{"race", []dnsProviderConfig{{Protocol: "DOH", URL: "http://dns.google/q"}},
			`provider 0: invalid DOH URL "http://dns.google/q"`},
	} {
		_, err := normalizeDNSConfig(testCase.mode, "", dynamicBlockConfig{}, testCase.providers)
		if err == nil || err.Error() != testCase.want {
			t.Errorf("%s / %+v: error = %v, want %q", testCase.mode, testCase.providers, err, testCase.want)
		}
	}
}

func TestValueTablesGoThroughTheKernel(t *testing.T) {
	if got := ParseProtocol("doh"); got != ProtocolDoH {
		t.Fatalf("ParseProtocol(doh) = %v", got)
	}
	if got := ParseProtocol("DOT"); got != ProtocolDoT {
		t.Fatalf("ParseProtocol(DOT) = %v", got)
	}
	if got := ParseProtocol("unknown"); got != ProtocolPlain {
		t.Fatalf("ParseProtocol(unknown) = %v", got)
	}
	if got := ParseResponseType("NXDOMAIN"); got != ResponseNXDomain {
		t.Fatalf("ParseResponseType(NXDOMAIN) = %v", got)
	}
	// Case-sensitive, exactly as before: the config path upper-cases on its own.
	if got := ParseResponseType("nxdomain"); got != ResponseCustomIP {
		t.Fatalf("ParseResponseType(nxdomain) = %v", got)
	}
	if got := ParseResponseType("NODATA"); got != ResponseNoData {
		t.Fatalf("ParseResponseType(NODATA) = %v", got)
	}
}

func TestParseDoQURL(t *testing.T) {
	for _, testCase := range []struct {
		url  string
		host string
		port string
	}{
		{"quic://dns.adguard.com:8853", "dns.adguard.com", "8853"},
		{"https://dns.adguard.com/dns-query", "dns.adguard.com", "853"},
		{"doq://[2606:4700::1111]:853", "2606:4700::1111", "853"},
		{"dns.adguard.com", "dns.adguard.com", "853"},
	} {
		host, port := parseDoQURL(testCase.url)
		if host != testCase.host || port != testCase.port {
			t.Errorf("parseDoQURL(%q) = (%q, %q), want (%q, %q)",
				testCase.url, host, port, testCase.host, testCase.port)
		}
	}
}

func TestNormalizeDomain(t *testing.T) {
	for _, testCase := range []struct{ in, out string }{
		{"Example.COM", "example.com"},
		{" example.com. ", "example.com"},
		{"example.com..", "example.com."},
		{".", ""},
		{"  ", ""},
	} {
		if got := normalizeDomainNative(testCase.in); got != testCase.out {
			t.Errorf("normalizeDomainNative(%q) = %q, want %q", testCase.in, got, testCase.out)
		}
	}
}

func TestClassifyRewriteTargets(t *testing.T) {
	entry := classifyRewriteTargetsNative([]string{"5.6.7.8", "9.9.9.9", "::1", "Example.COM."})
	if entry == nil {
		t.Fatal("expected an entry")
	}
	if entry.ip4.String() != "5.6.7.8" || entry.ip6.String() != "::1" || entry.cname != "example.com" {
		t.Fatalf("entry = %+v", entry)
	}
	if entry := classifyRewriteTargetsNative([]string{"  ", ""}); entry != nil {
		t.Fatalf("blank targets must be dropped, got %+v", entry)
	}
}

// The rewrite table keeps working through the kernel: string and array values, suffix matching,
// case folding and the CNAME-only lookup the MITM redirect path uses.
func TestSetRewriteRulesThroughTheKernel(t *testing.T) {
	engine := NewEngine()
	engine.SetRewriteRules(`{
		"Example.COM.": "1.2.3.4",
		"cname.example": ["9.9.9.9", "::1", "Target.Example."],
		"broken.example": 42,
		"empty.example": "",
		"  ": "1.1.1.1"
	}`)

	if got := engine.rewriteIP("www.example.com", true); got == nil || got.String() != "1.2.3.4" {
		t.Fatalf("subdomain rewrite = %v", got)
	}
	if got := engine.rewriteIP("example.com", false); got != nil {
		t.Fatalf("IPv6 rewrite for an IPv4-only entry = %v", got)
	}
	if got := engine.rewriteIP("cname.example", true); got == nil || got.String() != "9.9.9.9" {
		t.Fatalf("array rewrite = %v", got)
	}
	if got := engine.rewriteIP("cname.example", false); got == nil || got.String() != "::1" {
		t.Fatalf("array IPv6 rewrite = %v", got)
	}
	if got := engine.rewriteCNAME("cname.example"); got != "target.example" {
		t.Fatalf("cname = %q", got)
	}
	if got := engine.rewriteIP("broken.example", true); got != nil {
		t.Fatalf("a non-string value must be dropped, got %v", got)
	}
	if got := engine.rewriteIP("empty.example", true); got != nil {
		t.Fatalf("an empty value must be dropped, got %v", got)
	}

	// The stored table is keyed by the normalized domain.
	if len(engine.rewriteRules) != 2 {
		t.Fatalf("table holds %d entries, want 2", len(engine.rewriteRules))
	}
	if _, ok := engine.rewriteRules["example.com"]; !ok {
		t.Fatalf("keys = %v", engine.rewriteRules)
	}

	engine.SetRewriteRules("")
	if len(engine.rewriteRules) != 0 {
		t.Fatalf("empty content must clear the table, got %d entries", len(engine.rewriteRules))
	}
}
