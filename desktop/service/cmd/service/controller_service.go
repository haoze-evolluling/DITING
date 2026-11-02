package main

import (
	"context"
	"fmt"
	"os"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// GetCoreServiceStatus 实现 ServiceController 接口。
//
// 供 Web 控制台获取宿主机后台核心服务的真实状态。服务管理器在查询失败时
// 会返回尽可能完整的部分状态，此处保留该状态并附上错误原因，避免前端
// 因单次查询异常而退化为"未安装"等误导性展示。
func (p *program) GetCoreServiceStatus(ctx context.Context) (*platform.CoreServiceStatus, error) {
	if p.serviceMgr == nil {
		return nil, fmt.Errorf("后台核心服务管理器未初始化")
	}

	status, err := p.serviceMgr.GetStatus(ctx)
	if err != nil {
		if status != nil {
			if status.Message == "" {
				status.Message = err.Error()
			}
			return status, nil
		}
		return nil, err
	}

	p.describeForegroundMode(status)
	return status, nil
}

// describeForegroundMode 修正"未注册为系统服务"场景下的状态展示。
//
// 本方法由服务进程自身提供，因此能收到该请求即证明核心正在运行。
// 若此时系统服务尚未注册（例如以前台/控制台方式启动），如实说明运行形态，
// 而不是让用户面对"未安装"却同时连着服务的自相矛盾提示。
func (p *program) describeForegroundMode(status *platform.CoreServiceStatus) {
	if status == nil || status.Installed {
		return
	}

	// 未注册为服务时，平台层无从解析可执行路径，此处以进程自身路径兜底，
	// 这正是"核心程序位置"一栏应当展示的内容。
	if status.ExecutablePath == "" {
		if exe, err := os.Executable(); err == nil {
			status.ExecutablePath = exe
			status.CanInstall = true
		}
	}

	p.mu.Lock()
	dnsRunning := p.dnsRunning
	p.mu.Unlock()

	status.Running = true
	status.State = "foreground"
	status.StateText = "前台运行中"
	if dnsRunning {
		status.Message = "核心服务未注册为系统服务，当前以前台模式运行并正常提供 DNS 解析。"
	} else {
		status.Message = "核心服务未注册为系统服务，当前以前台模式运行，DNS 监听器尚未启动。"
	}
}
