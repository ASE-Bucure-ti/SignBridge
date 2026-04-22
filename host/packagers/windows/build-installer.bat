@echo off
REM ════════════════════════════════════════════════════════════════════════
REM  SignBridge — Windows Installer Builder
REM
REM  Compiles the Inno Setup script to produce:
REM    host\installers\windows\SignBridge-Setup-X.Y.Z.exe
REM
REM  Prerequisites:
REM    1. Build the host first:  host\build_windows.bat
REM    2. Install Inno Setup 6+: https://jrsoftware.org/isdl.php
REM ════════════════════════════════════════════════════════════════════════

echo ========================================
echo  SignBridge - Installer Build (Windows)
echo ========================================
echo.

set "SIGN_HELPER=%~dp0sign-artifact.bat"
set "INSTALLER_PATH="

REM ── Locate Inno Setup compiler ────────────────────────────────────────
set "ISCC="

if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files\Inno Setup 6\ISCC.exe"
)

if "%ISCC%"=="" (
    echo ERROR: Inno Setup 6 not found.
    echo Download from https://jrsoftware.org/isdl.php
    exit /b 1
)

echo Found ISCC: %ISCC%
echo.

REM ── Check that the PyInstaller build exists ───────────────────────────
if not exist "%~dp0..\..\dist\SignBridge\SignBridge.exe" (
    echo ERROR: dist\SignBridge\SignBridge.exe not found.
    echo Run build_windows.bat first to build the native host.
    exit /b 1
)

echo [1/3] PyInstaller build found.

REM ── Compile the installer ─────────────────────────────────────────────
echo [2/3] Compiling installer...
echo.

"%ISCC%" "%~dp0signbridge-setup.iss"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ========================================
    echo  INSTALLER BUILD FAILED
    echo ========================================
    echo.
    echo If you get an antivirus error, try excluding
    echo the installers\windows folder from Windows Defender.
    exit /b 1
)

for /f "delims=" %%F in ('dir /b /o:-d "%~dp0..\..\installers\windows\SignBridge-Setup-*.exe"') do if not defined INSTALLER_PATH set "INSTALLER_PATH=%~dp0..\..\installers\windows\%%F"

if "%INSTALLER_PATH%"=="" (
    echo ERROR: Could not locate built installer in installers\windows.
    exit /b 1
)

echo [3/3] Signing installer...
call "%SIGN_HELPER%" "%INSTALLER_PATH%"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ========================================
    echo  INSTALLER SIGNING FAILED
    echo ========================================
    exit /b 1
)

echo.
echo ========================================
echo  INSTALLER BUILD SUCCESSFUL
echo ========================================
echo.
echo Output: %INSTALLER_PATH%
echo.

if "%CI%"=="" pause
