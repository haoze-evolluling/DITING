package windows

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

type mockFirewallExecutor struct {
	cmdCalls []string
	outputs  map[string]string
	errors   map[string]error
}

func (m *mockFirewallExecutor) RunPowerShell(ctx context.Context, script string) (string, error) {
	return "", nil
}

func (m *mockFirewallExecutor) RunCommand(ctx context.Context, name string, args ...string) (string, error) {
	full := name + " " + strings.Join(args, " ")
	m.cmdCalls = append(m.cmdCalls, full)
	for pattern, err := range m.errors {
		if strings.Contains(full, pattern) {
			return "", err
		}
	}
	for pattern, out := range m.outputs {
		if strings.Contains(full, pattern) {
			return out, nil
		}
	}
	return "OK", nil
}

func TestCheckFirewallPort53(t *testing.T) {
	ctx := context.Background()

	// 1. 规则存在且启用 (中文)
	mock := &mockFirewallExecutor{
		outputs: map[string]string{
			"show rule": "规则名称: Diting DNS LAN Server (UDP)\n已启用: 是\n操作: 允许\n",
		},
	}
	allowed, err := CheckFirewallPort53(ctx, mock)
	if err != nil || !allowed {
		t.Fatalf("expected allowed true, got %v, err: %v", allowed, err)
	}

	// 2. 规则存在且启用 (英文)
	mockEn := &mockFirewallExecutor{
		outputs: map[string]string{
			"show rule": "Rule Name: Diting DNS LAN Server (UDP)\nEnabled: Yes\nAction: Allow\n",
		},
	}
	allowedEn, err := CheckFirewallPort53(ctx, mockEn)
	if err != nil || !allowedEn {
		t.Fatalf("expected allowedEn true, got %v, err: %v", allowedEn, err)
	}

	// 3. 规则不存在 (netsh 报错)
	mockMissing := &mockFirewallExecutor{
		errors: map[string]error{
			"show rule": fmt.Errorf("找不到指定的规则"),
		},
	}
	allowedMissing, err := CheckFirewallPort53(ctx, mockMissing)
	if err != nil || allowedMissing {
		t.Fatalf("expected allowedMissing false, got %v, err: %v", allowedMissing, err)
	}
}

func TestConfigureFirewallPort53(t *testing.T) {
	ctx := context.Background()

	// 1. 启用防火墙规则
	mock := &mockFirewallExecutor{
		outputs: make(map[string]string),
	}
	err := ConfigureFirewallPort53(ctx, mock, true)
	if err != nil {
		t.Fatalf("expected nil err, got %v", err)
	}

	// 应有删除旧规则与添加 UDP/TCP 规则的调用
	hasUDPAdd := false
	hasTCPAdd := false
	for _, call := range mock.cmdCalls {
		if strings.Contains(call, "add rule") && strings.Contains(call, "protocol=UDP") {
			hasUDPAdd = true
		}
		if strings.Contains(call, "add rule") && strings.Contains(call, "protocol=TCP") {
			hasTCPAdd = true
		}
	}
	if !hasUDPAdd || !hasTCPAdd {
		t.Errorf("expected both UDP and TCP add rules, calls: %v", mock.cmdCalls)
	}

	// 2. 禁用/移除防火墙规则
	mockDisable := &mockFirewallExecutor{
		outputs: make(map[string]string),
	}
	err = ConfigureFirewallPort53(ctx, mockDisable, false)
	if err != nil {
		t.Fatalf("expected nil err on disable, got %v", err)
	}
	hasDelete := false
	for _, call := range mockDisable.cmdCalls {
		if strings.Contains(call, "delete rule") {
			hasDelete = true
		}
	}
	if !hasDelete {
		t.Errorf("expected delete rule calls on disable")
	}
}
