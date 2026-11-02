package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

type securityMockController struct {
	mockController
	accessCalled      bool
	rateLimitCalled   bool
	dns64Called       bool
	unqualifiedCalled bool
	privacyCalled     bool
	lastPrivacyReq    ConfigurePrivacyRequest
	rebindCalled      bool
	lastRebindReq     ConfigureRebindRequest
	hostsCalled       bool
	lastHostsReq      ConfigureHostsRequest
}

func (m *securityMockController) ConfigureAccess(ctx context.Context, req ConfigureAccessRequest) error {
	m.accessCalled = true
	return nil
}

func (m *securityMockController) ConfigureRateLimit(ctx context.Context, req ConfigureRateLimitRequest) error {
	m.rateLimitCalled = true
	return nil
}

func (m *securityMockController) ConfigureDNS64(ctx context.Context, req ConfigureDNS64Request) error {
	m.dns64Called = true
	return nil
}

func (m *securityMockController) ConfigureBlockUnqualified(ctx context.Context, req ConfigureBlockUnqualifiedRequest) error {
	m.unqualifiedCalled = true
	return nil
}

func (m *securityMockController) ConfigurePrivacy(ctx context.Context, req ConfigurePrivacyRequest) error {
	m.privacyCalled = true
	m.lastPrivacyReq = req
	return nil
}

func (m *securityMockController) ConfigureRebind(ctx context.Context, req ConfigureRebindRequest) error {
	m.rebindCalled = true
	m.lastRebindReq = req
	return nil
}

func (m *securityMockController) ConfigureHosts(ctx context.Context, req ConfigureHostsRequest) error {
	m.hostsCalled = true
	m.lastHostsReq = req
	return nil
}

func TestServer_SecurityAndPrivacyEndpoints(t *testing.T) {
	mockCtrl := &securityMockController{}
	token := "test-token"
	server := NewServer("127.0.0.1:0", token, mockCtrl)
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() {
		_ = server.Shutdown(context.Background())
	}()

	baseURL := "http://" + server.Addr()

	// 1. POST /api/v1/dns/privacy/configure
	bTrue := true
	bFalse := false
	pad256 := 256
	privPayload := ConfigurePrivacyRequest{
		BlockPrivatePTR: &bFalse,
		BlockIPv6:       &bTrue,
		BlockECH:        &bTrue,
		EDNSPadding:     &pad256,
	}
	body, _ := json.Marshal(privPayload)

	req, err := http.NewRequest(http.MethodPost, baseURL+"/api/v1/dns/privacy/configure", bytes.NewReader(body))
	if err != nil {
		t.Fatalf("create request failed: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST privacy configure failed: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200, got %d", resp.StatusCode)
	}
	if !mockCtrl.privacyCalled {
		t.Fatal("expected ConfigurePrivacy to be called")
	}
	if mockCtrl.lastPrivacyReq.BlockPrivatePTR == nil || *mockCtrl.lastPrivacyReq.BlockPrivatePTR != false {
		t.Errorf("unexpected BlockPrivatePTR: %v", mockCtrl.lastPrivacyReq.BlockPrivatePTR)
	}
	if mockCtrl.lastPrivacyReq.BlockIPv6 == nil || *mockCtrl.lastPrivacyReq.BlockIPv6 != true {
		t.Errorf("unexpected BlockIPv6: %v", mockCtrl.lastPrivacyReq.BlockIPv6)
	}
	if mockCtrl.lastPrivacyReq.BlockECH == nil || *mockCtrl.lastPrivacyReq.BlockECH != true {
		t.Errorf("unexpected BlockECH: %v", mockCtrl.lastPrivacyReq.BlockECH)
	}
	if mockCtrl.lastPrivacyReq.EDNSPadding == nil || *mockCtrl.lastPrivacyReq.EDNSPadding != 256 {
		t.Errorf("unexpected EDNSPadding: %v", mockCtrl.lastPrivacyReq.EDNSPadding)
	}

	// 2. GET method should fail with 405
	reqGet, _ := http.NewRequest(http.MethodGet, baseURL+"/api/v1/dns/privacy/configure", nil)
	reqGet.Header.Set("Authorization", "Bearer "+token)
	respGet, err := http.DefaultClient.Do(reqGet)
	if err != nil {
		t.Fatalf("GET failed: %v", err)
	}
	defer respGet.Body.Close()
	if respGet.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("expected status 405 for GET, got %d", respGet.StatusCode)
	}

	// 3. POST /api/v1/dns/unqualified/configure
	unqualPayload := ConfigureBlockUnqualifiedRequest{BlockUnqualified: true}
	unqualBody, _ := json.Marshal(unqualPayload)
	reqUnqual, _ := http.NewRequest(http.MethodPost, baseURL+"/api/v1/dns/unqualified/configure", bytes.NewReader(unqualBody))
	reqUnqual.Header.Set("Authorization", "Bearer "+token)
	respUnqual, err := http.DefaultClient.Do(reqUnqual)
	if err != nil {
		t.Fatalf("POST unqualified failed: %v", err)
	}
	defer respUnqual.Body.Close()
	if respUnqual.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200, got %d", respUnqual.StatusCode)
	}
	if !mockCtrl.unqualifiedCalled {
		t.Fatal("expected ConfigureBlockUnqualified to be called")
	}

	// 4. POST /api/v1/dns/rebind/configure
	rebindPayload := ConfigureRebindRequest{
		Enabled:        &bTrue,
		AllowedDomains: []string{"localhost", ".lan", "nas.local"},
	}
	rebindBody, _ := json.Marshal(rebindPayload)
	reqRebind, _ := http.NewRequest(http.MethodPost, baseURL+"/api/v1/dns/rebind/configure", bytes.NewReader(rebindBody))
	reqRebind.Header.Set("Authorization", "Bearer "+token)
	respRebind, err := http.DefaultClient.Do(reqRebind)
	if err != nil {
		t.Fatalf("POST rebind failed: %v", err)
	}
	defer respRebind.Body.Close()
	if respRebind.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200 for rebind, got %d", respRebind.StatusCode)
	}
	if !mockCtrl.rebindCalled {
		t.Fatal("expected ConfigureRebind to be called")
	}
	if len(mockCtrl.lastRebindReq.AllowedDomains) != 3 {
		t.Fatalf("expected 3 allowed domains, got %v", mockCtrl.lastRebindReq.AllowedDomains)
	}

	// 5. POST /api/v1/dns/hosts/configure
	hostsPayload := ConfigureHostsRequest{
		Enabled:       &bTrue,
		UseSystemHost: &bTrue,
	}
	hostsBody, _ := json.Marshal(hostsPayload)
	reqHosts, _ := http.NewRequest(http.MethodPost, baseURL+"/api/v1/dns/hosts/configure", bytes.NewReader(hostsBody))
	reqHosts.Header.Set("Authorization", "Bearer "+token)
	respHosts, err := http.DefaultClient.Do(reqHosts)
	if err != nil {
		t.Fatalf("POST hosts failed: %v", err)
	}
	defer respHosts.Body.Close()
	if respHosts.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200 for hosts, got %d", respHosts.StatusCode)
	}
	if !mockCtrl.hostsCalled {
		t.Fatal("expected ConfigureHosts to be called")
	}
}
