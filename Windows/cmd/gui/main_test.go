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

func TestApp_GetSystemAccentColor(t *testing.T) {
	app := NewApp()
	color := app.GetSystemAccentColor()
	if len(color) != 7 || color[0] != '#' {
		t.Errorf("expected valid hex color, got %s", color)
	}
}

func TestApp_AutoStart(t *testing.T) {
	app := NewApp()
	// 验证查询接口正常运行
	_ = app.IsAutoStartEnabled()
}
