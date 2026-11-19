<#
  护花使者后端一键部署（Windows Server）
  ------------------------------------------------------------------
  把本目录整个复制到服务器（RDP 里直接拷贝即可），然后以管理员身份打开 PowerShell：

      powershell -ExecutionPolicy Bypass -File .\install-server.ps1 -PublicBaseUrl http://公网IP:8080

  目录内容：
      schedule.war          必填，后端 War 包
      install-server.ps1    本脚本
      migrate-db.ps1        数据迁移脚本（服务部署完成后再用）
      schedule.db           可选，旧数据（放到 migrate-db.ps1 同目录再执行迁移）

  脚本会完成：安装 JDK 17 + Tomcat 9、生成配置、部署轮协服务、
  创建静态下载目录、开放防火墙、注册 Windows 服务并配置每日数据库备份。
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\huhuashizhe',
    [int]$Port = 8080,
    [string]$PublicBaseUrl = '',
    [string]$JdkZip = '',
    [string]$TomcatZip = '',
    [string]$ScheduleKey = '',
    [string]$AdminKey = '',
    [string]$TokenSecret = '',
    [string]$DbFile = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ServiceName = 'HuHuaShiZheSchedule'
$TaskName = 'HuHuaShiZheDbBackup'

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Expand-Zip([string]$ZipPath, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw '请右键“以管理员身份运行” PowerShell，再执行本脚本'
}

$scriptDir = $PSScriptRoot
$warPath = Join-Path $scriptDir 'schedule.war'
if (-not (Test-Path $warPath)) {
    throw "缺少 schedule.war，请与本脚本放在同一目录：$scriptDir"
}
if ($PublicBaseUrl) {
    $PublicBaseUrl = $PublicBaseUrl.TrimEnd('/')
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$configDir = Join-Path $InstallDir 'config'
$dataDir = Join-Path $InstallDir 'data'
New-Item -ItemType Directory -Force -Path $configDir, $dataDir, (Join-Path $dataDir 'backups') | Out-Null

# 升级时先停掉旧服务，避免文件被占用
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Write-Step "停止旧服务 $ServiceName"
    Stop-Service -Name $ServiceName -Force
    $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
}

# ---------- JDK ----------
$jdkDir = Join-Path $InstallDir 'jdk'
if (-not (Test-Path (Join-Path $jdkDir 'bin\java.exe'))) {
    $jdkPackage = $JdkZip
    if (-not $jdkPackage) {
        $jdkPackage = Join-Path $env:TEMP 'huhuashizhe-jdk17.zip'
        Write-Step '下载 JDK 17（约 180MB）'
        $jdkUrls = @(
            'https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip',
            'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse'
        )
        $downloaded = $false
        foreach ($url in $jdkUrls) {
            try {
                Invoke-WebRequest -Uri $url -OutFile $jdkPackage -UseBasicParsing
                $downloaded = $true
                break
            } catch {
                Write-Warning "下载失败，尝试下一个地址：$url"
            }
        }
        if (-not $downloaded) {
            throw 'JDK 下载失败，请手动下载 JDK 17 压缩包，并用 -JdkZip 指定路径'
        }
    }
    Write-Step '解压 JDK'
    $jdkTemp = Join-Path $InstallDir '_jdk_tmp'
    Expand-Zip $jdkPackage $jdkTemp
    $jdkInner = Get-ChildItem $jdkTemp -Directory | Select-Object -First 1
    if (-not $jdkInner) { throw 'JDK 压缩包结构异常' }
    Move-Item $jdkInner.FullName $jdkDir
    Remove-Item $jdkTemp -Recurse -Force
} else {
    Write-Step 'JDK 已安装，跳过'
}

