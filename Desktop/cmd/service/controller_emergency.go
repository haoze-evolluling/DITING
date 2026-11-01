package main

import (
	"context"
	"errors"
	"log"

	"github.com/haoze-evolluling/diting/desktop/internal/ipc"
)

// EmergencyRestore 实现 ServiceController 接口：应急恢复系统网络默认设置。
//
// 旧版桌面端把这个能力放在 Wails 绑定（`App.RunEmergencyRestore`）里，Web 控制台只能用 CLI；
// Flutter 前端只走 HTTP，所以服务侧提供同义接口，桌面窗口与局域网控制台共用一份实现。
//
// 失败语义照 `executeEmergencyRestore`（CLI 离线通道）执行三步：先按落盘快照还原接管过的网卡，
// 再兜底重置任何残留指向本机回环的 DNS，最后清空系统 DNS 缓存。单步失败不阻断后续步骤，
// 但错误会带回给调用方，避免「点了没反应却报成功」。
func (p *program) EmergencyRestore(ctx context.Context) (*ipc.EmergencyRestoreResponse, error) {
	if p.stateStore == nil || p.takeoverMgr == nil {
		return nil, errors.New("系统状态存储或 DNS 管理器未就绪")
	}

	healed, healErr := p.stateStore.CheckAndSelfHeal(ctx, p.takeoverMgr)
	if healErr != nil {
		log.Printf("[应急恢复] 快照自愈失败: %v\n", healErr)
	}

	residualErr := p.takeoverMgr.ResetResidualLoopbackDNS(ctx)
	if residualErr != nil {
		log.Printf("[应急恢复] 兜底重置残留回环 DNS 失败: %v\n", residualErr)
	}

	flushErr := p.takeoverMgr.FlushDNSCache(ctx)
	if flushErr != nil {
		log.Printf("[应急恢复] 清空系统 DNS 缓存失败: %v\n", flushErr)
	}

	switch {
	case healErr != nil:
		return nil, healErr
	case residualErr != nil:
		return nil, residualErr
	case flushErr != nil:
		return nil, flushErr
	}

	if healed {
		log.Println("[应急恢复] 已按接管快照恢复系统网卡 DNS")
		return &ipc.EmergencyRestoreResponse{
			Healed:  true,
			Message: "已成功恢复网络 DNS 设置！",
		}, nil
	}
	return &ipc.EmergencyRestoreResponse{
		Healed:  false,
		Message: "网络 DNS 状态正常，无需修复。",
	}, nil
}
