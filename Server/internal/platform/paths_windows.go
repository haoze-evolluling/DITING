//go:build windows

package platform

import "path/filepath"

// defaultDataDir 返回 Windows 平台的数据根目录 (%ProgramData%\DITING)。
//
// 保持与历史版本一致的路径，确保已安装的 Windows 端用户配置、
// 接管状态与规则缓存可被无缝延续使用。
func defaultDataDir() string {
	return windowsProgramDataDir()
}

// defaultConfigDir 在 Windows 上与数据目录一致。
func defaultConfigDir() string {
	return windowsProgramDataDir()
}

// windowsProgramDataDir 计算 %ProgramData%\DITING。
func windowsProgramDataDir() string {
	programData := `C:\ProgramData`
	if env := lookupEnv("ProgramData"); env != "" {
		programData = env
	}
	return filepath.Join(programData, "DITING")
}
