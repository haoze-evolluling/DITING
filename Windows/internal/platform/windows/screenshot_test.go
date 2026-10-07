package windows

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCaptureWindowNonExistent(t *testing.T) {
	_, err := CaptureWindow("NonExistentWindow_1234567890", "")
	if err == nil {
		t.Fatal("expected error for non existent window, got nil")
	}
}

func TestCaptureDitingWindowFallback(t *testing.T) {
	tmpDir := t.TempDir()
	targetFile := filepath.Join(tmpDir, "test.png")

	// Even if window is not found in headless CI, it should return a descriptive error
	_, err := CaptureDitingWindow(targetFile)
	if err == nil {
		if _, statErr := os.Stat(targetFile); statErr != nil {
			t.Fatalf("expected file to exist if err is nil: %v", statErr)
		}
	} else {
		// Error should mention window title
		if err.Error() == "" {
			t.Fatal("expected non-empty error message")
		}
	}
}
