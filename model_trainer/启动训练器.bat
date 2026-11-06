@echo off
chcp 65001 >nul
title 护花使者 - 虫害识别模型训练器
set PYTHONUTF8=1
cd /d "%~dp0"

rem ---------- 选择 Python：优先本机 Python 3.12（ML 生态兼容性最好） ----------
set "PY="
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PY (
    py -3.12 -c "import sys" >nul 2>&1 && set "PY=py -3.12"
)
if not defined PY set "PY=python"

rem ---------- 首次运行自动安装依赖 ----------
%PY% -c "import ultralytics, PySide6, matplotlib" >nul 2>&1
if errorlevel 1 (
    echo [首次运行] 正在安装依赖（含 PyTorch，约需 10~30 分钟，取决于网速）...
    %PY% -m pip install -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt
    rem 有 NVIDIA 显卡则补装 CUDA 版 PyTorch（失败自动用 CPU 版）
    nvidia-smi >nul 2>&1 && (
        echo [首次运行] 检测到 NVIDIA 显卡，安装 GPU 版 PyTorch...
        %PY% -m pip install --index-url https://download.pytorch.org/whl/cu128 torch torchvision
        %PY% -c "import torch; assert torch.cuda.is_available()" >nul 2>&1 || (
            echo [提示] GPU 版安装失败，回退 CPU 版...
            %PY% -m pip install torch torchvision
        )
    ) || (
        %PY% -m pip install torch torchvision
    )
)

%PY% main.py
if errorlevel 1 pause
