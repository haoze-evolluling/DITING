package windows

import (
	"context"
	"testing"
)

func TestNativeSetInterfaceDnsSettings_Export(t *testing.T) {
	if !isSetInterfaceDnsSettingsSupported() {
		t.Skip("SetInterfaceDnsSettings not supported on this platform")
	}

	// 传入非法 GUID 测试参数校验
	err := setAdapterDNSNative("invalid-guid", []string{"127.0.0.1"})
	if err == nil {
		t.Errorf("expected error for invalid GUID, got nil")
	}

	errReset := resetAdapterDNSNative("invalid-guid")
	if errReset == nil {
		t.Errorf("expected error for invalid GUID on reset, got nil")
	}
}

func TestNativeResetResidualLoopbackDNS(t *testing.T) {
	mock := &mockExecutor{}
	err := resetResidualLoopbackDNSNative(context.Background(), mock)
	if err != nil {
		t.Fatalf("resetResidualLoopbackDNSNative failed: %v", err)
	}
}
