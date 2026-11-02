package tunnel

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

func TestHTTPConnectOutbound_UDPDoesNotReportError(t *testing.T) {
	var statusMu sync.Mutex
	reportedStatuses := make([]string, 0)

	report := func(state, message string) {
		statusMu.Lock()
		defer statusMu.Unlock()
		reportedStatuses = append(reportedStatuses, state+":"+message)
	}

	cfg := outboundProxyConfig{
		Enabled:  true,
		Protocol: "http",
		Host:     "127.0.0.1",
		Port:     8080,
	}

	outbound := newFlowOutbound(cfg, nil, report)
	defer outbound.Close()

	if outbound.SupportsUDP() {
		t.Fatal("expected HTTP proxy outbound to not support UDP")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	_, err := outbound.DialUDP(ctx, "8.8.8.8:53")
	if !errors.Is(err, errOutboundUDPUnsupported) {
		t.Fatalf("expected errOutboundUDPUnsupported, got %v", err)
	}

	_, err = outbound.OpenPacket(ctx)
	if !errors.Is(err, errOutboundUDPUnsupported) {
		t.Fatalf("expected errOutboundUDPUnsupported, got %v", err)
	}

	// Give a moment in case any erroneous async report was dispatched
	time.Sleep(50 * time.Millisecond)

	statusMu.Lock()
	defer statusMu.Unlock()
	if len(reportedStatuses) > 0 {
		t.Fatalf("expected no status reports on unsupported UDP, but got: %v", reportedStatuses)
	}
}

func TestProxyOutbound_StatusDeduplication(t *testing.T) {
	var statusMu sync.Mutex
	reported := make([]string, 0)

	report := func(state, message string) {
		statusMu.Lock()
		defer statusMu.Unlock()
		reported = append(reported, state+":"+message)
	}

	cfg := outboundProxyConfig{
		Enabled:  true,
		Protocol: "socks5",
		Host:     "127.0.0.1",
		Port:     1080,
	}

	outbound := newFlowOutbound(cfg, nil, report)
	defer outbound.Close()

	proxyOutbound, ok := outbound.(*proxyFlowOutbound)
	if !ok {
		t.Fatal("expected *proxyFlowOutbound")
	}

	// Report ready multiple times
	proxyOutbound.status("ready", nil)
	proxyOutbound.status("ready", nil)
	proxyOutbound.status("ready", nil)

	// Report same error multiple times
	proxyOutbound.status("error", errors.New("connection failed"))
	proxyOutbound.status("error", errors.New("connection failed"))

	// Report ready again
	proxyOutbound.status("ready", nil)

	time.Sleep(100 * time.Millisecond)

	statusMu.Lock()
	defer statusMu.Unlock()

	expected := []string{
		"ready:",
		"error:connection failed",
		"ready:",
	}

	if len(reported) != len(expected) {
		t.Fatalf("expected %d events, got %d: %v", len(expected), len(reported), reported)
	}

	for i := range expected {
		if reported[i] != expected[i] {
			t.Errorf("at index %d: expected %q, got %q", i, expected[i], reported[i])
		}
	}
}
