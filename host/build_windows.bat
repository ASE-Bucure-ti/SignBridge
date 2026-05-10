@echo off
REM ════════════════════════════════════════════════════════════════════════
REM  SignBridge — Windows Build Script
REM  Builds a one-dir PyInstaller bundle in dist\SignBridge\
REM ════════════════════════════════════════════════════════════════════════

echo ========================================
echo  SignBridge - Production Build (Windows)
echo ========================================
echo.

set "SIGN_HELPER=%~dp0packagers\windows\sign-artifact.bat"
set "PYTHON_CMD="

REM ── Check Python ──────────────────────────────────────────────────────
where py >nul 2>&1
if not errorlevel 1 (
    set "PYTHON_CMD=py -3.11"
) else if exist "%USERPROFILE%\.pyenv\pyenv-win\versions\3.12.2\python.exe" (
    set "PYTHON_CMD=%USERPROFILE%\.pyenv\pyenv-win\versions\3.12.2\python.exe"
) else (
    where python.exe >nul 2>&1
    if not errorlevel 1 (
        set "PYTHON_CMD=python.exe"
    )
)

if "%PYTHON_CMD%"=="" (
    echo ERROR: Python is not installed or not in PATH
    echo Install Python from https://python.org or ensure python.exe is available in PATH
    exit /b 1
)

echo [1/5] Checking Python version...
%PYTHON_CMD% --version

REM ── Virtual environment ───────────────────────────────────────────────
if not exist "venv" (
    echo [2/5] Creating virtual environment...
    %PYTHON_CMD% -m venv venv
    if %ERRORLEVEL% neq 0 (
        echo ERROR: Failed to create virtual environment
        exit /b 1
    )
) else (
    echo [2/5] Using existing virtual environment...
)

echo [3/5] Activating virtual environment...
call venv\Scripts\activate.bat

REM ── Install dependencies ──────────────────────────────────────────────
echo [4/5] Installing dependencies...
pip install --upgrade pip
pip install -r requirements.txt
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to install dependencies
    exit /b 1
)

REM ── Verify PKCS#11 library ───────────────────────────────────────────
if not exist "libs\eTPKCS11.dll" (
    echo WARNING: libs\eTPKCS11.dll not found
    echo HSM operations will require the vendor library at runtime
    echo.
)

REM ── Clean previous build ──────────────────────────────────────────────
if exist "dist" rmdir /s /q dist
if exist "build" rmdir /s /q build

REM ── Build ─────────────────────────────────────────────────────────────
echo [5/6] Building with PyInstaller...
echo.
pyinstaller --clean signbridge.spec
if %ERRORLEVEL% neq 0 (
    echo.
    echo ========================================
    echo  BUILD FAILED
    echo ========================================
    exit /b 1
)

echo.
if exist "dist\SignBridge\SignBridge.exe" (
    echo [6/6] Signing native host executable...
    call "%SIGN_HELPER%" "%~dp0dist\SignBridge\SignBridge.exe"
    if %ERRORLEVEL% neq 0 (
        echo ========================================
        echo  SIGNING FAILED
        echo ========================================
        exit /b 1
    )

    echo ========================================
    echo  BUILD SUCCESSFUL
    echo ========================================
    echo.
    echo Executable: dist\SignBridge\SignBridge.exe
    echo.
    for %%A in ("dist\SignBridge\SignBridge.exe") do echo Size: %%~zA bytes
    echo.
    echo Next steps:
    echo   1. Run install\register_host.py to register with browsers
    echo   2. Load the extension in Chrome/Edge/Firefox
    echo   3. Test from the web app
    echo.
) else (
    echo ========================================
    echo  BUILD FAILED — no executable produced
    echo ========================================
    exit /b 1
)

call venv\Scripts\deactivate.bat 2>nul
if "%CI%"=="" pause
