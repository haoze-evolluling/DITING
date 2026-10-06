package windows

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"strings"
)

// PortConflict 记录占用 53 端口的冲突详情
type PortConflict struct {
	Port         int    `json:"port"`
	Protocol     string `json:"protocol"`     // "UDP" 或 "TCP"
	LocalAddress string `json:"localAddress"` // 监听地址，如 "0.0.0.0:53"
	PID          int    `json:"pid"`          // 占用进程 PID
	ProcessName  string `json:"processName"`  // 占用进程名称
	ServiceName  string `json:"serviceName,omitempty"`
	IsICS        bool   `json:"isICS"`     // 是否为 Windows ICS (SharedAccess) 网络共享服务
	IsSelf       bool   `json:"isSelf"`    // 是否为谛听服务自身占用的端口
	Diagnosis    string `json:"diagnosis"` // 针对性诊断与处置建议
}

// PortCheckResult 包含 53 端口可用性探测汇总
type PortCheckResult struct {
	Available  bool           `json:"available"`  // 127.0.0.1:53 是否立即可用
	Conflicts  []PortConflict `json:"conflicts"`  // 系统中现存的 53 端口冲突/监听列表
	HasICS     bool           `json:"hasICS"`     // 是否检测到 ICS 服务运行
	Diagnostic string         `json:"diagnostic"` // 综合诊断报告建议
}

// PortChecker 定义端口冲突探测接口
type PortChecker interface {
	CheckPort53(ctx context.Context) (*PortCheckResult, error)
}

// WindowsPortChecker Windows 平台 53 端口占用与冲突检测器
type WindowsPortChecker struct {
	executor CommandExecutor
}

// NewPortChecker 创建端口检测器
func NewPortChecker(executor CommandExecutor) *WindowsPortChecker {
	if executor == nil {
		executor = NewDefaultExecutor()
	}
	return &WindowsPortChecker{executor: executor}
}

type portRawDTO struct {
	Protocol     string `json:"Protocol"`
	LocalAddress string `json:"LocalAddress"`
	PID          int    `json:"PID"`
	ProcessName  string `json:"ProcessName"`
}

type icsInfoDTO struct {
	Name      string `json:"Name"`
	ProcessId int    `json:"ProcessId"`
	State     string `json:"State"`
}

const portCheckScript = `
$udp = @(Get-NetUDPEndpoint -LocalPort 53 -ErrorAction SilentlyContinue | ForEach-Object {
    $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue;
    [PSCustomObject]@{
        Protocol = 'UDP';
        LocalAddress = $_.LocalAddress + ':' + $_.LocalPort;
        PID = $_.OwningProcess;
        ProcessName = if ($proc) { $proc.ProcessName } else { '' }
    }
});
$tcp = @(Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue | ForEach-Object {
    $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue;
    [PSCustomObject]@{
        Protocol = 'TCP';
        LocalAddress = $_.LocalAddress + ':' + $_.LocalPort;
        PID = $_.OwningProcess;
        ProcessName = if ($proc) { $proc.ProcessName } else { '' }
    }
});
$list = @($udp + $tcp) | Where-Object { $_ -and $_.LocalAddress };
$ics = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'SharedAccess' } | Select-Object Name, ProcessId, State;
[PSCustomObject]@{
    Listeners = $list;
    ICS = $ics;
} | ConvertTo-Json -Depth 3
`

type portScriptResult struct {
	Listeners json.RawMessage `json:"Listeners"`
	ICS       *icsInfoDTO     `json:"ICS"`
}

// CheckPort53 探测 53 端口冲突并识别 SharedAccess (ICS) 等服务
func (c *WindowsPortChecker) CheckPort53(ctx context.Context) (*PortCheckResult, error) {
	// 1. 本地尝试轻量级绑定探测（检测当前用户态能否直接成功监听 127.0.0.1:53）
	udpFree := testUDPBind("127.0.0.1:53")
	tcpFree := testTCPBind("127.0.0.1:53")
	available := udpFree && tcpFree

	// 2. 通过 PowerShell 深度检测全系统 53 端口监听实体及 ICS 状态
	out, err := c.executor.RunPowerShell(ctx, portCheckScript)
	if err != nil {
		// 脚本执行失败时仅返回基础套接字探测结果
		return &PortCheckResult{
			Available:  available,
			Conflicts:  nil,
			HasICS:     false,
			Diagnostic: fmt.Sprintf("53 端口套接字绑定探测: UDP=%v, TCP=%v (系统诊断命令失败: %v)", udpFree, tcpFree, err),
		}, nil
	}

	conflicts, hasICS, diag := parsePortCheckJSON(out, available, os.Getpid())
	hasOtherConflict := false
	for _, conf := range conflicts {
		if !conf.IsSelf {
			hasOtherConflict = true
			break
		}
	}
	if !hasOtherConflict && !hasICS {
		available = true
	}

	return &PortCheckResult{
		Available:  available,
		Conflicts:  conflicts,
		HasICS:     hasICS,
		Diagnostic: diag,
	}, nil
}

