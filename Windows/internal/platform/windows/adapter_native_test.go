package windows

import (
	"context"
	"testing"
)

func TestNativeAdapterScan(t *testing.T) {
	adapters, err := scanAdaptersNative(context.Background())
	if err != nil {
		t.Fatalf("scanAdaptersNative failed: %v", err)
	}

	if len(adapters) == 0 {
		t.Errorf("expected at least 1 adapter, got 0")
	}

	foundPhysical := false
	for _, a := range adapters {
		if a.IsPhysical && a.Status == "Up" {
			foundPhysical = true
			break
		}
	}
	t.Logf("Found %d adapters natively, found active physical adapter: %v", len(adapters), foundPhysical)
}
