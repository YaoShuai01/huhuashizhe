<#
  护花使者 App 一键发版（上传 APK 到阿里云服务器）
  ------------------------------------------------------------------
  在项目根目录执行：

      powershell -ExecutionPolicy Bypass -File .\tools\publish-update.ps1 -Apk .\护花使者_v3.2.0.apk -Notes "更新说明"

  可选参数：
      -ServerBaseUrl http://1.2.3.4:8080
      -AdminKey      管理员密钥（不填会提示输入）
      -Version       默认读取 lib/core/constants/app_version.dart

  脚本会用管理员密钥换取 token，把 APK 上传到服务器并写入 version.json；
  App 下次打开（或手动点检查更新）即可看到新版本。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [string]$Notes = '',
    [string]$Version = '',
    [string]$ServerBaseUrl = '',
    [string]$AdminKey = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

$repoRoot = Split-Path -Parent $PSScriptRoot

# ---------- 版本号校验 ----------
$versionFile = Join-Path $repoRoot 'lib\core\constants\app_version.dart'
$pubspecFile = Join-Path $repoRoot 'pubspec.yaml'
if (-not (Test-Path $versionFile) -or -not (Test-Path $pubspecFile)) {
    throw "请在项目根目录运行：找不到 $versionFile 或 $pubspecFile"
}
$dartVersion = [regex]::Match(
    (Get-Content $versionFile -Raw -Encoding UTF8), "appVersion\s*=\s*'([^']+)'"
).Groups[1].Value
$pubMatch = [regex]::Match(
    (Get-Content $pubspecFile -Raw -Encoding UTF8), '(?m)^version:\s*([\d.]+)\+(\d+)'
)
$pubVersion = $pubMatch.Groups[1].Value
$versionCode = [int]$pubMatch.Groups[2].Value

if (-not $Version) { $Version = $dartVersion }
if ($Version -ne $dartVersion -or $Version -ne $pubVersion) {
    throw "版本号不一致：参数=$Version，app_version.dart=$dartVersion，pubspec=$pubVersion。请先统一版本号再发版。"
}
if (-not ($Version -match '^\d+\.\d+\.\d+$')) {
    throw "版本号格式错误：$Version（应为 x.y.z）"
}

# ---------- APK 检查 ----------
$apkPath = (Resolve-Path $Apk).Path
if ([IO.Path]::GetExtension($apkPath).ToLower() -ne '.apk') {
    throw "不是 APK 文件：$apkPath"
}
$size = (Get-Item $apkPath).Length
if ($size -lt 1MB) {
    throw "APK 文件过小（$size 字节），请确认构建是否成功"
}
if ($Notes.Length -gt 1500) {
    throw '更新说明太长，请控制在 1500 字以内'
}

# ---------- 服务器与密钥 ----------
if (-not $ServerBaseUrl) {
    $ServerBaseUrl = Read-Host '服务器地址（例如 http://1.2.3.4:8080）'
}
$ServerBaseUrl = $ServerBaseUrl.TrimEnd('/')
if ($ServerBaseUrl -notmatch '^https?://') {
    throw "服务器地址必须以 http:// 或 https:// 开头：$ServerBaseUrl"
}
if (-not $AdminKey) {
    $AdminKey = Read-Host '管理员密钥'
}
if (-not $AdminKey) { throw '管理员密钥不能为空' }

# ---------- 认证 ----------
Write-Step '验证管理员密钥'
$authBody = @{ key = $AdminKey } | ConvertTo-Json -Compress
$auth = Invoke-RestMethod -Uri "$ServerBaseUrl/schedule/auth" -Method Post `
    -ContentType 'application/json' -Body $authBody -TimeoutSec 30
if (-not $auth.token -or $auth.role -ne 'admin') {
    throw '认证失败：请确认使用的是管理员密钥'
}

# ---------- 上传 ----------
Write-Step ("上传 APK（{0:N1} MB，版本 v{1}）" -f ($size / 1MB), $Version)
Write-Host '上传期间请保持网络畅通，不要关闭窗口...' -ForegroundColor Yellow
$query = "version=$Version&versionCode=$versionCode&notes=$([uri]::EscapeDataString($Notes))"
$uri = "$ServerBaseUrl/schedule/admin/publish?$query"
$response = Invoke-WebRequest -Uri $uri -Method Post -InFile $apkPath `
    -ContentType 'application/octet-stream' `
    -Headers @{ Authorization = "Bearer $($auth.token)" } `
    -UseBasicParsing -TimeoutSec 1800
$result = $response.Content | ConvertFrom-Json
if (-not $result.ok) {
    throw "上传失败：$($response.Content)"
}

# ---------- 校验 ----------
Write-Step '校验线上版本信息'
$online = Invoke-RestMethod -Uri "$ServerBaseUrl/schedule/version" -TimeoutSec 30
if ($online.versionName -ne $Version) {
    throw "发布校验失败：线上版本是 $($online.versionName)，期望 $Version"
}

Write-Host ''
Write-Host "发布成功：v$Version（versionCode=$versionCode，$([math]::Round($result.size / 1MB, 1)) MB）" -ForegroundColor Green
Write-Host "下载地址：$($result.downloadUrl)"
Write-Host "版本信息：$ServerBaseUrl/schedule/version"
Write-Host ''
Write-Host '提示：App 内的旧版本会在下次检查更新时看到此版本。' -ForegroundColor Yellow
