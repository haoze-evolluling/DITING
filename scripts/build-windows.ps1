<#
.SYNOPSIS
    谛听 (DITING) Windows 端构建脚本 (diting-service & diting-gui & nsis-installer)

.DESCRIPTION
    一键编译 Windows 平台特权服务 (diting-service.exe)、Wails GUI 前端客户端 (diting-gui.exe)
    以及集成了特权服务与自动安装注册的独立 NSIS 安装包。
    支持自动版本注入、安装包规范命名（如 DITING-release-v1.2.10.exe）及中间调试产物清理。

.PARAMETER Target
    构建目标: all (默认，完整安装包并清理中间体), service (仅特权服务), gui (仅GUI客户端), installer (仅打包安装包)

.PARAMETER Version
    应用版本号，默认 1.2.10 (如 1.2.10)

.PARAMETER BuildType
    构建类型: release (默认), debug

.PARAMETER Clean
    在构建前清理 build/bin 输出目录
#>

[CmdletBinding()]
param (
    [ValidateSet("all", "service", "gui", "installer")]
    [string]$Target = "all",

    [string]$Version = "1.2.10",

    [ValidateSet("release", "debug")]
    [string]$BuildType = "release",

    [switch]$Clean
)

$ErrorActionPreference = "Stop"

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

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "DITING Windows Build Script" -ForegroundColor Cyan
Write-Host "Target: $Target | Version: $version | BuildType: $buildType | Commit: $gitCommit" -ForegroundColor Cyan
Write-Host "Expected Installer: $finalInstallerName" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($Clean) {
    if (Test-Path $binDir) {
        Write-Host "Clean bin dir: $binDir" -ForegroundColor Yellow
        Remove-Item -Recurse -Force $binDir
    }
}

if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
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
        Write-Host " -> Synced NSIS INFO_PRODUCTVERSION to: $nsisVer" -ForegroundColor DarkGray
    }
}

function Stop-RunningProcesses {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match "diting-gui.*installer" -or
        $_.ProcessName -match "diting-gui" -or
        $_.ProcessName -match "^DITING-"
    }
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Build-Service {
    Write-Host "[1/3] Building diting-service.exe..." -ForegroundColor Green
    Push-Location $windowsDir
    try {
        $outFile = Join-Path $binDir "diting-service.exe"
        go build -ldflags $ldflags -o $outFile ./cmd/service
        Write-Host " -> Output: $outFile" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

function Build-Gui {
    Write-Host "[2/3] Building diting-gui.exe (Wails)..." -ForegroundColor Green
    Stop-RunningProcesses
    Push-Location $windowsDir
    try {
        $wailsCmdArgs = @("build", "-ldflags", $ldflags) + $wailsExtraArgs
        Write-Host " -> Running: wails $($wailsCmdArgs -join ' ')" -ForegroundColor DarkGray
        & wails @wailsCmdArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Wails build failed with exit code $LASTEXITCODE"
        }
        Write-Host " -> Output: $(Join-Path $binDir 'diting-gui.exe')" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

function Build-Installer {
    Write-Host "[3/3] Building Windows NSIS Installer (Bundle GUI & Service)..." -ForegroundColor Green

    # 同步 NSIS 属性中的版本号
    Sync-NsisVersion

    # 确保特权服务二进制已就绪（打包所需）
    $serviceExe = Join-Path $binDir "diting-service.exe"
    if (-not (Test-Path $serviceExe)) {
        Write-Host " -> Privileged service not found, building it first..." -ForegroundColor Yellow
        Build-Service
    }

    # 若先前打开的安装程序或主程序尚未退出，先强制关闭以释放输出文件锁
    Stop-RunningProcesses

    Push-Location $windowsDir
    try {
        $wailsCmdArgs = @("build", "-nsis", "-ldflags", $ldflags) + $wailsExtraArgs
        Write-Host " -> Running: wails $($wailsCmdArgs -join ' ')" -ForegroundColor DarkGray
        & wails @wailsCmdArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Wails build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    # 检索新生成的安装包文件
    $generatedInstaller = Get-ChildItem -Path $binDir -Filter "*installer.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $generatedInstaller) {
        $generatedInstaller = Get-ChildItem -Path $binDir -Filter "diting-gui-*-installer.exe" | Select-Object -First 1
    }

    if ($generatedInstaller) {
        if (Test-Path $finalInstallerPath) {
            Remove-Item -Path $finalInstallerPath -Force
        }
        Move-Item -Path $generatedInstaller.FullName -Destination $finalInstallerPath -Force
        Write-Host " -> Generated installer renamed to: $finalInstallerName" -ForegroundColor Green
    } else {
        throw "Failed to locate generated NSIS installer in $binDir"
    }

    # 清理中间二进制产物，确保输出目录只保留最终安装包
    Write-Host " -> Cleaning intermediate build artifacts from output directory..." -ForegroundColor Yellow
    Get-ChildItem -Path $binDir -File | Where-Object { $_.Name -ne $finalInstallerName } | ForEach-Object {
        Write-Host "    - Removed: $($_.Name)" -ForegroundColor DarkGray
        Remove-Item -Path $_.FullName -Force
    }

    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Installer package ready: $finalInstallerPath" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
}

switch ($Target) {
    "service"   { Build-Service }
    "gui"       { Build-Gui }
    "installer" { Build-Installer }
    "all"       {
        Build-Service
        Build-Installer
    }
}

Write-Host "Build completed successfully." -ForegroundColor Cyan
