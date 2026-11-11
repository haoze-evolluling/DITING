package core

import (
	"encoding/base64"
	"encoding/binary"
	"strings"
	"testing"
)

// buildStamp 按 DNS Stamps 规范拼装印章，用于构造测试向量
func buildStamp(proto byte, props uint64, parts ...[]byte) string {
	bin := make([]byte, 9)
	bin[0] = proto
	binary.LittleEndian.PutUint64(bin[1:9], props)
	for _, p := range parts {
		bin = append(bin, p...)
	}
	return "sdns://" + base64.RawURLEncoding.EncodeToString(bin)
}

func lp(s string) []byte {
	b := []byte{byte(len(s))}
	return append(b, []byte(s)...)
}

// vlp 拼装 VLP 列表，除最后一项外均置 0x80。
//
// 空列表必须输出单个 0x00 终止字节，这是规范中"无指纹/无引导 IP"的表示，
// 少了它读取器会把后续字段的长度字节误当作本列表的长度。
func vlp(items ...[]byte) []byte {
	if len(items) == 0 {
		return []byte{0x00}
	}
	var out []byte
	for i, it := range items {
		vlen := len(it)
		if i < len(items)-1 {
			vlen |= 0x80
		}
		out = append(out, byte(vlen))
		out = append(out, it...)
	}
	return out
}

func TestParseServerStamp_Plain(t *testing.T) {
	// 端口为默认 53 时应被省略，解析后补回
	stampStr := buildStamp(0x00, 0, lp("9.9.9.9"))

	stamp, err := ParseServerStamp(stampStr)
	if err != nil {
		t.Fatalf("parse plain stamp: %v", err)
	}
	if stamp.Proto != StampProtoPlain {
		t.Fatalf("proto = %v, want Plain", stamp.Proto)
	}
	if stamp.ServerAddrStr != "9.9.9.9:53" {
		t.Fatalf("server addr = %q, want 9.9.9.9:53", stamp.ServerAddrStr)
	}
	proto, err := stamp.Protocol()
	if err != nil || proto != ProtocolPlain {
		t.Fatalf("Protocol() = %v, %v", proto, err)
	}
}

func TestParseServerStamp_PlainWithProps(t *testing.T) {
	props := uint64(StampPropDNSSEC | StampPropNoLog)
	stampStr := buildStamp(0x00, props, lp("1.1.1.1:5353"))

	stamp, err := ParseServerStamp(stampStr)
	if err != nil {
		t.Fatalf("parse plain stamp: %v", err)
	}
	if !stamp.Props.Has(StampPropDNSSEC) || !stamp.Props.Has(StampPropNoLog) {
		t.Fatalf("props = %b, want DNSSEC|NoLog", uint64(stamp.Props))
	}
	if stamp.Props.Has(StampPropNoFilter) {
		t.Fatal("props unexpectedly has NoFilter")
	}
	if stamp.ServerAddrStr != "1.1.1.1:5353" {
		t.Fatalf("server addr = %q", stamp.ServerAddrStr)
	}
}

func TestParseServerStamp_DoH(t *testing.T) {
	hash := make([]byte, 32)
	for i := range hash {
		hash[i] = byte(i)
	}

	stampStr := buildStamp(0x02, uint64(StampPropNoFilter),
		lp("1.1.1.1"), // 直连地址
		vlp(hash),     // 证书指纹
		lp("cloudflare-dns.com"),
		lp("/dns-query"),
		vlp([]byte("1.1.1.1"), []byte("1.0.0.1")), // 引导 IP
	)

	stamp, err := ParseServerStamp(stampStr)
	if err != nil {
		t.Fatalf("parse DoH stamp: %v", err)
	}
	if stamp.Proto != StampProtoDoH {
		t.Fatalf("proto = %v, want DoH", stamp.Proto)
	}
	if stamp.ProviderName != "cloudflare-dns.com" {
		t.Fatalf("provider = %q", stamp.ProviderName)
	}
	if stamp.Path != "/dns-query" {
		t.Fatalf("path = %q", stamp.Path)
	}
	if stamp.ServerAddrStr != "1.1.1.1:443" {
		t.Fatalf("server addr = %q, want 1.1.1.1:443", stamp.ServerAddrStr)
	}
	if len(stamp.Hashes) != 1 || len(stamp.Hashes[0]) != 32 {
		t.Fatalf("hashes = %d", len(stamp.Hashes))
	}
	if len(stamp.BootstrapIPs) != 2 || stamp.BootstrapIPs[0] != "1.1.1.1" {
		t.Fatalf("bootstrap IPs = %v", stamp.BootstrapIPs)
	}

	if got := stamp.URL(); got != "https://cloudflare-dns.com/dns-query" {
		t.Fatalf("URL() = %q", got)
	}
	if got := stamp.Server(); got != "cloudflare-dns.com" {
		t.Fatalf("Server() = %q, want cloudflare-dns.com", got)
	}

	pins, err := stamp.Pins()
	if err != nil {
		t.Fatalf("Pins(): %v", err)
	}
	if len(pins) != 1 {
		t.Fatalf("pins = %d", len(pins))
	}
	if !equalBytes(pins[0].Sha256, hash) {
		t.Fatal("pin bytes mismatch")
	}
}

