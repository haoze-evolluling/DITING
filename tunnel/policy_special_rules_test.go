package tunnel

import (
	"testing"

	"github.com/miekg/dns"
)

func TestPolicyEngine_Denyallow(t *testing.T) {
	pe := newPolicyEngine()
	snapshotJSON := `{
		"specialBlock": [
			{
				"pattern": "example.com",
				"source": "denyallow-rule",
				"important": false,
				"denyallow": "good.example.com|safe.example.com",
				"isRegex": false
			}
		]
	}`

	if err := pe.applySnapshot(snapshotJSON); err != nil {
		t.Fatalf("applySnapshot failed: %v", err)
	}

	tests := []struct {
		domain  string
		blocked bool
	}{
		{"example.com", true},
		{"bad.example.com", true},
		{"good.example.com", false},
		{"sub.good.example.com", false},
		{"safe.example.com", false},
		{"other.org", false},
	}

	for _, tt := range tests {
		blocked, reason := pe.evaluate(tt.domain, "", dns.TypeA)
		if blocked != tt.blocked {
			t.Errorf("evaluate(%q): got blocked=%v (reason=%q), want %v", tt.domain, blocked, reason, tt.blocked)
		}
	}
}

func TestPolicyEngine_RegexRules(t *testing.T) {
	pe := newPolicyEngine()
	snapshotJSON := `{
		"specialBlock": [
			{
				"pattern": "^ad[s0-9]*\\.test\\.com$",
				"source": "regex-block",
				"important": false,
				"isRegex": true
			}
		],
		"specialAllow": [
			{
				"pattern": "^ad999\\.test\\.com$",
				"important": false,
				"isRegex": true
			}
		]
	}`

	if err := pe.applySnapshot(snapshotJSON); err != nil {
		t.Fatalf("applySnapshot failed: %v", err)
	}

	tests := []struct {
		domain  string
		blocked bool
	}{
		{"ads.test.com", true},
		{"ad123.test.com", true},
		{"ad999.test.com", false}, // whitelist matches
		{"other.test.com", false},
		{"not-ads.test.com", false},
	}

	for _, tt := range tests {
		blocked, reason := pe.evaluate(tt.domain, "", dns.TypeA)
		if blocked != tt.blocked {
			t.Errorf("evaluate(%q): got blocked=%v (reason=%q), want %v", tt.domain, blocked, reason, tt.blocked)
		}
	}
}

func TestPolicyEngine_DnsType(t *testing.T) {
	pe := newPolicyEngine()
	snapshotJSON := `{
		"specialBlock": [
			{
				"pattern": "v6-only-block.com",
				"source": "v6-block",
				"important": false,
				"dnsType": "AAAA"
			},
			{
				"pattern": "non-v6-block.com",
				"source": "non-v6-block",
				"important": false,
				"dnsType": "~AAAA"
			}
		]
	}`

	if err := pe.applySnapshot(snapshotJSON); err != nil {
		t.Fatalf("applySnapshot failed: %v", err)
	}

	// v6-only-block.com should only block AAAA
	if blocked, _ := pe.evaluate("v6-only-block.com", "", dns.TypeA); blocked {
		t.Errorf("expected TypeA to pass for v6-only-block.com")
	}
	if blocked, _ := pe.evaluate("v6-only-block.com", "", dns.TypeAAAA); !blocked {
		t.Errorf("expected TypeAAAA to be blocked for v6-only-block.com")
	}

	// non-v6-block.com should block everything except AAAA
	if blocked, _ := pe.evaluate("non-v6-block.com", "", dns.TypeA); !blocked {
		t.Errorf("expected TypeA to be blocked for non-v6-block.com")
	}
	if blocked, _ := pe.evaluate("non-v6-block.com", "", dns.TypeHTTPS); !blocked {
		t.Errorf("expected TypeHTTPS to be blocked for non-v6-block.com")
	}
	if blocked, _ := pe.evaluate("non-v6-block.com", "", dns.TypeAAAA); blocked {
		t.Errorf("expected TypeAAAA to pass for non-v6-block.com")
	}
}

func TestPolicyEngine_SpecialRulePriorities(t *testing.T) {
	pe := newPolicyEngine()
	// Priority order:
	// 1. App important block
	// 2. Global important block
	// 3. App allow
	// 4. Global allow
	// 5. App normal block
	// 6. Global normal block
	snapshotJSON := `{
		"specialBlock": [
			{
				"pattern": "target.com",
				"source": "global-normal",
				"important": false,
				"isRegex": false
			},
			{
				"pattern": "target-important.com",
				"source": "app-important",
				"important": true,
				"appScope": "com.test.app",
				"isRegex": false
			}
		],
		"specialAllow": [
			{
				"pattern": "target.com",
				"important": false,
				"appScope": "com.test.app",
				"isRegex": false
			},
			{
				"pattern": "target-important.com",
				"important": false,
				"isRegex": false
			}
		]
	}`

	if err := pe.applySnapshot(snapshotJSON); err != nil {
		t.Fatalf("applySnapshot failed: %v", err)
	}

	// target.com:
	// App com.test.app has specialAllow (priority 3), which overrides global normal block (priority 6).
	blocked, _ := pe.evaluate("target.com", "com.test.app", dns.TypeA)
	if blocked {
		t.Errorf("expected target.com to be allowed for com.test.app due to app-level specialAllow")
	}

	// target.com:
	// Other apps do not have app allow, so global normal block (priority 6) applies.
	blocked, _ = pe.evaluate("target.com", "com.other.app", dns.TypeA)
	if !blocked {
		t.Errorf("expected target.com to be blocked for com.other.app")
	}

	// target-important.com:
	// For com.test.app: app-important block (priority 1) overrides global allow (priority 4).
	blocked, _ = pe.evaluate("target-important.com", "com.test.app", dns.TypeA)
	if !blocked {
		t.Errorf("expected target-important.com to be blocked for com.test.app due to app-important block")
	}

	// For com.other.app: app-important block does NOT apply, so global allow (priority 4) applies.
	blocked, _ = pe.evaluate("target-important.com", "com.other.app", dns.TypeA)
	if blocked {
		t.Errorf("expected target-important.com to be allowed for com.other.app")
	}
}