# ---------- Tomcat ----------
$tomcatDir = Join-Path $InstallDir 'tomcat'
if (-not (Test-Path (Join-Path $tomcatDir 'bin\catalina.bat'))) {
    $tomcatPackage = $TomcatZip
    if (-not $tomcatPackage) {
        Write-Step '解析 Tomcat 9 最新版本'
        $listing = Invoke-WebRequest -Uri 'https://mirrors.aliyun.com/apache/tomcat/tomcat-9/' -UseBasicParsing
        $versions = [regex]::Matches($listing.Content, 'v(9\.0\.\d+)/') |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object { [version]$_ } -Unique
        $latest = $versions | Select-Object -Last 1
        if (-not $latest) {
            throw '无法从阿里云镜像获取 Tomcat 版本，请手动下载后通过 -TomcatZip 指定'
        }
        $tomcatPackage = Join-Path $env:TEMP 'huhuashizhe-tomcat9.zip'
        $url = "https://mirrors.aliyun.com/apache/tomcat/tomcat-9/v$latest/bin/apache-tomcat-$latest-windows-x64.zip"
        Write-Step "下载 Tomcat $latest"
        Invoke-WebRequest -Uri $url -OutFile $tomcatPackage -UseBasicParsing
    }
    Write-Step '解压 Tomcat'
    $tomcatTemp = Join-Path $InstallDir '_tomcat_tmp'
    Expand-Zip $tomcatPackage $tomcatTemp
    $tomcatInner = Get-ChildItem $tomcatTemp -Directory | Select-Object -First 1
    if (-not $tomcatInner) { throw 'Tomcat 压缩包结构异常' }
    Move-Item $tomcatInner.FullName $tomcatDir
    Remove-Item $tomcatTemp -Recurse -Force
} else {
    Write-Step 'Tomcat 已安装，跳过'
}

# 修改监听端口
$serverXml = Join-Path $tomcatDir 'conf\server.xml'
$serverXmlText = [System.IO.File]::ReadAllText($serverXml)
$serverXmlText = [regex]::Replace($serverXmlText, 'port="8080"', "port=`"$Port`"")
[System.IO.File]::WriteAllText($serverXml, $serverXmlText, (New-Object System.Text.UTF8Encoding($false)))

# ---------- 服务配置 ----------
$configFile = Join-Path $configDir 'config.properties'
if (-not (Test-Path $configFile)) {
    Write-Step '生成服务配置'
    if (-not $ScheduleKey) {
        $ScheduleKey = Read-Host '请输入轮协密钥（成员在 App 里输入）'
    }
    if (-not $AdminKey) {
        $AdminKey = Read-Host '请输入管理员密钥（用于修改轮协表和发布版本）'
    }
    if (-not $ScheduleKey -or -not $AdminKey) { throw '两个密钥都不能为空' }
    if ($ScheduleKey -eq $AdminKey) { throw '轮协密钥和管理员密钥不能相同' }
    if (-not $TokenSecret) {
        $bytes = New-Object byte[] 32
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $TokenSecret = [Convert]::ToBase64String($bytes)
    } elseif ($TokenSecret.Length -lt 32) {
        throw 'token.secret 至少需要 32 位字符'
    }
    $secret = $TokenSecret
    $dbPath = (Join-Path $dataDir 'schedule.db').Replace('\', '/')
    $backupPath = (Join-Path $dataDir 'backups').Replace('\', '/')
    $configText = @"
schedule.key=$ScheduleKey
admin.key=$AdminKey
token.secret=$secret
db.path=$dbPath
backup.dir=$backupPath
member.token.ttl.seconds=31536000
admin.token.ttl.seconds=7776000
"@
    Write-Utf8NoBom $configFile $configText
} else {
    Write-Step '服务配置已存在，保留原密钥'
}

# Tomcat 启动参数
$setenvFile = Join-Path $tomcatDir 'bin\setenv.bat'
$setenvText = @"
set "JAVA_HOME=$jdkDir"
set "CATALINA_OPTS=-Xms128m -Xmx512m -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Dschedule.config=$configFile"
"@
Write-Utf8NoBom $setenvFile $setenvText

# Windows 服务（tomcat9.exe）不会读取 setenv.bat，必须通过系统环境变量传配置路径
[Environment]::SetEnvironmentVariable('SCHEDULE_CONFIG', $configFile, 'Machine')

# ---------- 部署 WAR ----------
Write-Step '部署 schedule.war'
$webappsDir = Join-Path $tomcatDir 'webapps'
if (-not (Test-Path $webappsDir)) { New-Item -ItemType Directory -Force -Path $webappsDir | Out-Null }
Remove-Item (Join-Path $webappsDir 'schedule') -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item $warPath (Join-Path $webappsDir 'schedule.war') -Force

# ---------- 静态下载目录与 App 配置 ----------
$rootDir = Join-Path $webappsDir 'ROOT'
$staticAppDir = Join-Path $rootDir 'app'
$staticConfigDir = Join-Path $rootDir 'config'
New-Item -ItemType Directory -Force -Path $staticAppDir, $staticConfigDir | Out-Null

$publicConfigFile = Join-Path $staticConfigDir 'schedule.json'
if ($PublicBaseUrl) {
    $configJson = @"
{
  "schemaVersion": 1,
  "apiBaseUrl": "$PublicBaseUrl/schedule"
}
"@
    Write-Utf8NoBom $publicConfigFile $configJson
} elseif (-not (Test-Path $publicConfigFile)) {
    throw '首次部署请用 -PublicBaseUrl 指定公网访问地址，例如：-PublicBaseUrl http://1.2.3.4:8080'
}

# ---------- 旧数据迁移（可选） ----------
if ($DbFile) {
    if (-not (Test-Path $DbFile)) { throw "找不到数据库文件：$DbFile" }
    $targetDb = Join-Path $dataDir 'schedule.db'
    if (Test-Path $targetDb) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item $targetDb (Join-Path $dataDir "schedule.db.before-migrate-$stamp") -Force
    }
    Write-Step "迁移旧数据库：$DbFile"
    Copy-Item $DbFile $targetDb -Force
    foreach ($suffix in @('-wal', '-shm')) {
        $extra = "$DbFile$suffix"
        if (Test-Path $extra) {
            Copy-Item $extra "$targetDb$suffix" -Force
        } else {
            Remove-Item "$targetDb$suffix" -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------- 防火墙 ----------
$ruleName = "HuHuaShiZhe-$Port"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    Write-Step "开放 Windows 防火墙端口 $Port"
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP `
        -LocalPort $Port -Action Allow | Out-Null
}

