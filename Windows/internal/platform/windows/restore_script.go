package windows

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// GenerateRestoreScript 生成独立离线恢复脚本 restore-dns.bat
// 该脚本不依赖本程序，用于程序无法启动时手动还原网卡 DNS
func GenerateRestoreScript(adapters []AdapterState, outputPath string) error {
	var sb strings.Builder
	sb.WriteString("@echo off\r\n")
	sb.WriteString("chcp 65001 >nul\r\n")
	sb.WriteString("echo ================================================================\r\n")
	sb.WriteString("echo   谛听 (DITING) 紧急离线 DNS 还原脚本\r\n")
	sb.WriteString(fmt.Sprintf("echo   生成时间: %s\r\n", time.Now().Format("2006-01-02 15:04:05")))
	sb.WriteString("echo ================================================================\r\n\r\n")
	sb.WriteString("net session >nul 2>&1\r\n")
	sb.WriteString("if %errorlevel% neq 0 (\r\n")
	sb.WriteString("    echo [错误] 请右键点击此批处理脚本，选择【以管理员身份运行】！\r\n")
	sb.WriteString("    pause\r\n")
	sb.WriteString("    exit /b 1\r\n")
	sb.WriteString(")\r\n\r\n")
	sb.WriteString("echo [1/2] 正在还原网卡 DNS 配置...\r\n")

	for _, raw := range adapters {
		a := CleanAdapterState(raw)
		sb.WriteString(fmt.Sprintf("echo 正在恢复适配器 [%s] ...\r\n", a.Name))
		if a.IPv4DHCP || len(a.IPv4DNS) == 0 {
			sb.WriteString(fmt.Sprintf("netsh interface ipv4 set dnsservers name=\"%s\" source=dhcp\r\n", a.Name))
		} else {
			for i, dnsIP := range a.IPv4DNS {
				if i == 0 {
					sb.WriteString(fmt.Sprintf("netsh interface ipv4 set dnsservers name=\"%s\" static %s primary validate=no\r\n", a.Name, dnsIP))
				} else {
					sb.WriteString(fmt.Sprintf("netsh interface ipv4 add dnsservers name=\"%s\" %s index=%d validate=no\r\n", a.Name, dnsIP, i+1))
				}
			}
		}

		if a.IPv6DHCP || len(a.IPv6DNS) == 0 {
			sb.WriteString(fmt.Sprintf("netsh interface ipv6 set dnsservers name=\"%s\" source=dhcp\r\n", a.Name))
		} else {
			for i, dnsIP := range a.IPv6DNS {
				if i == 0 {
					sb.WriteString(fmt.Sprintf("netsh interface ipv6 set dnsservers name=\"%s\" static %s primary validate=no\r\n", a.Name, dnsIP))
				} else {
					sb.WriteString(fmt.Sprintf("netsh interface ipv6 add dnsservers name=\"%s\" %s index=%d validate=no\r\n", a.Name, dnsIP, i+1))
				}
			}
		}
	}

	sb.WriteString("\r\necho [2/2] 正在刷新系统 DNS 解析缓存...\r\n")
	sb.WriteString("ipconfig /flushdns\r\n\r\n")
	sb.WriteString("echo ================================================================\r\n")
	sb.WriteString("echo 系统 DNS 设置已完全恢复初始状态。\r\n")
	sb.WriteString("echo ================================================================\r\n")
	sb.WriteString("pause\r\n")

	dir := filepath.Dir(outputPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	return os.WriteFile(outputPath, []byte(sb.String()), 0644)
}
