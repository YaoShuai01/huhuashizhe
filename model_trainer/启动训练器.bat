@echo off
rem HHSZ Model Trainer launcher (ASCII only to avoid codepage issues)
title HHSZ Model Trainer
set PYTHONUTF8=1
cd /d "%~dp0"

rem ---------- Pick Python: prefer local Python 3.12 (best ML ecosystem support) ----------
set "PY="
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PY (
    py -3.12 -c "import sys" >nul 2>&1 && set "PY=py -3.12"
)
if not defined PY set "PY=python"

rem ---------- First run: auto install dependencies ----------
%PY% -c "import ultralytics, PySide6, matplotlib" >nul 2>&1
if errorlevel 1 (
    echo [FIRST RUN] Installing dependencies, please wait 10-30 minutes...
    %PY% -m pip install -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt
    rem If NVIDIA GPU present, install CUDA build of PyTorch (fallback to CPU on failure)
    nvidia-smi >nul 2>&1 && (
        echo [FIRST RUN] NVIDIA GPU detected, installing CUDA PyTorch...
        %PY% -m pip install --index-url https://download.pytorch.org/whl/cu128 torch torchvision
        %PY% -c "import torch; assert torch.cuda.is_available()" >nul 2>&1 || (
            echo [WARN] CUDA install failed, falling back to CPU build...
            %PY% -m pip install torch torchvision
        )
    ) || (
        %PY% -m pip install torch torchvision
    )
)

echo [START] Launching trainer GUI...
%PY% main.py
if errorlevel 1 (
    echo.
    echo [ERROR] Trainer exited with an error. Check messages above.
    pause
)
