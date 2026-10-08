<#
.SYNOPSIS
    谛听 (DITING) Windows 端构建脚本 (diting-service & diting-gui & nsis-installer)

.DESCRIPTION
    一键编译 Windows 平台特权服务 (diting-service.exe)、Wails GUI 前端客户端 (diting-gui.exe)
    以及集成了特权服务与自动安装注册的独立 NSIS 安装包。
    支持自动版本注入、安装包规范命名（如 DITING-release-v1.3.0.exe）及中间调试产物清理。

.PARAMETER Target
    构建目标: all (默认，完整安装包并清理中间体), service (仅特权服务), gui (仅GUI客户端), installer (仅打包安装包)

.PARAMETER Version
    应用版本号，默认 1.3.0 (如 1.3.0)

.PARAMETER BuildType
    构建类型: release (默认), debug

.PARAMETER Clean
    在构建前清理 build/bin 输出目录

.PARAMETER SkipCheck
    跳过前置依赖工具链环境检查
#>

[CmdletBinding()]
param (
    [ValidateSet("all", "service", "gui", "installer")]
    [string]$Target = "all",

    [string]$Version = "1.3.0",

    [ValidateSet("release", "debug")]
    [string]$BuildType = "release",

    [switch]$Clean,

    [switch]$SkipCheck
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# --- 目录与元数据配置 ---
$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ($scriptDir) {
    $scriptDir = (Resolve-Path $scriptDir).Path
} else {
    $scriptDir = $pwd.Path
}
$rootDir = (Resolve-Path (Join-Path $scriptDir "..")).Path
$windowsDir = (Resolve-Path (Join-Path $rootDir "Windows")).Path
$binDir = Join-Path $windowsDir "build\bin"

$version = $Version
$buildType = $BuildType.ToLower()

$gitCommit = try { (git -C $rootDir rev-parse --short HEAD 2>$null) } catch { "unknown" }
if (-not $gitCommit) { $gitCommit = "unknown" }
$buildTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")

# 根据构建类型配置 ldflags 及 Wails 参数
if ($buildType -eq "release") {
    $ldflags = "-s -w -X 'main.Version=$version' -X 'main.GitCommit=$gitCommit' -X 'main.BuildTime=$buildTime'"
    $wailsExtraArgs = @()
} else {
    $ldflags = "-X 'main.Version=$version' -X 'main.GitCommit=$gitCommit' -X 'main.BuildTime=$buildTime'"
    $wailsExtraArgs = @("-debug")
}

$finalInstallerName = "DITING-$buildType-v$version.exe"
$finalInstallerPath = Join-Path $binDir $finalInstallerName

# --- 辅助函数 ---

function Write-Banner {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  谛听 (DITING) Windows 构建工具" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  构建目标 : $Target" -ForegroundColor White
    Write-Host "  应用版本 : $version" -ForegroundColor White
    Write-Host "  构建类型 : $buildType" -ForegroundColor White
    Write-Host "  Git 提交 : $gitCommit" -ForegroundColor White
    Write-Host "  构建时间 : $buildTime" -ForegroundColor White
    Write-Host "  输出路径 : $binDir" -ForegroundColor White
    if ($Target -in @("all", "installer")) {
        Write-Host "  预期安装包: $finalInstallerName" -ForegroundColor White
    }
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Format-FileSize([long]$Bytes) {
    if ($Bytes -ge 1GB) {
        return "$([Math]::Round($Bytes / 1GB, 2)) GB ($('{0:N0}' -f $Bytes) 字节)"
    }
    if ($Bytes -ge 1MB) {
        return "$([Math]::Round($Bytes / 1MB, 2)) MB ($('{0:N0}' -f $Bytes) 字节)"
    }
    if ($Bytes -ge 1KB) {
        return "$([Math]::Round($Bytes / 1KB, 2)) KB ($('{0:N0}' -f $Bytes) 字节)"
    }
    return "$Bytes 字节"
}

function Test-BuildPrerequisites {
    Write-Host "正在检查构建环境工具链..." -ForegroundColor DarkGray

    # 1. Go
    $goCmd = Get-Command go -ErrorAction SilentlyContinue
    if (-not $goCmd) {
        throw "未找到 Go 编译环境，请确保 Go 已安装并配置在系统 PATH 中。"
    }
    $goVer = (go version) -replace "^go version ", ""
    Write-Host "  ➜ Go 工具链    : $goVer" -ForegroundColor DarkGray

    # 2. Wails (对于 gui, installer, all 目标)
    if ($Target -in @("gui", "installer", "all")) {
        $wailsCmd = Get-Command wails -ErrorAction SilentlyContinue
        if (-not $wailsCmd) {
            throw "未找到 Wails CLI，请执行: go install github.com/wailsapp/wails/v2/cmd/wails@latest"
        }
        $wailsVer = (wails version 2>$null | Select-Object -First 1)
        Write-Host "  ➜ Wails CLI     : $wailsVer" -ForegroundColor DarkGray

        # 3. Node & npm
        $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
        if (-not $nodeCmd) {
            throw "未找到 Node.js 环境，前端客户端编译需要 Node.js 与 npm 支持。"
        }
        $nodeVer = (node -v)
        Write-Host "  ➜ Node.js 环境  : $nodeVer" -ForegroundColor DarkGray
    }

    # 4. NSIS (对于 installer, all 目标)
    if ($Target -in @("installer", "all")) {
        $makensisCmd = Get-Command makensis -ErrorAction SilentlyContinue
        if (-not $makensisCmd) {
            $defaultNsisDirs = @(
                "C:\Program Files (x86)\NSIS",
                "C:\Program Files\NSIS"
            )
            foreach ($dir in $defaultNsisDirs) {
                if (Test-Path (Join-Path $dir "makensis.exe")) {
                    $env:PATH = "$dir;$env:PATH"
                    $makensisCmd = Get-Command makensis -ErrorAction SilentlyContinue
                    break
                }
            }
        }
        if (-not $makensisCmd) {
            throw "未找到 NSIS (makensis.exe)，打包安装包需要安装 NSIS 并加入 PATH。"
        }
        Write-Host "  ➜ NSIS 编译器   : $($makensisCmd.Source)" -ForegroundColor DarkGray
    }

    Write-Host "  ✔ 环境工具链检测通过`n" -ForegroundColor DarkGreen
}

function Sync-NsisVersion {
    $projectNsiPath = Join-Path $windowsDir "build\windows\installer\project.nsi"
    if (Test-Path $projectNsiPath) {
        $cleanNsisVersion = ($version -replace '^[vV]', '') -replace '-.*$', ''
        $parts = $cleanNsisVersion.Split('.')
        while ($parts.Count -lt 3) { $parts += "0" }
        $nsisVer = ($parts[0..2] -join '.')
        $nsiContent = [System.IO.File]::ReadAllText($projectNsiPath, [System.Text.Encoding]::UTF8)
        $nsiContent = [System.Text.RegularExpressions.Regex]::Replace($nsiContent, '!define INFO_PRODUCTVERSION\s+".*?"', "!define INFO_PRODUCTVERSION `"$nsisVer`"")
        [System.IO.File]::WriteAllText($projectNsiPath, $nsiContent, [System.Text.Encoding]::UTF8)
        Write-Host "  ➜ 同步 NSIS INFO_PRODUCTVERSION: $nsisVer" -ForegroundColor DarkGray
    }
}

function Stop-RunningProcesses {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match "diting-gui.*installer" -or
        $_.ProcessName -match "diting-gui" -or
        $_.ProcessName -match "^DITING-" -or
        $_.ProcessName -eq "diting-service"
    }
    if ($procs) {
        $names = ($procs | ForEach-Object { "$($_.ProcessName) (PID: $($_.Id))" }) -join ", "
        Write-Host "  ➜ 检测到可能锁定文件的运行中进程，正在安全终止: $names" -ForegroundColor Yellow
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
}

function Build-Service {
    Push-Location $windowsDir
    try {
        $outFile = Join-Path $binDir "diting-service.exe"
        Write-Host "  ➜ 目标产物: $outFile" -ForegroundColor DarkGray
        Write-Host "  ➜ 执行命令: go build -ldflags ... -o $outFile ./cmd/service" -ForegroundColor DarkGray
        & go build -ldflags $ldflags -o $outFile ./cmd/service
        if ($LASTEXITCODE -ne 0) {
            throw "Go 编译特权服务失败 (exit code: $LASTEXITCODE)"
        }
    }
    finally {
        Pop-Location
    }
}

function Build-Gui {
    Stop-RunningProcesses
    Push-Location $windowsDir
    try {
        $wailsCmdArgs = @("build", "-ldflags", $ldflags) + $wailsExtraArgs
        Write-Host "  ➜ 执行命令: wails $($wailsCmdArgs -join ' ')" -ForegroundColor DarkGray
        & wails @wailsCmdArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Wails 构建 GUI 客户端失败 (exit code: $LASTEXITCODE)"
        }
    }
    finally {
        Pop-Location
    }
}

function Build-InstallerPackage {
    Sync-NsisVersion
    Stop-RunningProcesses
    Push-Location $windowsDir
    try {
        $wailsCmdArgs = @("build", "-nsis", "-ldflags", $ldflags) + $wailsExtraArgs
        Write-Host "  ➜ 执行命令: wails $($wailsCmdArgs -join ' ')" -ForegroundColor DarkGray
        & wails @wailsCmdArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Wails 构建 NSIS 安装包失败 (exit code: $LASTEXITCODE)"
        }
    }
    finally {
        Pop-Location
    }
}

function Finalize-InstallerArtifacts {
    # 查找新生成的安装程序
    $generatedInstaller = Get-ChildItem -Path $binDir -Filter "*installer.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $generatedInstaller) {
        $generatedInstaller = Get-ChildItem -Path $binDir -Filter "diting-gui-*-installer.exe" | Select-Object -First 1
    }

    if (-not $generatedInstaller) {
        throw "未能定位到生成的 NSIS 安装包文件 (搜索目录: $binDir)"
    }

    if (Test-Path $finalInstallerPath) {
        Remove-Item -Path $finalInstallerPath -Force
    }
    Move-Item -Path $generatedInstaller.FullName -Destination $finalInstallerPath -Force
    Write-Host "  ➜ 规范命名产物: $finalInstallerName" -ForegroundColor Green

    # 清理中间二进制产物，确保输出目录仅保留最终安装包
    Write-Host "  ➜ 清理中间二进制产物与调试临时文件..." -ForegroundColor DarkGray
    $removedCount = 0
    Get-ChildItem -Path $binDir -File | Where-Object { $_.Name -ne $finalInstallerName } | ForEach-Object {
        Write-Host "    - 移除中间文件: $($_.Name)" -ForegroundColor DarkGray
        Remove-Item -Path $_.FullName -Force
        $removedCount++
    }
    if ($removedCount -gt 0) {
        Write-Host "  ✔ 已清理 $removedCount 个中间文件，输出目录已净化" -ForegroundColor DarkGray
    }
}

# --- 执行入口与计划调度 ---

Write-Banner

if (-not $SkipCheck) {
    Test-BuildPrerequisites
}

if ($Clean) {
    if (Test-Path $binDir) {
        Write-Host "清理输出目录: $binDir" -ForegroundColor Yellow
        Remove-Item -Recurse -Force $binDir
    }
}

if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

# 规划构建步骤流水线
$pipeline = [System.Collections.Generic.List[PSCustomObject]]::new()

if ($Target -eq "service") {
    $pipeline.Add([PSCustomObject]@{
        Title  = "编译内核特权服务 (diting-service.exe)"
        Action = { Build-Service }
    })
}
elseif ($Target -eq "gui") {
    $pipeline.Add([PSCustomObject]@{
        Title  = "编译前端 GUI 客户端 (diting-gui.exe)"
        Action = { Build-Gui }
    })
}
elseif ($Target -eq "installer") {
    $serviceExe = Join-Path $binDir "diting-service.exe"
    if (-not (Test-Path $serviceExe)) {
        $pipeline.Add([PSCustomObject]@{
            Title  = "编译内核特权服务依赖 (diting-service.exe)"
            Action = { Build-Service }
        })
    }
    $pipeline.Add([PSCustomObject]@{
        Title  = "编译前端客户端并构建 NSIS 安装包"
        Action = { Build-InstallerPackage }
    })
    $pipeline.Add([PSCustomObject]@{
        Title  = "规范化安装包产物命名并清理中间调试产物"
        Action = { Finalize-InstallerArtifacts }
    })
}
elseif ($Target -eq "all") {
    $pipeline.Add([PSCustomObject]@{
        Title  = "编译内核特权服务 (diting-service.exe)"
        Action = { Build-Service }
    })
    $pipeline.Add([PSCustomObject]@{
        Title  = "编译前端客户端并构建一体化 NSIS 安装包"
        Action = { Build-InstallerPackage }
    })
    $pipeline.Add([PSCustomObject]@{
        Title  = "规范化安装包产物命名并清理中间调试产物"
        Action = { Finalize-InstallerArtifacts }
    })
}

$totalSteps = $pipeline.Count
$totalSw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    for ($i = 0; $i -lt $totalSteps; $i++) {
        $stepNumber = $i + 1
        $step = $pipeline[$i]
        Write-Host "[$stepNumber/$totalSteps] $($step.Title)..." -ForegroundColor Cyan
        $stepSw = [System.Diagnostics.Stopwatch]::StartNew()

        & $step.Action

        $stepSw.Stop()
        Write-Host "  ✔ 步骤完成 (耗时: $($stepSw.Elapsed.TotalSeconds.ToString('F2'))s)`n" -ForegroundColor Green
    }

    $totalSw.Stop()

    # 汇总产物清单
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  构建成功完成！ (总耗时: $($totalSw.Elapsed.TotalSeconds.ToString('F2'))s)" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green

    $expectedFiles = @()
    if ($Target -eq "service") {
        $expectedFiles += (Join-Path $binDir "diting-service.exe")
    }
    elseif ($Target -eq "gui") {
        $expectedFiles += (Join-Path $binDir "diting-gui.exe")
    }
    elseif ($Target -in @("installer", "all")) {
        $expectedFiles += $finalInstallerPath
    }

    foreach ($file in $expectedFiles) {
        if (Test-Path $file) {
            $item = Get-Item $file
            $sizeStr = Format-FileSize $item.Length
            $hashStr = (Get-FileHash -Path $file -Algorithm SHA256).Hash
            Write-Host "  产物名称 : $($item.Name)" -ForegroundColor Cyan
            Write-Host "  产物路径 : $($item.FullName)" -ForegroundColor White
            Write-Host "  文件大小 : $sizeStr" -ForegroundColor White
            Write-Host "  SHA-256  : $hashStr" -ForegroundColor White
            Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
        }
    }
}
catch {
    $totalSw.Stop()
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "  构建失败！ (总耗时: $($totalSw.Elapsed.TotalSeconds.ToString('F2'))s)" -ForegroundColor Red
    Write-Host "  错误详情: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    exit 1
}