func TestParseServerStamp_DoHDefaultsPath(t *testing.T) {
	// 路径为空时应回落到 /dns-query
	stampStr := buildStamp(0x02, 0, lp(""), vlp(), lp("dns.example.com"), lp(""))

	stamp, err := ParseServerStamp(stampStr)
	if err != nil {
		t.Fatalf("parse DoH stamp: %v", err)
	}
	if stamp.ServerAddrStr != "" {
		t.Fatalf("server addr = %q, want empty", stamp.ServerAddrStr)
	}
	if got := stamp.URL(); got != "https://dns.example.com/dns-query" {
		t.Fatalf("URL() = %q", got)
	}
}

func TestParseServerStamp_DoTAndDoQ(t *testing.T) {
	hash := make([]byte, 32)
	dotStr := buildStamp(0x03, 0, lp("1.1.1.1"), vlp(hash), lp("one.one.one.one"))
	doqStr := buildStamp(0x04, 0, lp("1.1.1.1"), vlp(hash), lp("one.one.one.one"))

	dot, err := ParseServerStamp(dotStr)
	if err != nil {
		t.Fatalf("parse DoT stamp: %v", err)
	}
	if dot.Proto != StampProtoTLS {
		t.Fatalf("proto = %v, want TLS", dot.Proto)
	}
	if got := dot.Server(); got != "one.one.one.one" {
		t.Fatalf("DoT Server() = %q", got)
	}
	if proto, _ := dot.Protocol(); proto != ProtocolDoT {
		t.Fatalf("DoT Protocol() = %v", proto)
	}

	doq, err := ParseServerStamp(doqStr)
	if err != nil {
		t.Fatalf("parse DoQ stamp: %v", err)
	}
	if doq.Proto != StampProtoDoQ {
		t.Fatalf("proto = %v, want DoQ", doq.Proto)
	}
	if proto, _ := doq.Protocol(); proto != ProtocolDoQ {
		t.Fatalf("DoQ Protocol() = %v", proto)
	}
}

func TestParseServerStamp_UnsupportedProtocols(t *testing.T) {
	cases := map[string]byte{
		"DNSCrypt":        0x01,
		"oDoH target":     0x05,
		"DNSCrypt relay":  0x81,
		"oDoH relay":      0x85,
		"unknown version": 0x7f,
	}
	for name, proto := range cases {
		stampStr := buildStamp(proto, 0, lp("1.1.1.1"), vlp(make([]byte, 32)), lp("example.com"), lp("/q"))
		if _, err := ParseServerStamp(stampStr); err == nil {
			t.Errorf("%s: expected error, got nil", name)
		}
	}
}

func TestParseServerStamp_Malformed(t *testing.T) {
	hash32 := make([]byte, 32)

	cases := map[string]string{
		"empty":             "",
		"bad scheme":        "https://example.com",
		"bad base64":        "sdns://!!!not-base64!!!",
		"truncated props":   "sdns://" + base64.RawURLEncoding.EncodeToString([]byte{0x00, 0x01}),
		"garbage after":     buildStamp(0x00, 0, lp("9.9.9.9"), []byte{0x00}),
		"non-ip addr":       buildStamp(0x00, 0, lp("not-an-ip")),
		"empty port":        buildStamp(0x00, 0, lp("9.9.9.9:")),
		"port out of range": buildStamp(0x00, 0, lp("9.9.9.9:99999")),
		"short hash":        buildStamp(0x03, 0, lp("1.1.1.1"), vlp(make([]byte, 16)), lp("example.com")),
		"empty hostname":    buildStamp(0x03, 0, lp("1.1.1.1"), vlp(hash32), lp("")),
	}

	for name, stampStr := range cases {
		if _, err := ParseServerStamp(stampStr); err == nil {
			t.Errorf("%s: expected error, got nil", name)
		}
	}
}

func TestParseServerStamp_TruncatedVLP(t *testing.T) {
	// 声明 0x80 表示还有下一项，但数据在此结束
	bin := []byte{0x03}
	bin = append(bin, make([]byte, 8)...)
	bin = append(bin, lp("1.1.1.1")...)
	bin = append(bin, 0x80|32)
	bin = append(bin, make([]byte, 32)...)
	bin = append(bin, 0x80|32) // 还有下一项，但已无数据
	stampStr := "sdns://" + base64.RawURLEncoding.EncodeToString(bin)

	if _, err := ParseServerStamp(stampStr); err == nil {
		t.Fatal("expected error for truncated VLP, got nil")
	}
}

