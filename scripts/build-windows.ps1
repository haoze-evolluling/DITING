<#
.SYNOPSIS
    谛听 (DITING) Windows 端构建脚本 (diting-service & diting-gui)

.DESCRIPTION
    一键编译 Windows 平台特权服务 (diting-service.exe) 与 Wails GUI 前端客户端 (diting-gui.exe)。

.PARAMETER Target
    构建目标: all (默认), service, gui

.PARAMETER Clean
    在构建前清理 build/bin 输出目录
#>

[CmdletBinding()]
param (
    [ValidateSet("all", "service", "gui")]
    [string]$Target = "all",

    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$windowsDir = Join-Path $rootDir "Windows"
$binDir = Join-Path $windowsDir "build\bin"

$version = "0.1.0-dev"
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
    Write-Host "[1/2] Building diting-service.exe..." -ForegroundColor Green
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
    Write-Host "[2/2] Building diting-gui.exe (Wails)..." -ForegroundColor Green
    Push-Location $windowsDir
    try {
        wails build -ldflags $ldflags
        Write-Host " -> Output: $(Join-Path $binDir 'diting-gui.exe')" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

switch ($Target) {
    "service" { Build-Service }
    "gui"     { Build-Gui }
    "all"     {
        Build-Service
        Build-Gui
    }
}

Write-Host "Build completed successfully." -ForegroundColor Cyan
