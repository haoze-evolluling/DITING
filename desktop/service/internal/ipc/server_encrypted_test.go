package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// encMockController 覆盖 C1 的加密 DNS 配置与证书操作
type encMockController struct {
	mockController
	status     *EncryptedDNSStatusResponse
	failStatus bool
	failWrite  bool
	genReqs    []GenerateCertRequest
	importReqs []ImportCertRequest
}

func (m *encMockController) GetEncryptedDNS(ctx context.Context) (*EncryptedDNSStatusResponse, error) {
	if m.failStatus {
		return nil, errEncryptedTestFailure
	}
	if m.status != nil {
		return m.status, nil
	}
	return &EncryptedDNSStatusResponse{
		Config:         core.DefaultEncryptedDNSConfig(),
		DefaultDoTPort: core.DefaultDoTPort,
		DefaultDoHPort: core.DefaultDoHPort,
		DefaultDoQPort: core.DefaultDoQPort,
		DefaultDoHPath: core.DefaultDoHPath,
	}, nil
}

func (m *encMockController) ConfigureEncryptedDNS(ctx context.Context, req ConfigureEncryptedDNSRequest) error {
	if m.failWrite {
		return errEncryptedTestFailure
	}
	return nil
}

func (m *encMockController) GenerateEncryptedCert(ctx context.Context, req GenerateCertRequest) error {
	if m.failWrite {
		return errEncryptedTestFailure
	}
	m.genReqs = append(m.genReqs, req)
	return nil
}

func (m *encMockController) ImportEncryptedCert(ctx context.Context, req ImportCertRequest) error {
	if m.failWrite {
		return errEncryptedTestFailure
	}
	m.importReqs = append(m.importReqs, req)
	return nil
}

var errEncryptedTestFailure = errors.New("encrypted dns unavailable")

func callEncrypted(t *testing.T, srv *Server, path, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body == "" {
		reader = bytes.NewReader(nil)
	} else {
		reader = bytes.NewReader([]byte(body))
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()

	switch {
	case strings.HasSuffix(path, "/status"):
		srv.handleEncryptedDNSStatus(w, req)
	case strings.HasSuffix(path, "/configure"):
		srv.handleEncryptedDNSConfigure(w, req)
	case strings.HasSuffix(path, "/cert/generate"):
		srv.handleEncryptedCertGenerate(w, req)
	case strings.HasSuffix(path, "/cert/import"):
		srv.handleEncryptedCertImport(w, req)
	}
	return w
}

const (
	pathEncStatus   = "/api/v1/encrypted/dns/status"
	pathEncConfig   = "/api/v1/encrypted/dns/configure"
	pathEncGenerate = "/api/v1/encrypted/dns/cert/generate"
	pathEncImport   = "/api/v1/encrypted/dns/cert/import"
)

func TestServer_EncryptedStatus(t *testing.T) {
	cfg := core.DefaultEncryptedDNSConfig()
	cfg.Enabled = true
	cfg.DoTEnabled = true
	ctrl := &encMockController{status: &EncryptedDNSStatusResponse{
		Config: cfg,
		Cert: core.CertInfo{
			Source:      core.CertSourceSelfSigned,
			Subject:     "CN=dns.lan",
			Loaded:      true,
			SelfSigned:  true,
			Fingerprint: "AB:CD",
		},
		CertDir:        `C:\ProgramData\DITING\certs`,
		DefaultDoTPort: core.DefaultDoTPort,
		DefaultDoHPort: core.DefaultDoHPort,
		DefaultDoQPort: core.DefaultDoQPort,
		DefaultDoHPath: core.DefaultDoHPath,
	}}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callEncrypted(t, srv, pathEncStatus, http.MethodGet, "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}

	var res Response[*EncryptedDNSStatusResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("unexpected response: %+v", res)
	}
	if !res.Data.Cert.Loaded || !res.Data.Cert.SelfSigned {
		t.Fatalf("证书摘要不符: %+v", res.Data.Cert)
	}
	if res.Data.DefaultDoHPort != 443 {
		t.Fatalf("默认端口应回传: %d", res.Data.DefaultDoHPort)
	}
}

func TestServer_EncryptedStatusError(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &encMockController{failStatus: true})
	if w := callEncrypted(t, srv, pathEncStatus, http.MethodGet, ""); w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", w.Code)
	}
}

func TestServer_EncryptedStatusMethodNotAllowed(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &encMockController{})
	if w := callEncrypted(t, srv, pathEncStatus, http.MethodPost, ""); w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", w.Code)
	}
}

func TestServer_EncryptedConfigure(t *testing.T) {
	ctrl := &encMockController{}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	body := `{"enabled":true,"dotEnabled":true,"dohPath":"dns-query","dotPort":8853}`
	w := callEncrypted(t, srv, pathEncConfig, http.MethodPost, body)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}

	var res Response[*EncryptedDNSStatusResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	// 更新后必须回传完整状态：端口与路径会被归一化，
	// 界面需要看到真正生效的值
	if !res.Success || res.Data == nil {
		t.Fatalf("POST 应回传更新后的状态: %+v", res)
	}
}

