package main

import (
	"testing"
)

func TestApp_Greet(t *testing.T) {
	app := NewApp()
	msg := app.Greet("Tester")
	if msg == "" {
		t.Errorf("expected greet message")
	}
}

func TestApp_AutoStart(t *testing.T) {
	app := NewApp()
	// 验证查询接口正常运行
	_ = app.IsAutoStartEnabled()
}

func TestApp_CoreServiceStatus(t *testing.T) {
	app := NewApp()
	status, err := app.GetCoreServiceStatus()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status == nil {
		t.Fatalf("expected non-nil service status")
	}
	if status.State == "" {
		t.Errorf("expected non-empty state")
	}
}

