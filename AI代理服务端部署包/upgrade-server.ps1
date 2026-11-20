<#
  护花使者后端升级（AI 代理版）
  ------------------------------------------------------------------
  把 schedule.war 和本脚本复制到服务器（RDP 直接拷贝），以管理员身份执行：

      powershell -ExecutionPolicy Bypass -File .\upgrade-server.ps1 `
          -War .\schedule.war -AiApiKey "sk-xxxx"

  脚本会：停止服务 -> 备份旧 WAR 与配置 -> 部署新 WAR -> 写入 AI 配置 -> 启动服务 -> 健康检查。
  其他配置项（schedule.key / admin.key / token.secret / db.path）原样保留。
  注意：ai.api.key 只保存在服务器 config.properties，禁止提交到 Git。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$War,
    [Parameter(Mandatory = $true)][string]$AiApiKey,
    [string]$AiBaseUrl = 'https://maas.qianwenaiapi.com/compatible-mode/v1',
    [string]$AiModel = 'qwen3.8-flash',
    [string]$InstallDir = 'C:\huhuashizhe',
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ServiceName = 'HuHuaShiZheSchedule'
$warPath = (Resolve-Path $War).Path
if ([IO.Path]::GetExtension($warPath).ToLower() -ne '.war') {
    throw "不是 WAR 文件：$warPath"
}
$AiApiKey = $AiApiKey.Trim()
if (-not $AiApiKey) {
    throw 'ai.api.key 不能为空'
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw '请右键“以管理员身份运行” PowerShell，再执行本脚本'
}

$tomcatDir = Join-Path $InstallDir 'tomcat'
$webappsDir = Join-Path $tomcatDir 'webapps'
$configFile = Join-Path $InstallDir 'config\config.properties'
if (-not (Test-Path (Join-Path $tomcatDir 'bin\catalina.bat'))) {
    throw "未找到 Tomcat：$tomcatDir"
}
if (-not (Test-Path $configFile)) {
    throw "未找到配置文件：$configFile"
}

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

# ---------- 停止服务 ----------
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Write-Step "停止服务 $ServiceName"
    Stop-Service -Name $ServiceName -Force
    $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
}

# ---------- 备份 ----------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $InstallDir "backups\upgrade-$stamp"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$oldWar = Join-Path $webappsDir 'schedule.war'
if (Test-Path $oldWar) {
    Copy-Item $oldWar (Join-Path $backupDir 'schedule.war') -Force
}
Copy-Item $configFile (Join-Path $backupDir 'config.properties') -Force
Write-Step "已备份到 $backupDir"

# ---------- 部署 WAR ----------
Write-Step '部署新 schedule.war'
Remove-Item (Join-Path $webappsDir 'schedule') -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item $warPath (Join-Path $webappsDir 'schedule.war') -Force

# ---------- 更新 AI 配置（保留其他行） ----------
Write-Step '写入 AI 代理配置'
$lines = Get-Content $configFile -Encoding UTF8 | Where-Object {
    $_ -notmatch '^\s*ai\.(api\.key|base\.url|model)\s*='
}
$lines += "ai.api.key=$AiApiKey"
$lines += "ai.base.url=$AiBaseUrl"
$lines += "ai.model=$AiModel"
Write-Utf8NoBom $configFile (($lines -join "`r`n") + "`r`n")

# ---------- 启动服务 ----------
Write-Step "启动服务 $ServiceName"
Start-Service -Name $ServiceName
$service = Get-Service -Name $ServiceName
$service.WaitForStatus('Running', [TimeSpan]::FromSeconds(60))

# ---------- 健康检查 ----------
Write-Step '健康检查'
$ok = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 2
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/schedule/health" -TimeoutSec 5
        if ($health.ok) {
            $ok = $true
            break
        }
    } catch {
        # Tomcat 还在解压 WAR，稍后重试
    }
}
if (-not $ok) {
    throw '服务未在 30 秒内就绪，请查看 Tomcat 日志：' + (Join-Path $tomcatDir 'logs')
}

Write-Host ""
Write-Host "升级完成。AI 代理地址：http://<服务器IP>:$Port/schedule/ai/chat" -ForegroundColor Green
Write-Host "请勿把 $configFile 提交到 Git。" -ForegroundColor Yellow
