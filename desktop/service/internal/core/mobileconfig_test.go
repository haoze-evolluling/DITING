package core

import (
	"encoding/xml"
	"strings"
	"testing"
)

// wellFormed 用标准库解析一遍，确认生成的 XML 真的能读。
//
// 不只是「跑完不报错」：每个键后面必须紧跟一个元素，否则就是出现
// 了裸文本——那种文件设备会直接判定为损坏。
func wellFormed(t *testing.T, data []byte) {
	t.Helper()
	dec := xml.NewDecoder(strings.NewReader(string(data)))
	// inKey 记录当前是否在 <key> 内部；expectValue 在 key 闭合后置位，
	// 用来要求下一个字符数据必须是空白的（真值应是一个元素）
	inKey, expectValue := false, false
	for {
		tok, err := dec.Token()
		if err != nil {
			if err.Error() == "EOF" {
				break
			}
			t.Fatalf("生成的 XML 不合法: %v", err)
		}
		switch el := tok.(type) {
		case xml.StartElement:
			if el.Name.Local == "key" {
				inKey = true
				continue
			}
			expectValue = false
		case xml.EndElement:
			if el.Name.Local == "key" {
				inKey = false
				expectValue = true
			}
		case xml.CharData:
			if !inKey && expectValue && strings.TrimSpace(string(el)) != "" {
				t.Fatalf("<key> 后出现了裸文本 %q，应为带标签的元素", strings.TrimSpace(string(el)))
			}
		}
	}
	if expectValue {
		t.Fatal("最后一个 <key> 没有对应的值")
	}
}

func TestBuildMobileConfig_HTTPS(t *testing.T) {
	data, err := BuildMobileConfig(MobileConfigOptions{
		ServerName: "dns.lan",
		ServerURL:  "https://dns.lan/dns-query",
		Protocol:   MobileConfigProtocolHTTPS,
		UUID:       "2f8a1d3e-4b5c-4d6e-8f90-1234567890ab",
	})
	if err != nil {
		t.Fatalf("生成失败: %v", err)
	}

	got := string(data)
	wellFormed(t, data)

	for _, want := range []string{
		`<plist version="1.0">`,
		`<string>com.apple.dnsSettings.managed</string>`,
		`<string>HTTPS</string>`,
		`<string>https://dns.lan/dns-query</string>`,
		`<string>dns.lan</string>`,
		`<string>2f8a1d3e-4b5c-4d6e-8f90-1234567890ab</string>`,
		`<string>Configuration</string>`,
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("输出缺少 %s\n%s", want, got)
		}
	}
	if !strings.HasPrefix(got, `<?xml version="1.0" encoding="UTF-8"?>`) {
		t.Fatal("应以 XML 声明开头")
	}
}

func TestBuildMobileConfig_TLS(t *testing.T) {
	data, err := BuildMobileConfig(MobileConfigOptions{
		ServerName: "dns.lan",
		Protocol:   MobileConfigProtocolTLS,
		UUID:       "2f8a1d3e-4b5c-4d6e-8f90-1234567890ab",
	})
	if err != nil {
		t.Fatalf("生成失败: %v", err)
	}
	got := string(data)
	wellFormed(t, data)

	if !strings.Contains(got, "<string>TLS</string>") {
		t.Fatalf("应带 TLS 协议标识\n%s", got)
	}
	// TLS 模式不该出现 DoH 的地址键
	if strings.Contains(got, "ServerURL") {
		t.Fatal("TLS 模式不应包含 ServerURL")
	}
}

func TestBuildMobileConfig_RequiresServerName(t *testing.T) {
	_, err := BuildMobileConfig(MobileConfigOptions{
		Protocol: MobileConfigProtocolHTTPS,
		ServerURL: "https://dns.lan/dns-query",
	})
	if err == nil {
		t.Fatal("缺服务器名应报错")
	}
}

