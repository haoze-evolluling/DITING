package dns

import "testing"

func TestClientIDFromServerName(t *testing.T) {
	cases := []struct {
		name   string
		host   string
		client string
		want   string
	}{
		{"完全一致表示未指定", "dns.lan", "dns.lan", ""},
		{"直接子域即 ClientID", "dns.lan", "phone.dns.lan", "phone"},
		{"大小写不敏感", "DNS.LAN", "PHONE.dns.lan", "phone"},
		{"服务器名带末尾点也应一致", "dns.lan.", "dns.lan", ""},
		{"客户端多带一级不算 ClientID", "dns.lan", "a.b.dns.lan", ""},
		{"无关联的名字不算", "dns.lan", "evil.example.com", ""},
		{"后缀相同但不是子域", "dns.lan", "xdns.lan", ""},
		{"未配置服务器名时不识别", "", "phone.dns.lan", ""},
		{"客户端未给 SNI 时不识别", "dns.lan", "", ""},
		{"子域标签含非法字符时拒绝", "dns.lan", "ph_one.dns.lan", ""},
		{"子域标签以连字符开头时拒绝", "dns.lan", "-phone.dns.lan", ""},
		{"子域标签以连字符结尾时拒绝", "dns.lan", "phone-.dns.lan", ""},
		{"中间连字符合法", "dns.lan", "my-phone.dns.lan", "my-phone"},
		{"数字标签合法", "dns.lan", "123.dns.lan", "123"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ClientIDFromServerName(tc.host, tc.client)
			if got != tc.want {
				t.Fatalf("ClientIDFromServerName(%q, %q) = %q，期望 %q",
					tc.host, tc.client, got, tc.want)
			}
		})
	}
}

func TestValidateClientID(t *testing.T) {
	valid := []string{"phone", "my-phone", "abc123", "A1"}
	for _, id := range valid {
		if err := ValidateClientID(id); err != nil {
			t.Fatalf("%q 应判为合法: %v", id, err)
		}
	}

	invalid := []string{"", "  ", "a_b", "a.b", "-a", "a-", "a b", "中文", "a/b"}
	for _, id := range invalid {
		if err := ValidateClientID(id); err == nil {
			t.Fatalf("%q 应判为非法", id)
		}
	}
}

// 超过 63 字节的标签在 DNS 里根本编不出来，必须在入口就挡住
func TestValidateClientIDRejectsTooLong(t *testing.T) {
	long := make([]byte, 64)
	for i := range long {
		long[i] = 'a'
	}
	if err := ValidateClientID(string(long)); err == nil {
		t.Fatal("64 字节的 ClientID 应被拒绝")
	}
	if err := ValidateClientID(string(long[:63])); err != nil {
		t.Fatalf("63 字节的 ClientID 应被接受: %v", err)
	}
}

// 65 字节的 ClientID 前缀本身超长，不应被当成合法身份识别出来
func TestClientIDFromServerNameTooLongPrefix(t *testing.T) {
	prefix := make([]byte, 64)
	for i := range prefix {
		prefix[i] = 'a'
	}
	if got := ClientIDFromServerName("dns.lan", string(prefix)+".dns.lan"); got != "" {
		t.Fatalf("超长子域标签不应识别为 ClientID，实得 %q", got)
	}
}

func TestApplyEncryptedClientIDSetsClientName(t *testing.T) {
	ctx := NewDNSContext(nil, nil, nil, "tcp-tls")
	applyEncryptedClientID(ctx, queryOrigin{
		Protocol:   "tcp-tls",
		ServerName: "tablet.dns.lan",
	}, "dns.lan")

	if ctx.ClientID != "tablet" {
		t.Fatalf("ClientID 应为 tablet，实得 %q", ctx.ClientID)
	}
	if v, ok := ctx.Get(attrClientID); !ok || v != "tablet" {
		t.Fatalf("ClientID 应写入属性表，实得 %v", v)
	}

	// 明文入口（无 SNI、无路径）不应产生任何 ClientID
	plain := NewDNSContext(nil, nil, nil, "udp")
	applyEncryptedClientID(plain, queryOrigin{Protocol: "udp"}, "")
	if plain.ClientID != "" {
		t.Fatalf("明文入口不应有 ClientID，实得 %q", plain.ClientID)
	}
}

// DoH 的路径 ClientID 优先于 SNI：路径是用户逐字填进客户端的，
// 而 SNI 往往是客户端自己挑的默认值
func TestApplyEncryptedClientIDPrefersPath(t *testing.T) {
	ctx := NewDNSContext(nil, nil, nil, "doh")
	applyEncryptedClientID(ctx, queryOrigin{
		Protocol:     "doh",
		ServerName:   "sni.dns.lan",
		PathClientID: "laptop",
	}, "dns.lan")

	if ctx.ClientID != "laptop" {
		t.Fatalf("应以路径 ClientID 为准，实得 %q", ctx.ClientID)
	}
}