func TestServer_EncryptedConfigureBadJSON(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &encMockController{})
	if w := callEncrypted(t, srv, pathEncConfig, http.MethodPost, `{oops`); w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}

func TestServer_EncryptedConfigureError(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &encMockController{failWrite: true})
	if w := callEncrypted(t, srv, pathEncConfig, http.MethodPost, `{"enabled":true}`); w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", w.Code)
	}
}

func TestServer_EncryptedCertGenerate(t *testing.T) {
	ctrl := &encMockController{status: &EncryptedDNSStatusResponse{
		Config: core.DefaultEncryptedDNSConfig(),
	}}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	body := `{"commonName":"dns.lan","dnsNames":["dns.lan"],"keyType":"ecdsa","validDays":365,"force":true}`
	w := callEncrypted(t, srv, pathEncGenerate, http.MethodPost, body)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if len(ctrl.genReqs) != 1 {
		t.Fatalf("应转交一次生成请求，实得 %d", len(ctrl.genReqs))
	}
	got := ctrl.genReqs[0]
	if got.CommonName != "dns.lan" || !got.Force || got.ValidDays != 365 {
		t.Fatalf("请求未正确解析: %+v", got)
	}
}

// 证书生成失败是用户输入问题，应按 400 呈现，界面才能当表单错误展示
func TestServer_EncryptedCertGenerateFailureIsBadRequest(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &encMockController{failWrite: true})
	if w := callEncrypted(t, srv, pathEncGenerate, http.MethodPost, `{}`); w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}

func TestServer_EncryptedCertImportPEM(t *testing.T) {
	ctrl := &encMockController{status: &EncryptedDNSStatusResponse{
		Config: core.DefaultEncryptedDNSConfig(),
	}}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	body := `{"mode":"pem","certPem":"CERT","keyPem":"KEY"}`
	w := callEncrypted(t, srv, pathEncImport, http.MethodPost, body)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if len(ctrl.importReqs) != 1 {
		t.Fatalf("应转交一次导入请求，实得 %d", len(ctrl.importReqs))
	}
	if ctrl.importReqs[0].Mode != CertImportModePEM || ctrl.importReqs[0].CertPEM != "CERT" {
		t.Fatalf("请求未正确解析: %+v", ctrl.importReqs[0])
	}
}

func TestServer_EncryptedCertImportPKCS12(t *testing.T) {
	ctrl := &encMockController{status: &EncryptedDNSStatusResponse{
		Config: core.DefaultEncryptedDNSConfig(),
	}}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	// base64 在传输层无歧义，控制器负责解码
	body := `{"mode":"pkcs12","data":"MIIBAA==","password":"s3cret"}`
	w := callEncrypted(t, srv, pathEncImport, http.MethodPost, body)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	got := ctrl.importReqs[0]
	if got.Mode != CertImportModePKCS12 || got.Data != "MIIBAA==" || got.Password != "s3cret" {
		t.Fatalf("请求未正确解析: %+v", got)
	}
}

func TestServer_EncryptedCertImportFailureIsBadRequest(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &encMockController{failWrite: true})
	body := `{"mode":"pem","certPem":"x","keyPem":"y"}`
	if w := callEncrypted(t, srv, pathEncImport, http.MethodPost, body); w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}

func TestServer_EncryptedCertImportMethodNotAllowed(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &encMockController{})
	if w := callEncrypted(t, srv, pathEncImport, http.MethodGet, ""); w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", w.Code)
	}
}

func TestServer_EncryptedRequiresAuth(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &encMockController{})
	for _, tc := range []struct {
		path    string
		handler http.HandlerFunc
	}{
		{pathEncStatus, srv.handleEncryptedDNSStatus},
		{pathEncConfig, srv.handleEncryptedDNSConfigure},
		{pathEncGenerate, srv.handleEncryptedCertGenerate},
		{pathEncImport, srv.handleEncryptedCertImport},
	} {
		req := httptest.NewRequest(http.MethodGet, tc.path, nil)
		w := httptest.NewRecorder()
		srv.withAuth(tc.handler)(w, req)
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("%s: status = %d, want 401", tc.path, w.Code)
		}
	}
}

// 状态回传失败不应让一次成功的操作显示为失败
func TestServer_EncryptedWriteSucceedsEvenIfStatusFails(t *testing.T) {
	ctrl := &encMockController{failStatus: true}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callEncrypted(t, srv, pathEncGenerate, http.MethodPost, `{"force":true}`)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body = %s", w.Code, w.Body.String())
	}
	if len(ctrl.genReqs) != 1 {
		t.Fatal("生成请求仍应被转交")
	}
	var res Response[any]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if !res.Success {
		t.Fatal("操作已成功，响应应为成功")
	}
}
