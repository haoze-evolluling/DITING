package core

import (
	"net"
	"testing"
)

func TestAccessControl_EmptyDefault(t *testing.T) {
	cfg := DefaultAccessControlConfig()
	ac, err := NewAccessControl(cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	allowed, _ := ac.CheckAccess(net.ParseIP("192.168.1.100"))
	if !allowed {
		t.Fatal("expected default empty config to allow all clients")
	}

	allowed, _ = ac.CheckAccess(nil)
	if !allowed {
		t.Fatal("expected nil IP to be allowed")
	}
}

func TestAccessControl_BlockedList(t *testing.T) {
	cfg := AccessControlConfig{
		BlockedClients: []string{
			"192.168.1.50",
			"10.0.0.0/24",
			"2001:db8::1",
			"2001:db8:ffff::/48",
		},
	}
	ac, err := NewAccessControl(cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Blocked single IP
	if allowed, _ := ac.CheckAccess(net.ParseIP("192.168.1.50")); allowed {
		t.Fatal("expected 192.168.1.50 to be blocked")
	}

	// Not blocked sibling IP
	if allowed, _ := ac.CheckAccess(net.ParseIP("192.168.1.51")); !allowed {
		t.Fatal("expected 192.168.1.51 to be allowed")
	}

	// Blocked CIDR
	if allowed, _ := ac.CheckAccess(net.ParseIP("10.0.0.123")); allowed {
		t.Fatal("expected 10.0.0.123 to be blocked by CIDR 10.0.0.0/24")
	}
	if allowed, _ := ac.CheckAccess(net.ParseIP("10.0.1.1")); !allowed {
		t.Fatal("expected 10.0.1.1 to be allowed")
	}

	// IPv6 blocked
	if allowed, _ := ac.CheckAccess(net.ParseIP("2001:db8::1")); allowed {
		t.Fatal("expected 2001:db8::1 to be blocked")
	}
	if allowed, _ := ac.CheckAccess(net.ParseIP("2001:db8:ffff::10")); allowed {
		t.Fatal("expected 2001:db8:ffff::10 to be blocked by /48 CIDR")
	}
}

func TestAccessControl_AllowedList(t *testing.T) {
	cfg := AccessControlConfig{
		AllowedClients: []string{
			"192.168.1.10",
			"192.168.2.0/24",
		},
	}
	ac, err := NewAccessControl(cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if allowed, _ := ac.CheckAccess(net.ParseIP("192.168.1.10")); !allowed {
		t.Fatal("expected 192.168.1.10 to be allowed")
	}
	if allowed, _ := ac.CheckAccess(net.ParseIP("192.168.2.55")); !allowed {
		t.Fatal("expected 192.168.2.55 to be allowed")
	}
	if allowed, _ := ac.CheckAccess(net.ParseIP("192.168.1.11")); allowed {
		t.Fatal("expected 192.168.1.11 to be rejected when allowedClients is active")
	}
	if allowed, _ := ac.CheckAccess(net.ParseIP("8.8.8.8")); allowed {
		t.Fatal("expected 8.8.8.8 to be rejected")
	}
}

func TestAccessControl_BlockedTakesPrecedenceOverAllowed(t *testing.T) {
	cfg := AccessControlConfig{
		AllowedClients: []string{"192.168.1.0/24"},
		BlockedClients: []string{"192.168.1.100"},
	}
	ac, err := NewAccessControl(cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if allowed, _ := ac.CheckAccess(net.ParseIP("192.168.1.50")); !allowed {
		t.Fatal("expected 192.168.1.50 to be allowed")
	}
	if allowed, _ := ac.CheckAccess(net.ParseIP("192.168.1.100")); allowed {
		t.Fatal("expected 192.168.1.100 to be blocked because Blocked takes precedence")
	}
}

func TestAccessControl_InvalidCIDR(t *testing.T) {
	cfg := AccessControlConfig{
		AllowedClients: []string{"invalid-cidr/999"},
	}
	_, err := NewAccessControl(cfg)
	if err == nil {
		t.Fatal("expected error for invalid CIDR")
	}
}

func TestAccessControl_IPv4MappedIPv6(t *testing.T) {
	cfg := AccessControlConfig{
		BlockedClients: []string{"192.168.1.50"},
		AllowedClients: []string{"192.168.1.0/24"},
	}
	ac, err := NewAccessControl(cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// 模拟双栈监听器接收到的 IPv4-mapped IPv6 地址 (::ffff:192.168.1.50 与 ::ffff:192.168.1.60)
	v4MappedBlocked := net.ParseIP("::ffff:192.168.1.50")
	if allowed, _ := ac.CheckAccess(v4MappedBlocked); allowed {
		t.Fatal("expected ::ffff:192.168.1.50 to be blocked")
	}

	v4MappedAllowed := net.ParseIP("::ffff:192.168.1.60")
	if allowed, _ := ac.CheckAccess(v4MappedAllowed); !allowed {
		t.Fatal("expected ::ffff:192.168.1.60 to be allowed")
	}
}

