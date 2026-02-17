; ════════════════════════════════════════════════════════════════════════════
;  SignBridge — Inno Setup Installer Script (Windows)
;
;  Packages the PyInstaller one-dir build and auto-registers the native
;  messaging host for Chrome, Edge, Brave, and Firefox.
;
;  Prerequisites:
;    1. Build the host first:  build_windows.bat
;    2. Install Inno Setup 6+:  https://jrsoftware.org/isinfo.php
;    3. Compile this script:  ISCC signbridge-setup.iss
;       Or open in Inno Setup GUI and press Ctrl+F9
;
;  Output: installers\windows\SignBridge-Setup-1.0.0.exe
; ════════════════════════════════════════════════════════════════════════════

#define MyAppName      "SignBridge"
#define MyAppVersion   "1.0.0"
#define MyAppPublisher "ASE"
#define MyAppURL       "https://github.com/ASE-Bucure-ti/SignBridge"
#define MyAppExeName   "SignBridge.exe"
#define HostName       "com.ase.signer"

; Chrome extension ID — must match extension/manifest.json key-derived ID
#define ChromeExtID    "hlpdphlmjodbaodlaoikcjccjoahgomi"
; Firefox extension ID — must match extension/manifest.firefox.json
#define FirefoxExtID   "signbridge@ase.ro"

[Setup]
AppId={{8A2E4F6B-1C3D-4E5F-9A7B-2D8E6F0A1B3C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; No Start Menu shortcut needed — it's a background service
AllowNoIcons=yes
; Output location and filename
OutputDir=..\..\installers\windows
OutputBaseFilename=SignBridge-Setup-{#MyAppVersion}
; Installer icon
SetupIconFile=..\..\logo.ico
; Compression
Compression=lzma2/ultra64
SolidCompression=yes
; Require admin for HKLM registry writes (optional — using HKCU instead)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Misc
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; Minimum Windows version
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Copy the entire PyInstaller one-dir build
Source: "..\..\dist\SignBridge\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\dist\SignBridge\_internal\*"; DestDir: "{app}\_internal"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Registry]
; ── Chrome ──────────────────────────────────────────────────────────────
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\{#HostName}"; \
  ValueType: string; ValueName: ""; ValueData: "{localappdata}\{#MyAppName}\{#HostName}.chrome.json"; \
  Flags: uninsdeletekey

; ── Edge ────────────────────────────────────────────────────────────────
Root: HKCU; Subkey: "Software\Microsoft\Edge\NativeMessagingHosts\{#HostName}"; \
  ValueType: string; ValueName: ""; ValueData: "{localappdata}\{#MyAppName}\{#HostName}.edge.json"; \
  Flags: uninsdeletekey

; ── Brave ───────────────────────────────────────────────────────────────
Root: HKCU; Subkey: "Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\{#HostName}"; \
  ValueType: string; ValueName: ""; ValueData: "{localappdata}\{#MyAppName}\{#HostName}.brave.json"; \
  Flags: uninsdeletekey

; ── Firefox ─────────────────────────────────────────────────────────────
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\{#HostName}"; \
  ValueType: string; ValueName: ""; ValueData: "{localappdata}\{#MyAppName}\{#HostName}.firefox.json"; \
  Flags: uninsdeletekey

[Dirs]
Name: "{localappdata}\{#MyAppName}"

[Code]
// ─── Generate native messaging manifest JSON files ─────────────────────
// These are written post-install because they contain the resolved {app} path.

function BuildChromeManifest(ExePath: String): String;
begin
  Result :=
    '{' + #13#10 +
    '  "name": "{#HostName}",' + #13#10 +
    '  "description": "SignBridge - Generic Web HSM Signing Native Host",' + #13#10 +
    '  "path": "' + ExePath + '",' + #13#10 +
    '  "type": "stdio",' + #13#10 +
    '  "allowed_origins": [' + #13#10 +
    '    "chrome-extension://{#ChromeExtID}/"' + #13#10 +
    '  ]' + #13#10 +
    '}';
end;

function BuildFirefoxManifest(ExePath: String): String;
begin
  Result :=
    '{' + #13#10 +
    '  "name": "{#HostName}",' + #13#10 +
    '  "description": "SignBridge - Generic Web HSM Signing Native Host",' + #13#10 +
    '  "path": "' + ExePath + '",' + #13#10 +
    '  "type": "stdio",' + #13#10 +
    '  "allowed_extensions": [' + #13#10 +
    '    "{#FirefoxExtID}"' + #13#10 +
    '  ]' + #13#10 +
    '}';
end;

procedure WriteManifestFiles();
var
  ManifestDir, ExePath, EscapedExePath: String;
  ChromeManifest, FirefoxManifest: String;
begin
  ManifestDir := ExpandConstant('{localappdata}\{#MyAppName}');
  ExePath := ExpandConstant('{app}\{#MyAppExeName}');

  // JSON requires forward slashes or escaped backslashes
  EscapedExePath := ExePath;
  StringChangeEx(EscapedExePath, '\', '\\', True);

  // Build manifests
  ChromeManifest := BuildChromeManifest(EscapedExePath);
  FirefoxManifest := BuildFirefoxManifest(EscapedExePath);

  // Ensure directory exists
  ForceDirectories(ManifestDir);

  // Write Chrome-family manifests (all share the same format, different files for clarity)
  SaveStringToFile(ManifestDir + '\{#HostName}.chrome.json', ChromeManifest, False);
  SaveStringToFile(ManifestDir + '\{#HostName}.edge.json', ChromeManifest, False);
  SaveStringToFile(ManifestDir + '\{#HostName}.brave.json', ChromeManifest, False);

  // Write Firefox manifest
  SaveStringToFile(ManifestDir + '\{#HostName}.firefox.json', FirefoxManifest, False);

  Log('Native messaging manifests written to ' + ManifestDir);
end;

procedure DeleteManifestFiles();
var
  ManifestDir: String;
begin
  ManifestDir := ExpandConstant('{localappdata}\{#MyAppName}');

  DeleteFile(ManifestDir + '\{#HostName}.chrome.json');
  DeleteFile(ManifestDir + '\{#HostName}.edge.json');
  DeleteFile(ManifestDir + '\{#HostName}.brave.json');
  DeleteFile(ManifestDir + '\{#HostName}.firefox.json');

  RemoveDir(ManifestDir);  // Only removes if empty

  Log('Native messaging manifests cleaned up');
end;

// ─── Hook: after installation, write the manifest files ────────────────
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    WriteManifestFiles();
  end;
end;

// ─── Hook: on uninstall, clean up manifest files ───────────────────────
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DeleteManifestFiles();
  end;
end;
