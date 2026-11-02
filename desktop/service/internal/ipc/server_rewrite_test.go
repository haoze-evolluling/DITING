package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

type rewriteMockController struct {
	mockController
	rules   []core.RewriteRule
	clients []core.ClientInfo
	ecs     core.ECSConfig
}

func (m *rewriteMockController) GetRewriteRules(ctx context.Context) ([]core.RewriteRule, error) {
	return m.rules, nil
}

func (m *rewriteMockController) AddRewriteRule(ctx context.Context, rule core.RewriteRule) error {
	m.rules = append(m.rules, rule)
	return nil
}

func (m *rewriteMockController) DeleteRewriteRule(ctx context.Context, domain string) error {
	var remaining []core.RewriteRule
	for _, r := range m.rules {
		if r.Domain != domain {
			remaining = append(remaining, r)
		}
	}
	m.rules = remaining
	return nil
}

func (m *rewriteMockController) ConfigureRewrite(ctx context.Context, req ConfigureRewriteRequest) error {
	if req.Rules != nil {
		m.rules = *req.Rules
	}
	return nil
}

func (m *rewriteMockController) GetClients(ctx context.Context) ([]core.ClientInfo, error) {
	return m.clients, nil
}

func (m *rewriteMockController) ConfigureClientAlias(ctx context.Context, req ConfigureClientAliasRequest) error {
	m.clients = append(m.clients, core.ClientInfo{IP: req.IP, Name: req.Name})
	return nil
}

func (m *rewriteMockController) ConfigureECS(ctx context.Context, req ConfigureECSRequest) error {
	if req.Enabled != nil {
		m.ecs.Enabled = *req.Enabled
	}
	if req.StripECS != nil {
		m.ecs.StripECS = *req.StripECS
	}
	if req.CustomSubnet != nil {
		m.ecs.CustomSubnet = *req.CustomSubnet
	}
	return nil
}

func TestIPC_RewriteAndClientEndpoints(t *testing.T) {
	mockCtrl := &rewriteMockController{
		rules: []core.RewriteRule{
			{Domain: "nas.lan", IPs: []string{"192.168.1.100"}},
		},
		clients: []core.ClientInfo{
			{IP: "192.168.1.50", Name: "Storage-NAS"},
		},
	}

	server := NewServer("127.0.0.1:0", "secret-token", mockCtrl)

	// 1. GET /api/v1/dns/rewrite/rules
	req := httptest.NewRequest(http.MethodGet, "/api/v1/dns/rewrite/rules", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleRewriteRules(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var res Response[[]core.RewriteRule]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil || len(res.Data) != 1 {
		t.Fatalf("expected 1 rule returned, got: %v", res)
	}

	// 2. POST /api/v1/dns/rewrite/rules (添加新规则)
	addPayload := core.RewriteRule{
		Domain: "*.dev",
		IPs:    []string{"127.0.0.1"},
	}
	body, _ := json.Marshal(addPayload)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/dns/rewrite/rules", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer secret-token")
	w = httptest.NewRecorder()
	server.handleRewriteRules(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if len(mockCtrl.rules) != 2 {
		t.Fatalf("expected 2 rules in mock, got %d", len(mockCtrl.rules))
	}

	// 3. DELETE /api/v1/dns/rewrite/rules?domain=nas.lan
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/dns/rewrite/rules?domain=nas.lan", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w = httptest.NewRecorder()
	server.handleRewriteRules(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if len(mockCtrl.rules) != 1 || mockCtrl.rules[0].Domain != "*.dev" {
		t.Fatalf("expected only *.dev rule remaining")
	}

	// 4. GET /api/v1/clients
	req = httptest.NewRequest(http.MethodGet, "/api/v1/clients", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w = httptest.NewRecorder()
	server.handleClients(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var clientRes Response[[]core.ClientInfo]
	if err := json.Unmarshal(w.Body.Bytes(), &clientRes); err != nil || len(clientRes.Data) != 1 {
		t.Fatalf("unexpected client response: %v", clientRes)
	}

	// 5. POST /api/v1/clients/alias
	aliasReq := ConfigureClientAliasRequest{
		IP:   "192.168.1.88",
		Name: "Printer",
	}
	body, _ = json.Marshal(aliasReq)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/clients/alias", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer secret-token")
	w = httptest.NewRecorder()
	server.handleClientAlias(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if len(mockCtrl.clients) != 2 {
		t.Fatalf("expected 2 clients in mock")
	}

	// 6. POST /api/v1/dns/ecs/configure
	enable := true
	strip := true
	subnet := "10.0.0.0/24"
	ecsReq := ConfigureECSRequest{
		Enabled:      &enable,
		StripECS:     &strip,
		CustomSubnet: &subnet,
	}
	body, _ = json.Marshal(ecsReq)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/dns/ecs/configure", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer secret-token")
	w = httptest.NewRecorder()
	server.handleECSConfigure(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if !mockCtrl.ecs.Enabled || !mockCtrl.ecs.StripECS || mockCtrl.ecs.CustomSubnet != "10.0.0.0/24" {
		t.Fatalf("unexpected ECS config in mock: %+v", mockCtrl.ecs)
	}
}
