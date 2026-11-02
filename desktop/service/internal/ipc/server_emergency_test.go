package ipc

import (
	"context"
	"testing"
	"time"
)

// 应急恢复：桌面窗口与局域网控制台共用一条 HTTP 通路，
// 被拒/不可用时如实报错，不把「没做事」说成「已恢复」。
func TestServer_EmergencyRestore(t *testing.T) {
	token := "emergency-test-token"

	t.Run("接管中时按快照恢复", func(t *testing.T) {
		mockCtrl := &mockController{takeoverOn: true}
		server := NewServer("127.0.0.1:0", token, mockCtrl)
		if err := server.Start(); err != nil {
			t.Fatalf("server.Start failed: %v", err)
		}
		defer func() {
			_ = server.Shutdown(context.Background())
		}()

		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()

		res, err := NewClient(server.Addr(), token).EmergencyRestore(ctx)
		if err != nil {
			t.Fatalf("EmergencyRestore failed: %v", err)
		}
		if res == nil || !res.Healed {
			t.Fatalf("expected healed=true, got %+v", res)
		}
		if res.Message == "" {
			t.Fatal("expected the service's own message")
		}
		if mockCtrl.takeoverOn {
			t.Fatal("expected the mock to be restored")
		}
	})

	t.Run("本就干净时说明无需修复", func(t *testing.T) {
		mockCtrl := &mockController{}
		server := NewServer("127.0.0.1:0", token, mockCtrl)
		if err := server.Start(); err != nil {
			t.Fatalf("server.Start failed: %v", err)
		}
		defer func() {
			_ = server.Shutdown(context.Background())
		}()

		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()

		res, err := NewClient(server.Addr(), token).EmergencyRestore(ctx)
		if err != nil {
			t.Fatalf("EmergencyRestore failed: %v", err)
		}
		if res == nil || res.Healed {
			t.Fatalf("expected healed=false, got %+v", res)
		}
	})

	t.Run("恢复失败时透出原因", func(t *testing.T) {
		mockCtrl := &mockController{emergencyErr: context.DeadlineExceeded}
		server := NewServer("127.0.0.1:0", token, mockCtrl)
		if err := server.Start(); err != nil {
			t.Fatalf("server.Start failed: %v", err)
		}
		defer func() {
			_ = server.Shutdown(context.Background())
		}()

		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()

		if _, err := NewClient(server.Addr(), token).EmergencyRestore(ctx); err == nil {
			t.Fatal("expected an error when the restore fails")
		}
	})

	t.Run("只接受 POST", func(t *testing.T) {
		mockCtrl := &mockController{}
		server := NewServer("127.0.0.1:0", token, mockCtrl)
		if err := server.Start(); err != nil {
			t.Fatalf("server.Start failed: %v", err)
		}
		defer func() {
			_ = server.Shutdown(context.Background())
		}()

		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()

		var resp Response[*EmergencyRestoreResponse]
		if err := NewClient(server.Addr(), token).doRequest(
			ctx,
			"GET",
			"/api/v1/takeover/emergency-restore",
			nil,
			&resp,
		); err != nil {
			t.Fatalf("unexpected transport error: %v", err)
		}
		if resp.Success {
			t.Fatal("expected GET to be rejected")
		}
	})
}
