package windows

import (
	"net"
	"testing"
)

func TestIsPrivateIPv4(t *testing.T) {
	tests := []struct {
		ip   string
		want bool
	}{
		{"192.168.1.1", true},
		{"192.168.0.100", true},
		{"10.0.0.1", true},
		{"10.254.1.2", true},
		{"172.16.0.1", true},
		{"172.31.255.254", true},
		{"172.32.0.1", false},
		{"8.8.8.8", false},
		{"127.0.0.1", false},
		{"169.254.1.1", false},
		{"223.5.5.5", false},
	}

	for _, tt := range tests {
		ip := net.ParseIP(tt.ip)
		if got := isPrivateIPv4(ip); got != tt.want {
			t.Errorf("isPrivateIPv4(%q) = %v; want %v", tt.ip, got, tt.want)
		}
	}
}

func TestGetLANAddresses(t *testing.T) {
	addrs, err := GetLANAddresses()
	if err != nil {
		t.Fatalf("GetLANAddresses() failed: %v", err)
	}
	t.Logf("Discovered LAN addresses: %v", addrs)
	for _, addr := range addrs {
		ip := net.ParseIP(addr)
		if ip == nil {
			t.Errorf("invalid IP string returned: %s", addr)
		}
		if ip.IsLoopback() {
			t.Errorf("loopback IP should not be returned: %s", addr)
		}
		if ip.IsUnspecified() {
			t.Errorf("unspecified IP should not be returned: %s", addr)
		}
	}
}
