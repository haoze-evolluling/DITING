package auth

import (
	"testing"
	"time"
)

func TestAuthManager_SetupAndLogin(t *testing.T) {
	mgr := NewManager("admin", "", "", 1*time.Hour)
	if mgr.IsInitialized() {
		t.Fatalf("初始时应未初始化")
	}

	// 尚未初始化时登录应返回 ErrNotInitialized
	_, err := mgr.Login("admin", "123456", "127.0.0.1")
	if err == nil {
		t.Fatalf("期望未初始化错误，但未报错")
	}

	// 初始设置凭据
	err = mgr.SetupInitialCredentials("admin", "123456")
	if err != nil {
		t.Fatalf("初始化密码失败: %v", err)
	}
	if !mgr.IsInitialized() {
		t.Fatalf("初始化后 IsInitialized 应为 true")
	}

	// 重复初始化应报错
	err = mgr.SetupInitialCredentials("admin", "654321")
	if err != ErrAlreadyInitialized {
		t.Fatalf("重复初始化期望 ErrAlreadyInitialized，但获得: %v", err)
	}

	// 错误密码登录
	_, err = mgr.Login("admin", "wrongpass", "127.0.0.1")
	if err == nil {
		t.Fatalf("错误密码应返回错误")
	}

	// 正确密码登录
	sess, err := mgr.Login("admin", "123456", "127.0.0.1")
	if err != nil {
		t.Fatalf("正确密码登录失败: %v", err)
	}
	if sess.Token == "" || sess.Username != "admin" {
		t.Fatalf("会话数据异常: %+v", sess)
	}

	// 验证有效性
	validSess, ok := mgr.ValidateSession(sess.Token)
	if !ok || validSess.Username != "admin" {
		t.Fatalf("校验会话失败")
	}

	// 注销会话
	mgr.RevokeSession(sess.Token)
	_, ok = mgr.ValidateSession(sess.Token)
	if ok {
		t.Fatalf("注销后会话仍有效")
	}
}

func TestAuthManager_BruteForceLockout(t *testing.T) {
	mgr := NewManager("admin", "", "", 1*time.Hour)
	_ = mgr.SetupInitialCredentials("admin", "password123")

	clientIP := "192.168.1.100"
	for i := 0; i < MaxFailedAttempts; i++ {
		_, _ = mgr.Login("admin", "wrong", clientIP)
	}

	locked, remaining := mgr.CheckIPLockout(clientIP)
	if !locked || remaining <= 0 {
		t.Fatalf("连续失败 %d 次后应处于锁定状态", MaxFailedAttempts)
	}

	// 锁定状态下即便使用正确密码也应拒绝
	_, err := mgr.Login("admin", "password123", clientIP)
	if err == nil {
		t.Fatalf("锁定状态下应拒绝登录")
	}
}

func TestAuthManager_UpdateCredentials(t *testing.T) {
	mgr := NewManager("admin", "", "", 1*time.Hour)
	_ = mgr.SetupInitialCredentials("admin", "initialPass")

	sess, err := mgr.Login("admin", "initialPass", "127.0.0.1")
	if err != nil {
		t.Fatalf("登录失败: %v", err)
	}

	// 使用错误旧密码修改
	err = mgr.UpdateCredentials("admin", "wrongOld", "newPass123", false)
	if err == nil {
		t.Fatalf("旧密码错误应失败")
	}

	// 正确修改
	err = mgr.UpdateCredentials("admin", "initialPass", "newPass123", false)
	if err != nil {
		t.Fatalf("修改密码失败: %v", err)
	}

	// 旧会话应已被注销
	_, ok := mgr.ValidateSession(sess.Token)
	if ok {
		t.Fatalf("修改密码后旧会话应失效")
	}

	// 新密码登录
	_, err = mgr.Login("admin", "newPass123", "127.0.0.1")
	if err != nil {
		t.Fatalf("新密码登录失败: %v", err)
	}
}
