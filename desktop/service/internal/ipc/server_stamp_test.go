package ipc

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// buildTestStamp 按 DNS Stamps 规范拼装印章，构造测试向量
func buildTestStamp(proto byte, props uint64, parts ...[]byte) string {
	bin := make([]byte, 9)
	bin[0] = proto
	binary.LittleEndian.PutUint64(bin[1:9], props)
	for _, p := range parts {
		bin = append(bin, p...)
	}
	return "sdns://" + base64.RawURLEncoding.EncodeToString(bin)
}

func stampLP(s string) []byte {
	return append([]byte{byte(len(s))}, []byte(s)...)
}

func TestIPC_ParseStamp_DoH(t *testing.T) {
	hash := make([]byte, 32)
	for i := range hash {
		hash[i] = 0x5A
	}
	stampStr := buildTestStamp(0x02, uint64(3),
		stampLP("1.1.1.1"),
		append([]byte{32}, hash...),
		stampLP("cloudflare-dns.com"),
		stampLP("/dns-query"),
	)

	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	body, _ := json.Marshal(ParseStampRequest{Stamp: stampStr})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/upstream/stamp", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleParseStamp(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var res Response[ParseStampResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success {
		t.Fatalf("unexpected response: %+v", res)
	}
	if res.Data.Protocol != "DOH" {
		t.Fatalf("protocol = %q", res.Data.Protocol)
	}
	if res.Data.URL != "https://cloudflare-dns.com/dns-query" {
		t.Fatalf("url = %q", res.Data.URL)
	}
	if res.Data.ProviderName != "cloudflare-dns.com" {
		t.Fatalf("provider = %q", res.Data.ProviderName)
	}
	if res.Data.ServerAddr != "1.1.1.1:443" {
		t.Fatalf("serverAddr = %q", res.Data.ServerAddr)
	}
	if res.Data.Pin == "" || !strings.HasPrefix(res.Data.Pin, "5A:5A:") {
		t.Fatalf("pin = %q", res.Data.Pin)
	}
	if !res.Data.Props.DNSSEC || !res.Data.Props.NoLog {
		t.Fatalf("props = %+v", res.Data.Props)
	}
	if res.Data.Props.NoFilter {
		t.Fatalf("noFilter should be false: %+v", res.Data.Props)
	}
}

func TestIPC_ParseStamp_DoQDefaults(t *testing.T) {
	stampStr := buildTestStamp(0x04, 0,
		stampLP("1.1.1.1"),
		[]byte{0x00}, // 无指纹
		stampLP("one.one.one.one"),
	)

	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	body, _ := json.Marshal(ParseStampRequest{Stamp: stampStr})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/upstream/stamp", bytes.NewReader(body))
	w := httptest.NewRecorder()
	server.handleParseStamp(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var res Response[ParseStampResponse]
	_ = json.Unmarshal(w.Body.Bytes(), &res)
	if res.Data.Protocol != "DOQ" {
		t.Fatalf("protocol = %q", res.Data.Protocol)
	}
	if res.Data.URL != "" {
		t.Fatalf("DoQ must not carry a URL, got %q", res.Data.URL)
	}
	if res.Data.Pin != "" {
		t.Fatalf("expected empty pin, got %q", res.Data.Pin)
	}
}

func TestIPC_ParseStamp_Rejects(t *testing.T) {
	hash := make([]byte, 32)
	cases := map[string]string{
		"not a stamp":  "https://example.com/dns-query",
		"bad base64":   "sdns://@@@",
		"dnscrypt":     buildTestStamp(0x01, 0, stampLP("1.1.1.1"), append([]byte{32}, hash...), stampLP("example.com")),
		"odoh":         buildTestStamp(0x05, 0, stampLP("example.com"), stampLP("/q")),
		"bad hostname": buildTestStamp(0x03, 0, stampLP("1.1.1.1"), []byte{0x00}, stampLP("")),
	}

	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	for name, stampStr := range cases {
		body, _ := json.Marshal(ParseStampRequest{Stamp: stampStr})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/upstream/stamp", bytes.NewReader(body))
		w := httptest.NewRecorder()
		server.handleParseStamp(w, req)

		if w.Code == http.StatusOK {
			t.Errorf("%s: expected failure, got 200: %s", name, w.Body.String())
		}
	}
}

func TestIPC_ParseStamp_MethodNotAllowed(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/upstream/stamp", nil)
	w := httptest.NewRecorder()
	server.handleParseStamp(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestIPC_ParseStamp_RequiresAuth(t *testing.T) {
	// 路由需经 withAuth 包装：无凭证请求必须被拒
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	body, _ := json.Marshal(ParseStampRequest{Stamp: "sdns://"})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/upstream/stamp", bytes.NewReader(body))
	req.RemoteAddr = "203.0.113.7:12345"
	w := httptest.NewRecorder()

	mux := http.NewServeMux()
	server.registerRoutes(mux)
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", w.Code, w.Body.String())
	}
}
