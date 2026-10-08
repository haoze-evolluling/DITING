package windows

import (
	"os"
	"testing"
)

func TestNativePortCheck(t *testing.T) {
	listeners, err := getPort53ListenersNative()
	if err != nil {
		t.Fatalf("getPort53ListenersNative error: %v", err)
	}
	t.Logf("Found %d listeners on port 53 natively", len(listeners))

	hasICS, icsPID, err := checkICSStatusNative()
	if err != nil {
		t.Fatalf("checkICSStatusNative error: %v", err)
	}
	t.Logf("checkICSStatusNative: hasICS=%v, icsPID=%d", hasICS, icsPID)

	confs, ics, diag, err := checkPort53Native(true, os.Getpid())
	if err != nil {
		t.Fatalf("checkPort53Native error: %v", err)
	}
	t.Logf("checkPort53Native: confs=%d, ics=%v, diag=%s", len(confs), ics, diag)
}
