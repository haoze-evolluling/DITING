<#
.SYNOPSIS
    谛听 (DITING) 软件界面截图接口工具
.DESCRIPTION
    仅截取软件自身的窗口界面（排除系统桌面、任务栏及外部干扰），
    支持逐页遍历截取（总览大盘、网卡接管、上游调度、智能缓存、规则防护、实时日志、设置中心、各类弹窗），
    支持浅色/深色主题与自定义输出分辨率。
.PARAMETER Tab
    截取的目标标签页: all (默认), dashboard, adapters, upstream, cache, rules, logs, settings, modal-alert
.PARAMETER Theme
    主题色彩模式: both (默认，截取浅色和深色), dark, light
.PARAMETER OutputDir
    截图保存目录，默认项目根目录下的 screenshots/
#>

[CmdletBinding()]
param (
    [ValidateSet("all", "dashboard", "adapters", "upstream", "cache", "rules", "logs", "settings", "modal-alert")]
    [string]$Tab = "all",

    [ValidateSet("both", "dark", "light")]
    [string]$Theme = "both",

    [string]$OutputDir = "",

    [int]$Width = 1280,
    [int]$Height = 720
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir

if (-not $OutputDir) {
    $OutputDir = Join-Path $rootDir "screenshots"
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# 寻找系统 Edge 浏览器执行路径 (Wails 底层 WebView2 同源引擎)
$edgePaths = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    (Get-Command msedge.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
)

$edgeExe = $null
foreach ($p in $edgePaths) {
    if ($p -and (Test-Path $p)) {
        $edgeExe = $p
        break
    }
}

if (-not $edgeExe) {
    Write-Error "未找到 Microsoft Edge 浏览器，无法执行界面截图。"
    exit 1
}

$port = 5173
$baseUrl = "http://127.0.0.1:$port"

# 检查 Vite 开发服务器是否处于监听状态
$conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
if (-not $conn) {
    Write-Host "Vite 服务未在端口 $port 运行，正在启动临时前端服务..." -ForegroundColor Yellow
    $frontendDir = Join-Path $rootDir "Windows\frontend"
    $viteProcess = Start-Process -FilePath "npx.cmd" -ArgumentList "vite", "--host", "127.0.0.1", "--port", "$port" -WorkingDirectory $frontendDir -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 3
}

$allTabs = @("dashboard", "adapters", "upstream", "cache", "rules", "logs", "settings")
$targetTabs = if ($Tab -eq "all") { $allTabs + @("modal-alert") } else { @($Tab) }
$targetThemes = if ($Theme -eq "both") { @("dark", "light") } else { @($Theme) }

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "谛听 (DITING) 界面截图接口生成器" -ForegroundColor Cyan
Write-Host "分辨率: ${Width}x${Height} | 输出目录: $OutputDir" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

foreach ($t in $targetThemes) {
    foreach ($item in $targetTabs) {
        $fileName = if ($item -eq "modal-alert") {
            "${t}_modal_alert.png"
        } else {
            "${t}_tab_${item}.png"
        }

        $outFile = Join-Path $OutputDir $fileName
        $targetUrl = if ($item -eq "modal-alert") {
            "$baseUrl/?modal=alert&theme=$t"
        } else {
            "$baseUrl/?noalert=1&mock=1&theme=$t#/$item"
        }

        Write-Host "正在截取界面 [$t] -> $item..." -NoNewline

        $argsList = @(
            "--headless",
            "--disable-gpu",
            "--screenshot=$outFile",
            "--window-size=$Width,$Height",
            "$targetUrl"
        )

        $proc = Start-Process -FilePath $edgeExe -ArgumentList $argsList -PassThru -Wait -WindowStyle Hidden
        if (Test-Path $outFile) {
            $size = (Get-Item $outFile).Length
            Write-Host " 完成! ($([Math]::Round($size / 1024, 1)) KB)" -ForegroundColor Green
        } else {
            Write-Host " 失败" -ForegroundColor Red
        }
    }
}

Write-Host "所有请求的页面截图已输出至: $OutputDir" -ForegroundColor Cyan