func TestParseServerStamp_IPv6Addr(t *testing.T) {
	stampStr := buildStamp(0x00, 0, lp("[2606:4700:4700::1111]"))

	stamp, err := ParseServerStamp(stampStr)
	if err != nil {
		t.Fatalf("parse IPv6 stamp: %v", err)
	}
	if stamp.ServerAddrStr != "[2606:4700:4700::1111]:53" {
		t.Fatalf("server addr = %q", stamp.ServerAddrStr)
	}
}

func TestExpandStamp(t *testing.T) {
	hash := make([]byte, 32)
	for i := range hash {
		hash[i] = 0xAB
	}
	stampStr := buildStamp(0x02, 0, lp("1.1.1.1"), vlp(hash), lp("cloudflare-dns.com"), lp("/dns-query"))

	prov, pin, _, err := ExpandStamp(stampStr)
	if err != nil {
		t.Fatalf("ExpandStamp: %v", err)
	}
	if prov.Protocol != ProtocolDoH {
		t.Fatalf("protocol = %v", prov.Protocol)
	}
	if prov.URL != "https://cloudflare-dns.com/dns-query" {
		t.Fatalf("url = %q", prov.URL)
	}
	if pin == nil || !equalBytes(pin.Sha256, hash) {
		t.Fatal("pin mismatch")
	}

	// 不支持的协议必须报错，而不是静默降级
	if _, _, _, err := ExpandStamp(buildStamp(0x01, 0, lp("1.1.1.1"), vlp(hash), lp("example.com"))); err == nil {
		t.Fatal("expected error for DNSCrypt stamp")
	}
}

func TestStampFromProvider(t *testing.T) {
	got, field := stampFromProvider(ProviderConfig{Server: "sdns://abc"})
	if got != "sdns://abc" || field != stampFieldServer {
		t.Fatalf("server field stamp = %q, field = %q", got, field)
	}

	got, field = stampFromProvider(ProviderConfig{URL: "sdns:abc"})
	if got != "sdns:abc" || field != stampFieldURL {
		t.Fatalf("url field stamp = %q, field = %q", got, field)
	}

	if got, _ := stampFromProvider(ProviderConfig{Server: "1.1.1.1:53"}); got != "" {
		t.Fatalf("plain server wrongly detected as stamp: %q", got)
	}
}

func TestBuildProviderInputs_ExplicitOverridesStamp(t *testing.T) {
	hash := make([]byte, 32)
	stampStr := buildStamp(0x03, 0, lp("1.1.1.1"), vlp(hash), lp("one.one.one.one"))

	inputs, err := buildProviderInputs([]ProviderConfig{
		{ID: "p1", Server: stampStr},
	})
	if err != nil {
		t.Fatalf("buildProviderInputs: %v", err)
	}
	if inputs[0].cfg.Protocol != ProtocolDoT {
		t.Fatalf("stamp-derived protocol = %v", inputs[0].cfg.Protocol)
	}
	if inputs[0].cfg.Server != "one.one.one.one" {
		t.Fatalf("stamp-derived server = %q", inputs[0].cfg.Server)
	}
	if inputs[0].pin == nil {
		t.Fatal("expected pin from stamp")
	}
}

func TestBuildProviderInputs_ExplicitWeightWins(t *testing.T) {
	hash := make([]byte, 32)
	stampStr := buildStamp(0x03, 0, lp("1.1.1.1"), vlp(hash), lp("one.one.one.one"))

	inputs, err := buildProviderInputs([]ProviderConfig{
		{ID: "p1", Server: stampStr, Weight: 5},
	})
	if err != nil {
		t.Fatalf("buildProviderInputs: %v", err)
	}
	if inputs[0].cfg.Weight != 5 {
		t.Fatalf("weight = %d, want 5", inputs[0].cfg.Weight)
	}

	// 显式指定的协议应覆盖印章推导出的协议
	inputs, err = buildProviderInputs([]ProviderConfig{
		{ID: "p2", Server: stampStr, Protocol: ProtocolDoQ},
	})
	if err != nil {
		t.Fatalf("buildProviderInputs: %v", err)
	}
	if inputs[0].cfg.Protocol != ProtocolDoQ {
		t.Fatalf("protocol = %v, want DOQ", inputs[0].cfg.Protocol)
	}
}