func TestBuildMobileConfig_HTTPSRequiresURL(t *testing.T) {
	_, err := BuildMobileConfig(MobileConfigOptions{
		ServerName: "dns.lan",
		Protocol:   MobileConfigProtocolHTTPS,
	})
	if err == nil {
		t.Fatal("DoH 模式缺地址应报错")
	}

	// 非 https 的地址必须挡下：设备会静默忽略整条载荷
	_, err = BuildMobileConfig(MobileConfigOptions{
		ServerName: "dns.lan",
		Protocol:   MobileConfigProtocolHTTPS,
		ServerURL:  "http://dns.lan/dns-query",
	})
	if err == nil {
		t.Fatal("非 https 的地址应报错")
	}
}

func TestBuildMobileConfig_RejectsUnknownProtocol(t *testing.T) {
	_, err := BuildMobileConfig(MobileConfigOptions{
		ServerName: "dns.lan",
		Protocol:   "cleartext",
	})
	if err == nil {
		t.Fatal("未知协议应报错")
	}
}

// 服务器名里的 XML 保留字符必须被转义，否则整份文件无法解析
func TestBuildMobileConfig_EscapesXML(t *testing.T) {
	data, err := BuildMobileConfig(MobileConfigOptions{
		ServerName: `a&b<c>"d`,
		Protocol:   MobileConfigProtocolTLS,
	})
	if err != nil {
		t.Fatalf("生成失败: %v", err)
	}
	got := string(data)
	wellFormed(t, data)

	if strings.Contains(got, "a&b<c>") {
		t.Fatal("保留字符应被转义")
	}
	if !strings.Contains(got, "a&amp;b&lt;c&gt;&quot;d") {
		t.Fatalf("转义结果不符\n%s", got)
	}
}

func TestNewUUID(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 50; i++ {
		id, err := NewUUID()
		if err != nil {
			t.Fatalf("生成失败: %v", err)
		}
		if len(id) != 36 {
			t.Fatalf("UUID 长度应为 36，实得 %d (%s)", len(id), id)
		}
		if id[8] != '-' || id[13] != '-' || id[18] != '-' || id[23] != '-' {
			t.Fatalf("连字符位置不对: %s", id)
		}
		// 版本位必须为 4，变体位必须为 8/9/a/b
		if id[14] != '4' {
			t.Fatalf("版本位应为 4: %s", id)
		}
		if !strings.ContainsRune("89ab", rune(id[19])) {
			t.Fatalf("变体位不合法: %s", id)
		}
		if seen[id] {
			t.Fatalf("出现重复 UUID: %s", id)
		}
		seen[id] = true
	}
}

func TestEnsureEncryptedUUID(t *testing.T) {
	cfg := &EncryptedDNSConfig{}
	first, err := EnsureEncryptedUUID(cfg)
	if err != nil {
		t.Fatalf("生成失败: %v", err)
	}
	if cfg.UUID != first {
		t.Fatal("生成的 UUID 应写回配置")
	}

	// 再次调用必须返回同一个值：换了 UUID 设备会当成新描述文件
	second, err := EnsureEncryptedUUID(cfg)
	if err != nil {
		t.Fatalf("读取失败: %v", err)
	}
	if second != first {
		t.Fatalf("UUID 应保持固定，%q != %q", first, second)
	}

	if _, err := EnsureEncryptedUUID(nil); err == nil {
		t.Fatal("空配置应报错")
	}
}

func TestPlistStringAndInteger(t *testing.T) {
	if got := plistInteger(1); got != "<integer>1</integer>" {
		t.Fatalf("整数序列化不符: %s", got)
	}
	if got := plistString(""); got != "<string></string>" {
		t.Fatalf("空串应输出空元素: %s", got)
	}
}

// 控制字符会让整份 XML 无法解析，必须被丢弃
func TestEscapeXMLText_DropsControlChars(t *testing.T) {
	got := escapeXMLText("a\x00b\x1fc\td")
	if strings.ContainsAny(got, "\x00\x1f") {
		t.Fatalf("控制字符应被丢弃，实得 %q", got)
	}
	if got != "abc\td" {
		t.Fatalf("制表符以外的控制字符都应丢弃，实得 %q", got)
	}
}
