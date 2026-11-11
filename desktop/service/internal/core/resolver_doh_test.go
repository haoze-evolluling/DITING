package core

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func TestDoHResolver_Basic(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if r.Header.Get("Content-Type") != "application/dns-message" {
			http.Error(w, "bad content type", http.StatusBadRequest)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		var queryMsg dns.Msg
		if err := queryMsg.Unpack(body); err != nil {
			http.Error(w, "unpack query failed", http.StatusBadRequest)
			return
		}

		respMsg := new(dns.Msg)
		respMsg.SetReply(&queryMsg)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 93.184.216.34", queryMsg.Question[0].Name))
		respMsg.Answer = append(respMsg.Answer, rr)

		respBytes, _ := respMsg.Pack()
		w.Header().Set("Content-Type", "application/dns-message")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(respBytes)
	}))
	defer ts.Close()

	doh := NewDoHResolver(nil)
	defer doh.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("example.org")
	resp, err := doh.Exchange(ctx, rawQuery, ts.URL)
	if err != nil {
		t.Fatalf("doh Exchange failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("unpack doh response failed: %v", err)
	}
	if len(respMsg.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %d", len(respMsg.Answer))
	}
}

func TestDoHResolver_Errors(t *testing.T) {
	doh := NewDoHResolver(nil)
	defer doh.Close()

	// 空 URL 报错
	_, err := doh.Exchange(context.Background(), makeTestDNSQuery("example.com"), "")
	if err == nil {
		t.Fatalf("expected error on empty doh URL")
	}

	// 403 错误
	ts403 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusForbidden)
	}))
	defer ts403.Close()

	_, err = doh.Exchange(context.Background(), makeTestDNSQuery("example.com"), ts403.URL)
	if err == nil {
		t.Fatalf("expected error on HTTP 403, got nil")
	}

	// 500 错误
	ts500 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer ts500.Close()

	_, err = doh.Exchange(context.Background(), makeTestDNSQuery("example.com"), ts500.URL)
	if err == nil {
		t.Fatalf("expected error on HTTP 500, got nil")
	}

	// 响应报文截断/过短
	tsShort := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte{1, 2, 3}) // 不足 12 字节
	}))
	defer tsShort.Close()

	_, err = doh.Exchange(context.Background(), makeTestDNSQuery("example.com"), tsShort.URL)
	if err == nil {
		t.Fatalf("expected error on short response body, got nil")
	}
}