func TestConfigureWithStampProvider(t *testing.T) {
	hash := make([]byte, 32)
	for i := range hash {
		hash[i] = byte(i * 3)
	}
	stampStr := buildStamp(0x02, 0, lp("1.1.1.1"), vlp(hash), lp("cloudflare-dns.com"), lp("/dns-query"))

	r, err := NewResolver(ResolverConfig{
		Mode: "single",
		Providers: []ProviderConfig{
			{ID: "stamped", Server: stampStr},
		},
	})
	if err != nil {
		t.Fatalf("NewResolver with stamp: %v", err)
	}
	defer func() { _ = r.Shutdown() }()

	stats := r.GetProviderStats()
	if len(stats) != 1 {
		t.Fatalf("providers = %d", len(stats))
	}
	if stats[0].Protocol != ProtocolDoH {
		t.Fatalf("protocol = %v", stats[0].Protocol)
	}
	if stats[0].URL != "https://cloudflare-dns.com/dns-query" {
		t.Fatalf("url = %q", stats[0].URL)
	}
}

func TestBuildPinLookup(t *testing.T) {
	pinA, _ := CertPinFromRaw(make([]byte, 32))
	pinB, _ := ParseCertPin(strings.Repeat("ab", 32))

	providers := []*ConfiguredProvider{
		{Server: "one.one.one.one:853", Pin: pinA},
		{Server: "dns.example.com:443", Pin: pinB},
		{Server: "plain.example.com:53", Pin: nil},
	}

	lookup := buildPinLookup(providers)
	if lookup == nil {
		t.Fatal("lookup is nil")
	}
	if got := lookup("one.one.one.one"); got != pinA {
		t.Fatal("pin A not resolved by hostname")
	}
	if got := lookup("one.one.one.one:853"); got != pinA {
		t.Fatal("pin A not resolved with port")
	}
	if got := lookup("ONE.ONE.ONE.ONE"); got != pinA {
		t.Fatal("pin A not resolved case-insensitively")
	}
	if got := lookup("plain.example.com"); got != nil {
		t.Fatal("unpinned host must resolve to nil")
	}
	if got := lookup("unknown.example.com"); got != nil {
		t.Fatal("unknown host must resolve to nil")
	}
}

func TestBuildPinLookup_Empty(t *testing.T) {
	if lookup := buildPinLookup([]*ConfiguredProvider{{Server: "1.1.1.1:53"}}); lookup != nil {
		t.Fatal("expected nil lookup when no pins configured")
	}
}

func TestBuildProviderInputs_ExplicitPinOverridesStampPin(t *testing.T) {
	stampHash := make([]byte, 32)
	for i := range stampHash {
		stampHash[i] = 0x11
	}
	stampStr := buildStamp(0x03, 0, lp("1.1.1.1"), vlp(stampHash), lp("one.one.one.one"))

	// 未填显式指纹时应采用印章指纹
	inputs, err := buildProviderInputs([]ProviderConfig{{ID: "p1", Server: stampStr}})
	if err != nil {
		t.Fatalf("buildProviderInputs: %v", err)
	}
	if inputs[0].pin == nil || !equalBytes(inputs[0].pin.Sha256, stampHash) {
		t.Fatal("expected stamp pin to be used")
	}

	// 显式指纹必须覆盖印章指纹
	explicit := strings.Repeat("cd", 32)
	inputs, err = buildProviderInputs([]ProviderConfig{{ID: "p2", Server: stampStr, Pin: explicit}})
	if err != nil {
		t.Fatalf("buildProviderInputs: %v", err)
	}
	want, _ := ParseCertPin(explicit)
	if inputs[0].pin == nil || !equalBytes(inputs[0].pin.Sha256, want.Sha256) {
		t.Fatal("explicit pin must override the stamp pin")
	}

	// 非法指纹必须被拒绝，而不是静默忽略
	if _, err := buildProviderInputs([]ProviderConfig{{ID: "p3", Server: stampStr, Pin: "not-hex"}}); err == nil {
		t.Fatal("expected error for malformed explicit pin")
	}
}

func TestConfigureWithExplicitPin(t *testing.T) {
	explicit := strings.Repeat("7e", 32)
	r, err := NewResolver(ResolverConfig{
		Mode: "single",
		Providers: []ProviderConfig{
			{ID: "pinned", Protocol: ProtocolDoT, Server: "dns.example.com:853", Pin: explicit},
		},
	})
	if err != nil {
		t.Fatalf("NewResolver: %v", err)
	}
	defer func() { _ = r.Shutdown() }()

	want, _ := ParseCertPin(explicit)
	if r.doh == nil || r.dot == nil {
		t.Fatal("resolvers not initialized")
	}

	// 固定表应能按主机名解析出该指纹
	lookup := r.PinLookup()
	if lookup == nil {
		t.Fatal("pin lookup is nil")
	}
	if got := lookup("dns.example.com"); got == nil || !equalBytes(got.Sha256, want.Sha256) {
		t.Fatal("explicit pin not registered in lookup table")
	}
}
