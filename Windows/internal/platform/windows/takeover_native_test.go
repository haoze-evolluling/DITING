package windows

import (
	"context"
	"testing"

	"golang.org/x/sys/windows"
)

func TestNativeSetInterfaceDnsSettings_Export(t *testing.T) {
	if !isSetInterfaceDnsSettingsSupported() {
		t.Skip("SetInterfaceDnsSettings not supported on this platform")
	}

	errReset := resetAdapterDNSNative("invalid-guid")
	if errReset == nil {
		t.Errorf("expected error for invalid GUID on reset, got nil")
	}

	errResetZero := resetAdapterDNSNative("{00000000-0000-0000-0000-000000000000}")
	t.Logf("resetAdapterDNSNative with zero GUID returned: %v", errResetZero)

	errDual := setAdapterDNSDualStackNative("invalid-guid", []string{"127.0.0.1"}, []string{"::1"})
	if errDual == nil {
		t.Errorf("expected error for invalid GUID on dual stack set, got nil")
	}
}

func TestNativeResetResidualLoopbackDNS(t *testing.T) {
	err := resetResidualLoopbackDNSNative(context.Background())
	if err != nil {
		t.Fatalf("resetResidualLoopbackDNSNative failed: %v", err)
	}
}

func TestDnsFlushResolverCache(t *testing.T) {
	mod := windows.NewLazySystemDLL("dnsapi.dll")
	proc := mod.NewProc("DnsFlushResolverCache")
	if err := proc.Find(); err != nil {
		t.Fatalf("not found: %v", err)
	}
	ret, _, err := proc.Call()
	t.Logf("DnsFlushResolverCache: ret=%v, err=%v", ret, err)
}

func TestFlushDNSCacheNative(t *testing.T) {
	err := flushDNSCacheNative()
	if err != nil {
		t.Fatalf("flushDNSCacheNative failed: %v", err)
	}
}