# ---------- Windows 服务 ----------
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Step "注册 Windows 服务 $ServiceName"
    Push-Location (Join-Path $tomcatDir 'bin')
    try {
        $env:JAVA_HOME = $jdkDir
        & cmd.exe /c "service.bat install $ServiceName" | Out-Host
    } finally {
        Pop-Location
    }
    & sc.exe config $ServiceName start= auto | Out-Null
    # 默认安装成 LocalService，SQLite 数据目录没有写权限，统一改成 LocalSystem
    & sc.exe config $ServiceName obj= LocalSystem | Out-Null
} else {
    Write-Step "服务已存在，直接启动"
    & sc.exe config $ServiceName obj= LocalSystem | Out-Null
}

Write-Step "启动服务 $ServiceName"
Start-Service -Name $ServiceName

# ---------- 每日数据库备份 ----------
Write-Step '配置每日数据库备份'
$backupScript = Join-Path $InstallDir 'backup-db.ps1'
$dbFile = Join-Path $dataDir 'schedule.db'
$dbBackupDir = Join-Path $dataDir 'db-backups'
$backupText = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$service = '$ServiceName'
`$db = '$dbFile'
`$dir = '$dbBackupDir'
New-Item -ItemType Directory -Force -Path `$dir | Out-Null
`$running = (Get-Service `$service).Status -eq 'Running'
if (`$running) { Stop-Service `$service -Force; Start-Sleep -Seconds 2 }
`$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (Test-Path `$db) { Copy-Item `$db (Join-Path `$dir "schedule-`$stamp.db") -Force }
if (`$running) { Start-Service `$service }
Get-ChildItem `$dir -Filter 'schedule-*.db' | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 14 | Remove-Item -Force
"@
Write-Utf8NoBom $backupScript $backupText
$taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$backupScript`""
& schtasks.exe /Create /F /TN $TaskName /SC DAILY /ST 03:30 /RU SYSTEM /TR $taskCommand | Out-Host

# ---------- 健康检查 ----------
Write-Step '等待服务启动并检查健康状态'
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
    Write-Warning '健康检查未通过，最近日志如下：'
    $log = Get-ChildItem (Join-Path $tomcatDir 'logs') -Filter 'catalina.*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log) { Get-Content $log.FullName -Tail 40 }
    exit 1
}

Write-Host ""
Write-Host '部署完成。' -ForegroundColor Green
Write-Host "轮协 API：$PublicBaseUrl/schedule"
Write-Host "健康检查：$PublicBaseUrl/schedule/health"
Write-Host "网页版：  $PublicBaseUrl/schedule/web"
Write-Host ''
Write-Host '还需要在阿里云控制台完成：' -ForegroundColor Yellow
Write-Host "  1. 安全组入方向放行 TCP $Port"
Write-Host '  2. 如果浏览器打不开，检查 Windows 防火墙规则 ' $ruleName
Write-Host '  3. 有了备案域名后，把 -PublicBaseUrl 换成 https://域名 重新执行本脚本即可'
