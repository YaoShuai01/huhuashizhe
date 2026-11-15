# 护花使者飞控固件（基于 rtlopez/esp-fc，MIT）构建/烧录脚本
#
# 依赖：
#   - arduino-cli 1.6+（命令需在 PATH 中，或设置环境变量 ARDUINO_CLI）
#   - ESP32 Arduino core 3.3.11（arduino-cli core install esp32:esp32@3.3.11）
#
# 用法：
#   .\build.ps1                 仅编译
#   .\build.ps1 -Flash          编译并烧录（默认 COM6）
#   .\build.ps1 -Flash -Port COM6
#
# 注意：
#   - 首次烧录前建议先备份原固件；本工程默认使用 2MB 分区表（app 1.875MB）。
#   - 编译产物在 %TEMP%\hhs_espfc_build。

param(
    [switch]$Flash,
    [string]$Port = "COM6"
)

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$build = Join-Path $env:TEMP "hhs_espfc_build"

$cli = $env:ARDUINO_CLI
if (-not $cli) {
    $cmd = Get-Command arduino-cli -ErrorAction SilentlyContinue
    if ($cmd) { $cli = $cmd.Source }
}
if (-not $cli -or -not (Test-Path $cli)) {
    throw "未找到 arduino-cli，请先安装并加入 PATH，或设置环境变量 ARDUINO_CLI"
}

# ESP32-S3：原生 USB CDC + UART0(CH343) 双 MSP，2MB 自定义分区，关闭 PSRAM
# 飞控实测为 ESP32-S3 N16R8：16MB Flash + 8MB PSRAM，Flash 为 DIO 80MHz
$fqbn = "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=dio,FlashSize=16M,PartitionScheme=custom,PSRAM=disabled,CPUFreq=240,UploadMode=default"

# 所有库源码已放在 src/libs 下，直接给编译器 include 根目录
$inc = @(
    "-I$build/sketch/src/libs/Espfc",
    "-I$build/sketch/src/libs/Hal/include",
    "-I$build/sketch/src/libs/Hal/src",
    "-I$build/sketch/src/libs/AHRS",
    "-I$build/sketch/src/libs/betaflight",
    "-I$build/sketch/src/libs/EscDriver",
    "-I$build/sketch/src/libs/Gps",
    "-I$build/sketch/src/libs/MultiButton",
    "-I$build/sketch/src/libs/printf"
) -join " "

$common = "-DESP32S3 -DESPFC_HAL_QUEUE_FREERTOS -DESPFC_UDP_RX -DESPFC_HHS_PRESET"
$cppFlags = "$common -DARDUINO_USB_MODE=1 -DARDUINO_USB_CDC_ON_BOOT=1 -std=gnu++17 $inc"
$cFlags = "$common $inc"

Write-Host "编译 $here ..." -ForegroundColor Cyan
& $cli compile -b $fqbn `
    --build-path $build `
    --build-property "build.flash_size=16MB" `
    --build-property "compiler.cpp.extra_flags=$cppFlags" `
    --build-property "compiler.c.extra_flags=$cFlags" `
    $here
if ($LASTEXITCODE -ne 0) { throw "编译失败" }

$bin = Join-Path $build "esp32_drone_espfc.ino.bin"
Write-Host "编译完成: $bin" -ForegroundColor Green

if ($Flash) {
    Write-Host "烧录到 $Port ..." -ForegroundColor Cyan
    & $cli upload -b $fqbn -p $Port --input-dir $build $here
    if ($LASTEXITCODE -ne 0) { throw "烧录失败" }
    Write-Host "烧录完成。烧录后请断电重启，并连接 WiFi: HuHuaShiZhe-Drone" -ForegroundColor Green
}
