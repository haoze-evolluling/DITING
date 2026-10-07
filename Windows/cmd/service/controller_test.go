package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/haoze-evolluling/diting/windows/internal/config"
	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/haoze-evolluling/diting/windows/internal/ipc"
	miekgdns "github.com/miekg/dns"
)

func TestController_TestUpstream_DoH(t *testing.T) {
	// 启动一个模拟 DoH 服务器
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if r.Header.Get("Content-Type") != "application/dns-message" {
			http.Error(w, "invalid content type", http.StatusBadRequest)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		reqMsg := new(miekgdns.Msg)
		if err := reqMsg.Unpack(body); err != nil {
			http.Error(w, "bad dns wireformat", http.StatusBadRequest)
			return
		}

		respMsg := new(miekgdns.Msg)
		respMsg.SetReply(reqMsg)
		respMsg.Response = true
		respMsg.Answer = append(respMsg.Answer, &miekgdns.A{
			Hdr: miekgdns.RR_Header{
				Name:   reqMsg.Question[0].Name,
				Rrtype: miekgdns.TypeA,
				Class:  miekgdns.ClassINET,
				Ttl:    300,
			},
			A: []byte{223, 5, 5, 5},
		})

		wire, err := respMsg.Pack()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/dns-message")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(wire)
	}))
	defer ts.Close()

	prg := &program{
		cfg: config.DefaultConfig(),
	}

	// 1. 成功测试
	res, err := prg.TestUpstream(context.Background(), ipc.TestUpstreamRequest{
		Protocol: "DOH",
		URL:      ts.URL + "/dns-query",
	})
	if err != nil {
		t.Fatalf("TestUpstream unexpected err: %v", err)
	}
	if !res.Success {
		t.Fatalf("expected success, got error: %s", res.Error)
	}
	if res.LatencyMs <= 0 {
		t.Errorf("expected positive latency, got %f", res.LatencyMs)
	}

	// 2. 状态码错误测试
	errorTs := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "upstream rate limited", http.StatusTooManyRequests)
	}))
	defer errorTs.Close()

	errRes, err := prg.TestUpstream(context.Background(), ipc.TestUpstreamRequest{
		Protocol: "DOH",
		URL:      errorTs.URL,
	})
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if errRes.Success {
		t.Errorf("expected failure on 429 status code, got success")
	}
}

func TestController_TestUpstream_EmptyServer(t *testing.T) {
	prg := &program{
		cfg: config.DefaultConfig(),
	}

	res, err := prg.TestUpstream(context.Background(), ipc.TestUpstreamRequest{})
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if res.Success || res.Error != "未指定服务器地址" {
		t.Errorf("expected error for empty server, got res=%+v", res)
	}
}

func TestController_ConfigureUpstream(t *testing.T) {
	cfg := config.DefaultConfig()
	resolver, err := core.NewResolver(cfg.Upstream)
	if err != nil {
		t.Fatalf("NewResolver failed: %v", err)
	}

	prg := &program{
		cfg:      cfg,
		resolver: resolver,
	}

	err = prg.ConfigureUpstream(context.Background(), ipc.ConfigureUpstreamRequest{
		Mode: "SINGLE",
		Providers: []core.ProviderConfig{
			{ID: "node-1", Protocol: core.ProtocolPlain, Server: "223.5.5.5:53"},
		},
	})
	if err != nil {
		t.Fatalf("ConfigureUpstream failed: %v", err)
	}

	if prg.cfg.Upstream.Mode != "SINGLE" {
		t.Errorf("expected mode SINGLE, got %s", prg.cfg.Upstream.Mode)
	}
	if len(prg.cfg.Upstream.Providers) != 1 {
		t.Errorf("expected 1 provider")
	}
}

func TestController_CacheMethods(t *testing.T) {
	cfg := config.DefaultConfig()
	cache := core.NewDNSCache(cfg.Cache)
	defer cache.Close()

	prg := &program{
		cfg:   cfg,
		cache: cache,
	}

	ctx := context.Background()

	// 1. GetCacheStats
	st, err := prg.GetCacheStats(ctx)
	if err != nil || !st.Enabled {
		t.Fatalf("GetCacheStats failed: err=%v, st=%+v", err, st)
	}

	// 2. Put 条目并通过 controller 查询
	req := new(miekgdns.Msg)
	req.SetQuestion("cached-ctrl.com.", miekgdns.TypeA)
	resp := new(miekgdns.Msg)
	resp.SetReply(req)
	resp.Answer = []miekgdns.RR{
		&miekgdns.A{
			Hdr: miekgdns.RR_Header{Name: "cached-ctrl.com.", Rrtype: miekgdns.TypeA, Class: miekgdns.ClassINET, Ttl: 60},
			A:   []byte{1, 2, 3, 4},
		},
	}
	cache.Put(req, resp)

	// 3. GetCacheEntries
	entries, err := prg.GetCacheEntries(ctx, "cached-ctrl", 10)
	if err != nil || entries.Total != 1 {
		t.Fatalf("GetCacheEntries failed: err=%v, entries=%+v", err, entries)
	}

	// 4. GetCacheTopDomains
	top, err := prg.GetCacheTopDomains(ctx, 5)
	if err != nil || len(top) != 1 {
		t.Fatalf("GetCacheTopDomains failed: err=%v, top=%+v", err, top)
	}

	// 5. GetCacheConfig & UpdateCacheConfig
	cCfg, err := prg.GetCacheConfig(ctx)
	if err != nil || !cCfg.Enabled {
		t.Fatalf("GetCacheConfig failed: err=%v, cCfg=%+v", err, cCfg)
	}

	cCfg.MaxTTLSeconds = 1200
	if err := prg.UpdateCacheConfig(ctx, *cCfg); err != nil {
		t.Fatalf("UpdateCacheConfig failed: %v", err)
	}
	if prg.cfg.Cache.MaxTTLSeconds != 1200 {
		t.Errorf("expected MaxTTLSeconds 1200, got %d", prg.cfg.Cache.MaxTTLSeconds)
	}

	// 6. ClearCache
	if err := prg.ClearCache(ctx); err != nil {
		t.Fatalf("ClearCache failed: %v", err)
	}
	stAfter, _ := prg.GetCacheStats(ctx)
	if stAfter.EntryCount != 0 {
		t.Errorf("expected 0 entries after clear, got %d", stAfter.EntryCount)
	}
}
