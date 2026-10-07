<#
.SYNOPSIS
    谛听 (DITING) Windows 端构建脚本 (diting-service & diting-gui & nsis-installer)

.DESCRIPTION
    一键编译 Windows 平台特权服务 (diting-service.exe)、Wails GUI 前端客户端 (diting-gui.exe)
    以及集成了特权服务与自动安装注册的独立 NSIS 安装包。

.PARAMETER Target
    构建目标: all (默认，含完整安装包), service, gui, installer

.PARAMETER Clean
    在构建前清理 build/bin 输出目录
#>

[CmdletBinding()]
param (
    [ValidateSet("all", "service", "gui", "installer")]
    [string]$Target = "all",

    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$windowsDir = Join-Path $rootDir "Windows"
$binDir = Join-Path $windowsDir "build\bin"

$version = "0.2.0-dev"
$gitCommit = try { (git -C $rootDir rev-parse --short HEAD 2>$null) } catch { "unknown" }
if (-not $gitCommit) { $gitCommit = "unknown" }
$buildTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")

$ldflags = "-s -w -X 'main.Version=$version' -X 'main.GitCommit=$gitCommit' -X 'main.BuildTime=$buildTime'"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "DITING Windows Build Script" -ForegroundColor Cyan
Write-Host "Target: $Target | Version: $version | Commit: $gitCommit" -ForegroundColor Cyan
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
    Push-Location $windowsDir
    try {
        wails build -ldflags $ldflags
        Write-Host " -> Output: $(Join-Path $binDir 'diting-gui.exe')" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

function Build-Installer {
    Write-Host "[3/3] Building Windows NSIS Installer (Bundle GUI & Service)..." -ForegroundColor Green
    # 确保特权服务二进制已就绪
    $serviceExe = Join-Path $binDir "diting-service.exe"
    if (-not (Test-Path $serviceExe)) {
        Write-Host " -> Privileged service not found, building it first..." -ForegroundColor Yellow
        Build-Service
    }
    # 若先前打开的安装程序尚未退出，先强制关闭以释放输出文件锁
    Get-Process -Name "diting-gui-amd64-installer" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Push-Location $windowsDir
    try {
        wails build -nsis -ldflags $ldflags
        Write-Host " -> Output Installer in: $binDir" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
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
