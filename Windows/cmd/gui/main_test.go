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
