package dns

import (
	"net"
	"testing"

	"github.com/miekg/dns"
)

func TestEDNS0_SetAndGetOption(t *testing.T) {
	msg := new(dns.Msg)
	msg.SetQuestion("example.com.", dns.TypeA)

	if SetEdns0Option(nil, new(dns.EDNS0_EDE)) {
		t.Fatal("expected false for nil msg")
	}
	if SetEdns0Option(msg, nil) {
		t.Fatal("expected false for nil opt")
	}

	ede := &dns.EDNS0_EDE{
		InfoCode:  dns.ExtendedErrorCodeBlocked,
		ExtraText: "DITING: Blocked by test rule",
	}

	ok := SetEdns0Option(msg, ede)
	if !ok {
		t.Fatal("failed to set EDNS0 option")
	}

	opt := msg.IsEdns0()
	if opt == nil {
		t.Fatal("expected OPT record in msg")
	}

	retrieved := GetEdns0Option[*dns.EDNS0_EDE](msg)
	if retrieved == nil {
		t.Fatal("expected to retrieve EDE option")
	}

	if retrieved.InfoCode != dns.ExtendedErrorCodeBlocked {
		t.Fatalf("expected info code %d, got %d", dns.ExtendedErrorCodeBlocked, retrieved.InfoCode)
	}
	if retrieved.ExtraText != "DITING: Blocked by test rule" {
		t.Fatalf("unexpected extra text: %s", retrieved.ExtraText)
	}

	// Replacement of same option code
	newEde := &dns.EDNS0_EDE{
		InfoCode:  dns.ExtendedErrorCodeProhibited,
		ExtraText: "Replaced",
	}
	SetEdns0Option(msg, newEde)
	opt = msg.IsEdns0()
	if len(opt.Option) != 1 {
		t.Fatalf("expected 1 option after replacement, got %d", len(opt.Option))
	}
	retrieved = GetEdns0Option[*dns.EDNS0_EDE](msg)
	if retrieved.ExtraText != "Replaced" {
		t.Fatalf("expected Replaced, got %s", retrieved.ExtraText)
	}
}

func TestSetEDE_HelperAndTruncate(t *testing.T) {
	msg := new(dns.Msg)
	msg.SetQuestion("example.com.", dns.TypeA)

	longText := ""
	for i := 0; i < 300; i++ {
		longText += "a"
	}
	SetEDE(msg, dns.ExtendedErrorCodeNetworkError, longText)

	opt := GetEdns0Option[*dns.EDNS0_EDE](msg)
	if opt == nil {
		t.Fatal("expected EDE option")
	}
	if len(opt.ExtraText) != MaxEDETextLength {
		t.Fatalf("expected truncated length %d, got %d", MaxEDETextLength, len(opt.ExtraText))
	}

	// Test UTF-8 multi-byte truncate
	chineseText := "谛听DNS安全防御系统测试很长很长很长很长很长很长很长很长很长很长很长很长"
	truncated := TruncateText(chineseText, 10)
	if len(truncated) > 10 {
		t.Fatalf("truncated string exceeded 10 bytes: len=%d", len(truncated))
	}
}

func TestPadMessage(t *testing.T) {
	// 边界测试：nil 报文与非正数块大小
	if PadMessage(nil, 128) {
		t.Fatal("expected false for nil msg")
	}
	msg := new(dns.Msg)
	msg.SetQuestion("example.com.", dns.TypeA)
	if PadMessage(msg, 0) {
		t.Fatal("expected false for blockSize <= 0")
	}

	// 1. 块大小 128 填充验证
	if !PadMessage(msg, 128) {
		t.Fatal("failed to pad message to 128 bytes")
	}
	packed, err := msg.Pack()
	if err != nil {
		t.Fatalf("pack padded message failed: %v", err)
	}
	if len(packed)%128 != 0 {
		t.Fatalf("expected packed len to be multiple of 128, got %d", len(packed))
	}
	if len(packed) < 128 {
		t.Fatalf("expected packed len >= 128, got %d", len(packed))
	}

	// 2. 幂等性测试：再次使用块大小 128 填充，必须去除旧填充重新计算，长度依然严格整除
	if !PadMessage(msg, 128) {
		t.Fatal("failed second padding")
	}
	packed2, err := msg.Pack()
	if err != nil {
		t.Fatalf("pack re-padded message failed: %v", err)
	}
	if len(packed2)%128 != 0 {
		t.Fatalf("expected packed2 len to be multiple of 128, got %d", len(packed2))
	}
	if len(packed2) != len(packed) {
		t.Fatalf("expected idempotent length %d, got %d", len(packed), len(packed2))
	}

	// 3. 切换至 468 块大小测试 (RFC 8467 §4.1)
	if !PadMessage(msg, 468) {
		t.Fatal("failed 468 padding")
	}
	packed468, err := msg.Pack()
	if err != nil {
		t.Fatalf("pack 468-padded message failed: %v", err)
	}
	if len(packed468)%468 != 0 {
		t.Fatalf("expected packed468 len to be multiple of 468, got %d", len(packed468))
	}
}

