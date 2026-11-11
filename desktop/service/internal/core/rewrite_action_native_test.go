package core

import (
	"testing"

	"github.com/miekg/dns"
)

func TestEncodeRewriteActionParseRequest(t *testing.T) {
	payload := encodeRewriteActionParseRequest("NOERROR;TXT;hello")

	want := []byte{rewritePayloadLayoutVersion}
	want = rewriteText(want, "NOERROR;TXT;hello")
	if string(payload) != string(want) {
		t.Fatalf("请求载荷 = %v, want %v", payload, want)
	}
}

func TestEncodeRewriteActionKeyRequest(t *testing.T) {
	payload := encodeRewriteActionKeyRequest(&RewriteAction{
		RCode:  dns.RcodeSuccess,
		RRType: dns.TypeA,
		Value:  "127.0.0.1",
	})
	want := []byte{rewritePayloadLayoutVersion, 0, 0, 0, 1, 0}
	want = rewriteText(want, "127.0.0.1")
	if string(payload) != string(want) {
		t.Fatalf("请求载荷 = %v, want %v", payload, want)
	}

	bare := encodeRewriteActionKeyRequest(&RewriteAction{Bare: true})
	want = []byte{rewritePayloadLayoutVersion, 1, 0, 0, 0, 0}
	want = rewriteText(want, "")
	if string(bare) != string(want) {
		t.Fatalf("裸形式载荷 = %v, want %v", bare, want)
	}
}

func TestDecodeRewriteAction(t *testing.T) {
	payload := []byte{rewritePayloadLayoutVersion, 0, 0, 0, 1, 0}
	payload = rewriteText(payload, "127.0.0.1")
	action, err := decodeRewriteAction(payload)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if action.Bare || action.RCode != dns.RcodeSuccess || action.RRType != dns.TypeA || action.Value != "127.0.0.1" {
		t.Fatalf("action = %+v", action)
	}

	bare := []byte{rewritePayloadLayoutVersion, 1, 5, 0, 0, 0}
	bare = rewriteText(bare, "ignored")
	action, err = decodeRewriteAction(bare)
	if err != nil {
		t.Fatalf("decode bare: %v", err)
	}
	if !action.Bare || action.RCode != dns.RcodeRefused || action.RRType != 0 {
		t.Fatalf("bare action = %+v", action)
	}
}

func TestDecodeRewriteActionKey(t *testing.T) {
	payload := []byte{rewritePayloadLayoutVersion}
	payload = rewriteText(payload, "0;1;127.0.0.1")
	key, err := decodeRewriteActionKey(payload)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if key != "0;1;127.0.0.1" {
		t.Fatalf("key = %q", key)
	}
}

func TestDecodeRewriteActionRejectsMismatchedArtifacts(t *testing.T) {
	// 布局版本不符
	if _, err := decodeRewriteAction([]byte{rewritePayloadLayoutVersion + 1}); err == nil {
		t.Fatal("expected a layout error")
	}
	// 未知的裸形式标志位
	unknown := []byte{rewritePayloadLayoutVersion, 2, 0, 0, 0, 0}
	unknown = rewriteText(unknown, "")
	if _, err := decodeRewriteAction(unknown); err == nil {
		t.Fatal("expected a bare-flag error")
	}
	// 尾随字节意味着两侧布局不一致
	trailing := []byte{rewritePayloadLayoutVersion, 0, 0, 0, 1, 0}
	trailing = rewriteText(trailing, "127.0.0.1")
	trailing = append(trailing, 0xEE)
	if _, err := decodeRewriteAction(trailing); err == nil {
		t.Fatal("expected a trailing-byte error")
	}
	// 键同理
	key := []byte{rewritePayloadLayoutVersion}
	key = rewriteText(key, "0;1;127.0.0.1")
	key = append(key, 0xEE)
	if _, err := decodeRewriteActionKey(key); err == nil {
		t.Fatal("expected a trailing-byte error")
	}
	if _, err := decodeRewriteActionKey(nil); err == nil {
		t.Fatal("expected a truncated payload error")
	}
}

// 归一化键由内核生成：等价写法必须得到同一个键，nil 动作沿用旧的空串行为
func TestRewriteActionKey(t *testing.T) {
	for _, tc := range []struct {
		in   *RewriteAction
		want string
	}{
		{&RewriteAction{Bare: true}, "bare"},
		{&RewriteAction{RCode: dns.RcodeSuccess, RRType: dns.TypeA, Value: "::ffff:127.0.0.1"}, "0;1;127.0.0.1"},
		{&RewriteAction{RCode: dns.RcodeSuccess, RRType: dns.TypeCNAME, Value: "Example.ORG."}, "0;5;example.org"},
		{&RewriteAction{RCode: dns.RcodeRefused}, "5;0;"},
	} {
		got, err := tc.in.key()
		if err != nil {
			t.Fatalf("key(%+v): %v", tc.in, err)
		}
		if got != tc.want {
			t.Fatalf("key(%+v) = %q, want %q", tc.in, got, tc.want)
		}
	}

	if key, err := (*RewriteAction)(nil).key(); err != nil || key != "" {
		t.Fatalf("nil action key = %q, %v", key, err)
	}
}
