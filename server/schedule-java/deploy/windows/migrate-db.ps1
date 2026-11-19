<#
  护花使者轮协数据迁移（Windows Server）
  ------------------------------------------------------------------
  把旧电脑上的 schedule.db 复制到本脚本同目录，以管理员身份执行：

      powershell -ExecutionPolicy Bypass -File .\migrate-db.ps1

  脚本会：停止轮协服务 -> 备份服务器现有数据库 -> 覆盖为新的 schedule.db
  -> 启动服务 -> 健康检查。只会迁移一次，重复执行会再次覆盖。
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\huhuashizhe',
    [int]$Port = 8080,
    [string]$DbFile = ''
)

$ErrorActionPreference = 'Stop'
$ServiceName = 'HuHuaShiZheSchedule'

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw '请右键“以管理员身份运行” PowerShell，再执行本脚本'
}

if (-not $DbFile) {
    $DbFile = Join-Path $PSScriptRoot 'schedule.db'
}
if (-not (Test-Path $DbFile)) {
    throw "找不到数据库文件：$DbFile"
}

$dataDir = Join-Path $InstallDir 'data'
$target = Join-Path $dataDir 'schedule.db'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    throw "服务 $ServiceName 不存在，请先运行 install-server.ps1"
}
if ($service.Status -eq 'Running') {
    Write-Step '停止轮协服务'
    Stop-Service -Name $ServiceName -Force
    $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
}

if (Test-Path $target) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $dataDir "schedule.db.before-migrate-$stamp"
    Write-Step "备份服务器原数据库到 $backup"
    Copy-Item $target $backup -Force
}

Write-Step '复制新数据库'
Copy-Item $DbFile $target -Force
foreach ($suffix in @('-wal', '-shm')) {
    $extra = "$DbFile$suffix"
    if (Test-Path $extra) {
        Copy-Item $extra "$target$suffix" -Force
    } else {
        Remove-Item "$target$suffix" -Force -ErrorAction SilentlyContinue
    }
}

Write-Step '启动服务'
Start-Service -Name $ServiceName

$healthy = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 2
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/schedule/health" -TimeoutSec 5
        $healthy = $true
        Write-Host ("服务正常: " + ($health | ConvertTo-Json -Compress)) -ForegroundColor Green
        break
    } catch {
        # 继续等待
    }
}
if (-not $healthy) {
    throw '数据迁移后健康检查失败，请查看 Tomcat 日志'
}

Write-Host ''
Write-Host '数据迁移完成，请在 App 里刷新轮协表确认数据。' -ForegroundColor Green
