@echo off
REM ════════════════════════════════════════════════════════════════════════
REM  SignBridge — Windows Build Script
REM  Builds a one-dir PyInstaller bundle in dist\SignBridge\
REM ════════════════════════════════════════════════════════════════════════

echo ========================================
echo  SignBridge - Production Build (Windows)
echo ========================================
echo.

REM ── Check Python ──────────────────────────────────────────────────────
where py >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Python launcher ^(py^) is not installed or not in PATH
    echo Download from https://python.org
    exit /b 1
)

echo [1/5] Checking Python version...
py -3.11 --version

REM ── Virtual environment ───────────────────────────────────────────────
if not exist "venv" (
    echo [2/5] Creating virtual environment...
    py -3.11 -m venv venv
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
echo [5/5] Building with PyInstaller...
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
pause
