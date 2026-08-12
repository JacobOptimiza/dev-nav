#define AppName "DevNav"
#define AppPublisher "Jacob Optimiza"
#define AppURL "https://github.com/JacobOptimiza/dev-nav"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef Architecture
  #define Architecture "x64"
#endif

[Setup]
AppId={{B7B1A6EE-8F4D-4E59-9B4D-0A1B00000001}
AppName={#AppName}
AppVersion={#MyAppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}/releases
DefaultDirName={localappdata}\Programs\DevNav
DefaultGroupName=DevNav
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=release-assets
OutputBaseFilename=DevNavSetup-{#Architecture}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
Uninstallable=yes
UninstallDisplayIcon={app}\dev.exe
VersionInfoCompany={#AppPublisher}
VersionInfoDescription=Native project navigator for PowerShell 7
VersionInfoProductName=DevNav
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCopyright=Copyright (C) 2026 Jacob Optimiza

[Files]
Source: "release-assets\dev.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "powershell\DevNav.psm1"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer\ProfileIntegration.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "pwsh.exe"; Parameters: "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\ProfileIntegration.ps1"" -Install -ModulePath ""{app}\DevNav.psm1"""; Flags: runhidden waituntilterminated; StatusMsg: "Integrating DevNav with PowerShell 7..."

[UninstallRun]
Filename: "pwsh.exe"; Parameters: "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\ProfileIntegration.ps1"" -Uninstall -ModulePath ""{app}\DevNav.psm1"""; Flags: runhidden waituntilterminated

[UninstallDelete]
Type: files; Name: "{app}\ProfileIntegration.ps1"
Type: files; Name: "{app}\DevNav.psm1"
Type: files; Name: "{app}\dev.exe"
