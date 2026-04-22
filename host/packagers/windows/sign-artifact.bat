@echo off
setlocal

REM Shared signing helper for Windows artifacts.
REM Environment overrides:
REM   SIGNBRIDGE_SIGNING=0                    Disable signing
REM   SIGNBRIDGE_SIGNTOOL=<path or command>   Default: signtool
REM   SIGNBRIDGE_CODESIGN_DLIB=<path>         Default: C:\tools\artifact-signing\packages\Microsoft.ArtifactSigning.Client\bin\x64\Azure.CodeSigning.Dlib.dll
REM   SIGNBRIDGE_CODESIGN_METADATA=<path>     Default: C:\tools\artifact-signing\metadata.json
REM   SIGNBRIDGE_TIMESTAMP_URL=<url>          Default: http://timestamp.acs.microsoft.com

if "%~1"=="" (
    echo ERROR: No file path provided to sign-artifact.bat
    exit /b 2
)

if /i "%SIGNBRIDGE_SIGNING%"=="0" (
    echo Signing disabled for %~nx1 ^(SIGNBRIDGE_SIGNING=0^)
    exit /b 0
)

set "TARGET_FILE=%~f1"
if not exist "%TARGET_FILE%" (
    echo ERROR: File to sign not found: %TARGET_FILE%
    exit /b 1
)

if not defined SIGNBRIDGE_SIGNTOOL set "SIGNBRIDGE_SIGNTOOL=signtool"
if not defined SIGNBRIDGE_CODESIGN_DLIB set "SIGNBRIDGE_CODESIGN_DLIB=C:\tools\artifact-signing\packages\Microsoft.ArtifactSigning.Client\bin\x64\Azure.CodeSigning.Dlib.dll"
if not defined SIGNBRIDGE_CODESIGN_METADATA set "SIGNBRIDGE_CODESIGN_METADATA=C:\tools\artifact-signing\metadata.json"
if not defined SIGNBRIDGE_TIMESTAMP_URL set "SIGNBRIDGE_TIMESTAMP_URL=http://timestamp.acs.microsoft.com"

if not exist "%SIGNBRIDGE_CODESIGN_DLIB%" (
    echo ERROR: Signing dlib not found: %SIGNBRIDGE_CODESIGN_DLIB%
    exit /b 1
)

if not exist "%SIGNBRIDGE_CODESIGN_METADATA%" (
    echo ERROR: Signing metadata not found: %SIGNBRIDGE_CODESIGN_METADATA%
    exit /b 1
)

echo Signing: %TARGET_FILE%
echo   SignTool: %SIGNBRIDGE_SIGNTOOL%
echo   Dlib: %SIGNBRIDGE_CODESIGN_DLIB%
echo   Metadata: %SIGNBRIDGE_CODESIGN_METADATA%

"%SIGNBRIDGE_SIGNTOOL%" sign /v /debug /fd SHA256 /td SHA256 /tr "%SIGNBRIDGE_TIMESTAMP_URL%" /dlib "%SIGNBRIDGE_CODESIGN_DLIB%" /dmdf "%SIGNBRIDGE_CODESIGN_METADATA%" "%TARGET_FILE%"
if %ERRORLEVEL% neq 0 (
    echo ERROR: Signing failed for %TARGET_FILE%
    exit /b 1
)

"%SIGNBRIDGE_SIGNTOOL%" verify /pa /v "%TARGET_FILE%"
if %ERRORLEVEL% neq 0 (
    echo ERROR: Signature verification failed for %TARGET_FILE%
    exit /b 1
)

echo Signature verified: %TARGET_FILE%
exit /b 0