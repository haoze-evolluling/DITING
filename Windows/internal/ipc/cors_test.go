package ipc

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCorsMiddleware_OptionsPreflight(t *testing.T) {
	dummyHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	handler := corsMiddleware(dummyHandler)

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/health", nil)
	req.Header.Set("Origin", "http://wails.localhost")
	req.Header.Set("Access-Control-Request-Method", "POST")
	req.Header.Set("Access-Control-Request-Headers", "authorization,content-type")

	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	resp := w.Result()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("expected status 204 No Content for preflight, got %d", resp.StatusCode)
	}

	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "http://wails.localhost" {
		t.Errorf("expected Access-Control-Allow-Origin 'http://wails.localhost', got '%s'", got)
	}
	if got := resp.Header.Get("Access-Control-Allow-Private-Network"); got != "true" {
		t.Errorf("expected Access-Control-Allow-Private-Network 'true', got '%s'", got)
	}
	if got := resp.Header.Get("Access-Control-Allow-Methods"); got == "" {
		t.Errorf("expected non-empty Access-Control-Allow-Methods")
	}
}

func TestCorsMiddleware_ActualRequest(t *testing.T) {
	dummyHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("response-data"))
	})

	handler := corsMiddleware(dummyHandler)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/status", nil)
	req.Header.Set("Origin", "http://wails.localhost")

	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	resp := w.Result()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200 OK, got %d", resp.StatusCode)
	}

	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "http://wails.localhost" {
		t.Errorf("expected Access-Control-Allow-Origin 'http://wails.localhost', got '%s'", got)
	}
	if got := resp.Header.Get("Access-Control-Allow-Private-Network"); got != "true" {
		t.Errorf("expected Access-Control-Allow-Private-Network 'true', got '%s'", got)
	}
}

func TestCorsMiddleware_NoOriginHeader(t *testing.T) {
	dummyHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	handler := corsMiddleware(dummyHandler)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	resp := w.Result()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200 OK, got %d", resp.StatusCode)
	}

	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "*" {
		t.Errorf("expected Access-Control-Allow-Origin '*', got '%s'", got)
	}
}