func TestStripECH(t *testing.T) {
	// 边界测试：nil 报文
	if StripECH(nil) {
		t.Fatal("expected false for nil msg")
	}

	msg := new(dns.Msg)
	msg.SetQuestion("example.com.", dns.TypeHTTPS)

	// 1. 无 ECH 的常规 A 记录响应
	msg.Answer = append(msg.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: "example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
	})
	if StripECH(msg) {
		t.Fatal("expected false when no HTTPS/SVCB ECH is present")
	}

	// 2. 包含 ECH 参数的 HTTPS 记录
	httpsRR := &dns.HTTPS{
		SVCB: dns.SVCB{
			Hdr:      dns.RR_Header{Name: "example.com.", Rrtype: dns.TypeHTTPS, Class: dns.ClassINET, Ttl: 300},
			Priority: 1,
			Target:   ".",
			Value: []dns.SVCBKeyValue{
				&dns.SVCBAlpn{Alpn: []string{"h2", "h3"}},
				&dns.SVCBECHConfig{ECH: []byte{0x01, 0x02, 0x03, 0x04}},
			},
		},
	}
	msg.Answer = append(msg.Answer, httpsRR)

	if !StripECH(msg) {
		t.Fatal("expected true when ECH parameter was stripped")
	}

	// 验证 ECH 参数已被移除，而 ALPN 参数保留
	foundECH := false
	foundAlpn := false
	for _, kv := range httpsRR.Value {
		if kv.Key() == dns.SVCB_ECHCONFIG {
			foundECH = true
		}
		if _, ok := kv.(*dns.SVCBECHConfig); ok {
			foundECH = true
		}
		if kv.Key() == dns.SVCB_ALPN {
			foundAlpn = true
		}
	}

	if foundECH {
		t.Fatal("ECH config was not stripped from HTTPS RR")
	}
	if !foundAlpn {
		t.Fatal("ALPN parameter was unintentionally removed")
	}

	// 3. 再次剥离应返回 false（无变更）
	if StripECH(msg) {
		t.Fatal("expected false on second strip")
	}
}

func TestStripIPv6Hints(t *testing.T) {
	// 1. 空报文处理
	if StripIPv6Hints(nil) {
		t.Fatal("expected false for nil msg")
	}

	msg := new(dns.Msg)
	msg.SetQuestion("example.com.", dns.TypeHTTPS)

	// 2. 无 HTTPS/SVCB 记录
	if StripIPv6Hints(msg) {
		t.Fatal("expected false when no HTTPS/SVCB records present")
	}

	// 3. 构造包含 ipv4hint 与 ipv6hint 的 HTTPS 记录
	httpsRR := &dns.HTTPS{
		SVCB: dns.SVCB{
			Hdr:      dns.RR_Header{Name: "example.com.", Rrtype: dns.TypeHTTPS, Class: dns.ClassINET, Ttl: 300},
			Priority: 1,
			Target:   ".",
			Value: []dns.SVCBKeyValue{
				&dns.SVCBAlpn{Alpn: []string{"h2", "h3"}},
				&dns.SVCBIPv4Hint{Hint: []net.IP{net.ParseIP("1.1.1.1")}},
				&dns.SVCBIPv6Hint{Hint: []net.IP{net.ParseIP("2606:4700::1111")}},
			},
		},
	}
	msg.Answer = append(msg.Answer, httpsRR)

	if !StripIPv6Hints(msg) {
		t.Fatal("expected true when stripping ipv6hint from HTTPS RR")
	}

	hasIPv6Hint := false
	hasIPv4Hint := false
	for _, kv := range httpsRR.Value {
		if kv.Key() == dns.SVCB_IPV6HINT {
			hasIPv6Hint = true
		}
		if kv.Key() == dns.SVCB_IPV4HINT {
			hasIPv4Hint = true
		}
	}
	if hasIPv6Hint {
		t.Fatal("ipv6hint was not stripped")
	}
	if !hasIPv4Hint {
		t.Fatal("ipv4hint was erroneously stripped")
	}

	// 4. 第二次剥离应返回 false（幂等性）
	if StripIPv6Hints(msg) {
		t.Fatal("expected false on second strip")
	}
}

func TestPadMessage_BoundaryAndLarge(t *testing.T) {
	msg := new(dns.Msg)
	msg.SetQuestion("huge.example.com.", dns.TypeA)

	// 填充超大 TXT 记录逼近 65535 字节
	chunk := make([]string, 250)
	for i := range chunk {
		chunk[i] = "abcdefghijklmnopqrstuvwxyz0123456789"
	}
	for i := 0; i < 7; i++ {
		msg.Extra = append(msg.Extra, &dns.TXT{
			Hdr: dns.RR_Header{Name: "huge.example.com.", Rrtype: dns.TypeTXT, Class: dns.ClassINET, Ttl: 300},
			Txt: chunk,
		})
	}

	// 验证超大报文下 PadMessage 不会导致 panic 或破坏结构
	_ = PadMessage(msg, 128)
	if opt := msg.IsEdns0(); opt == nil {
		t.Fatal("expected OPT record to be present")
	}
}

