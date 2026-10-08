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

func TestCompareNativeAndPowerShellScan(t *testing.T) {
	nativeAdapters, err := scanAdaptersNative(context.Background())
	if err != nil {
		t.Fatalf("scanAdaptersNative failed: %v", err)
	}

	exec := NewDefaultExecutor()
	out, err := exec.RunPowerShell(context.Background(), adapterScanScript)
	if err != nil {
		t.Skipf("PowerShell not available: %v", err)
	}

	psAdapters, err := parseAdapterJSON(out)
	if err != nil {
		t.Fatalf("parseAdapterJSON failed: %v", err)
	}

	t.Logf("Native adapter count: %d, PowerShell adapter count: %d", len(nativeAdapters), len(psAdapters))

	nativeMap := make(map[string]AdapterInfo)
	for _, a := range nativeAdapters {
		nativeMap[a.Name] = a
	}

	for _, psA := range psAdapters {
		nA, ok := nativeMap[psA.Name]
		if !ok {
			t.Logf("PS adapter %q not found in native map", psA.Name)
			continue
		}
		t.Logf("Adapter %s: PS(Phys=%v, Stat=%s, GW=%s, v4DHCP=%v, v4DNS=%v) vs Native(Phys=%v, Stat=%s, GW=%s, v4DHCP=%v, v4DNS=%v)",
			psA.Name, psA.IsPhysical, psA.Status, psA.Gateway, psA.IPv4DHCP, psA.IPv4DNS,
			nA.IsPhysical, nA.Status, nA.Gateway, nA.IPv4DHCP, nA.IPv4DNS)
	}
}
