package core

import (
	"testing"
	"time"

	"github.com/miekg/dns"
)

// TestPauseForDisablesBlocking 校验暂停期内过滤整体放行。
func TestPauseForDisablesBlocking(t *testing.T) {
	engine := groupPolicyEngine(t)

	// 基线：黑名单域名被拦截
	if res := engine.Match("ads.example.com", dns.TypeA); !res.Blocked {
		t.Fatalf("暂停前应正常拦截: %+v", res)
	}
	if !engine.IsEnabled() {
		t.Fatalf("暂停前 IsEnabled 应为 true")
	}
	baselineBlocked := engine.GetStats().BlockedQueries

	engine.PauseFor(30 * time.Minute)
	if engine.IsEnabled() {
		t.Fatalf("暂停期内 IsEnabled 应为 false")
	}
	if res := engine.Match("ads.example.com", dns.TypeA); res.Blocked {
		t.Fatalf("暂停期内应整体放行: %+v", res)
	}
	if res := engine.MatchForGroup("ads.example.com", dns.TypeA, DefaultClientGroupID); res.Blocked {
		t.Fatalf("暂停期内分组评估同样应放行: %+v", res)
	}

	// 暂停期间不新增拦截计数
	st := engine.GetStats()
	if st.BlockedQueries != baselineBlocked {
		t.Fatalf("暂停期内不应新增拦截计数, 基线=%d 当前=%d", baselineBlocked, st.BlockedQueries)
	}
	if !st.Paused || st.PausedRemainingSec <= 0 || st.PausedUntilMs <= 0 {
		t.Fatalf("统计应反映暂停状态: %+v", st)
	}
}

// TestPauseResume 校验手动恢复后立即重新拦截。
func TestPauseResume(t *testing.T) {
	engine := groupPolicyEngine(t)
	engine.PauseFor(time.Hour)

	if engine.IsEnabled() {
		t.Fatalf("暂停后 IsEnabled 应为 false")
	}
	engine.ResumePause()

	if !engine.IsEnabled() {
		t.Fatalf("恢复后 IsEnabled 应为 true")
	}
	if res := engine.Match("ads.example.com", dns.TypeA); !res.Blocked {
		t.Fatalf("恢复后应重新拦截: %+v", res)
	}
	if paused, remaining, until := engine.PauseState(); paused || remaining != 0 || !until.IsZero() {
		t.Fatalf("恢复后暂停状态应清空: paused=%v remaining=%v until=%v", paused, remaining, until)
	}
}

// TestPauseExpiry 校验暂停自然到期后自动恢复拦截（时钟注入）。
func TestPauseExpiry(t *testing.T) {
	engine := groupPolicyEngine(t)

	now := time.Date(2024, time.March, 1, 12, 0, 0, 0, time.Local)
	engine.SetClock(func() time.Time { return now })

	engine.PauseFor(10 * time.Minute)
	if engine.IsEnabled() {
		t.Fatalf("暂停期内 IsEnabled 应为 false")
	}

	// 推进时钟越过截止时刻
	now = now.Add(11 * time.Minute)
	if !engine.IsEnabled() {
		t.Fatalf("暂停到期后 IsEnabled 应恢复为 true")
	}
	if res := engine.Match("ads.example.com", dns.TypeA); !res.Blocked {
		t.Fatalf("暂停到期后应重新拦截: %+v", res)
	}
}

// TestPauseForever 校验 d <= 0 表示暂停至手动恢复。
func TestPauseForever(t *testing.T) {
	engine := groupPolicyEngine(t)
	engine.PauseFor(0)

	paused, remaining, until := engine.PauseState()
	if !paused || remaining <= 0 || until.IsZero() {
		t.Fatalf("永久暂停应报告有效剩余时长: paused=%v remaining=%v", paused, remaining)
	}
	if engine.IsEnabled() {
		t.Fatalf("永久暂停期间 IsEnabled 应为 false")
	}

	engine.ResumePause()
	if !engine.IsEnabled() {
		t.Fatalf("手动恢复后应重新启用")
	}
}

// TestPauseRespectsMasterSwitch 校验总开关关闭时暂停不产生额外影响。
func TestPauseRespectsMasterSwitch(t *testing.T) {
	engine := groupPolicyEngine(t)
	engine.SetEnabled(false)
	engine.PauseFor(time.Hour)

	if engine.IsEnabled() {
		t.Fatalf("总开关关闭时 IsEnabled 应为 false")
	}
	engine.ResumePause()
	if engine.IsEnabled() {
		t.Fatalf("总开关仍关闭时 IsEnabled 应保持 false")
	}
}