func testUDPBind(addr string) bool {
	conn, err := net.ListenPacket("udp4", addr)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func testTCPBind(addr string) bool {
	l, err := net.Listen("tcp4", addr)
	if err != nil {
		return false
	}
	_ = l.Close()
	return true
}

func parsePortCheckJSON(out string, available bool, selfPIDs ...int) ([]PortConflict, bool, string) {
	selfPID := 0
	if len(selfPIDs) > 0 {
		selfPID = selfPIDs[0]
	}

	var res portScriptResult
	if err := json.Unmarshal([]byte(strings.TrimSpace(out)), &res); err != nil {
		return nil, false, "解析系统端口诊断信息失败: " + err.Error()
	}

	hasICS := false
	icsPID := 0
	if res.ICS != nil && strings.EqualFold(res.ICS.State, "Running") {
		hasICS = true
		icsPID = res.ICS.ProcessId
	}

	var rawList []portRawDTO
	if len(res.Listeners) > 0 && string(res.Listeners) != "null" {
		if err := json.Unmarshal(res.Listeners, &rawList); err != nil {
			var single portRawDTO
			if errS := json.Unmarshal(res.Listeners, &single); errS == nil {
				rawList = []portRawDTO{single}
			}
		}
	}

	conflicts := make([]PortConflict, 0, len(rawList))
	var diagLines []string
	hasSelfListener := false

	for _, item := range rawList {
		isSelf := (selfPID > 0 && item.PID == selfPID)
		if isSelf {
			hasSelfListener = true
		}
		isICS := !isSelf && hasICS && (item.PID == icsPID || strings.Contains(strings.ToLower(item.ProcessName), "svchost") && hasICS)
		diagnosis := ""
		if isSelf {
			diagnosis = fmt.Sprintf("进程 PID %d (%s) 为谛听 (DITING) 服务自身正在监听 %s (%s)。", item.PID, item.ProcessName, item.LocalAddress, item.Protocol)
		} else if isICS {
			diagnosis = fmt.Sprintf("检测到 Windows 网络连接共享服务 (SharedAccess / ICS) 正在运行 (PID: %d)。ICS 会在 0.0.0.0:53 上占用 UDP，可能阻碍或干扰 DNS 本地代理。建议在服务管理器 (services.msc) 中将 'Internet Connection Sharing (ICS)' 服务停止并设置为禁用，或在管理员终端执行 'sc stop SharedAccess'。", item.PID)
			diagLines = append(diagLines, diagnosis)
		} else {
			diagnosis = fmt.Sprintf("进程 PID %d (%s) 正在监听 %s (%s)。若与本地代理冲突，请停止该进程或更改其监听端口。", item.PID, item.ProcessName, item.LocalAddress, item.Protocol)
			diagLines = append(diagLines, diagnosis)
		}

		conflicts = append(conflicts, PortConflict{
			Port:         53,
			Protocol:     item.Protocol,
			LocalAddress: item.LocalAddress,
			PID:          item.PID,
			ProcessName:  item.ProcessName,
			ServiceName:  ternary(isICS, "SharedAccess", ""),
			IsICS:        isICS,
			IsSelf:       isSelf,
			Diagnosis:    diagnosis,
		})
	}

	if len(diagLines) == 0 {
		if hasSelfListener {
			return conflicts, hasICS, "127.0.0.1:53 当前由谛听 (DITING) 核心服务监听中，无外部端口冲突。"
		}
		if available {
			return conflicts, hasICS, "53 端口空闲且可用，无端口冲突。"
		}
		return conflicts, hasICS, "未能直接绑定 127.0.0.1:53，但未探测到明确的系统监听进程（可能需要管理员权限）。"
	}

	return conflicts, hasICS, strings.Join(diagLines, "\n")
}

func ternary[T any](cond bool, a, b T) T {
	if cond {
		return a
	}
	return b
}
