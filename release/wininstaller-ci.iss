; CI-only installer script -- a trimmed-down copy of wininstaller.iss
; covering only what .gitlab-ci.yml's package:windows-installer job
; actually builds: the 64-bit Standalone .exe and VST3 plugin. No
; VST2, no AAX, no 32-bit -- see .gitlab-ci.yml's top-of-file comment
; for why. wininstaller.iss itself is untouched and remains the real
; installer script for a full release once those are available.

[Setup]
AppName=SonoBus
AppVersion={#SBVERSION}
MinVersion=6.1
WizardStyle=modern
DefaultDirName={autopf}\SonoBus
DefaultGroupName=SonoBus
UninstallDisplayIcon={app}\SonoBus.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
OutputBaseFilename=SonoBus-{#SBVERSION}-Installer
LicenseFile=gpl-3.0.txt
SetupLogging=yes
SignTool=signtool $f
SignedUninstaller=yes
DisableReadyPage=true
DisableWelcomePage=yes
DisableDirPage=no
ShowComponentSizes=no

[Types]
Name: "full"; Description: "Full installation"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Components]
Name: "app"; Description: "Standalone 64-bit application (.exe)"; Types: full custom
Name: "vst3_64"; Description: "64-bit VST3 Plugin (.vst3)"; Types: full custom

[Files]
Source: "SonoBus\SonoBus.exe"; DestDir: "{app}"; Components: app; Flags: ignoreversion signonce
Source: "SonoBus\Plugins\VST3\SonoBus.vst3"; DestDir: "{commoncf}\VST3"; Components: vst3_64; Flags: ignoreversion signonce recursesubdirs createallsubdirs
Source: "SonoBus\Plugins\VST3\SonoBusInstrument.vst3"; DestDir: "{commoncf}\VST3"; Components: vst3_64; Flags: ignoreversion signonce recursesubdirs createallsubdirs
Source: "SonoBus\README.txt"; DestDir: "{app}"; DestName: "README.txt"; Flags: isreadme

; because we switched to folder-based VST3s
[InstallDelete]
Type: files; Name: "{commoncf}\VST3\SonoBus.vst3"

[Icons]
Name: "{group}\SonoBus"; Filename: "{app}\SonoBus.exe"
Name: "{group}\README"; Filename: "{app}\README.txt"
Name: "{group}\Uninstall SonoBus"; Filename: "{app}\unins000.exe"

[Registry]
Root: HKCR; Subkey: "sonobus"; ValueType: "string"; ValueData: "URL:sonobus Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "sonobus"; ValueType: "string"; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "sonobus\DefaultIcon"; ValueType: "string"; ValueData: "{app}\SonoBus.exe,0"
Root: HKCR; Subkey: "sonobus\shell\open\command"; ValueType: "string"; ValueData: """{app}\SonoBus.exe"" ""%1"""

[Code]
var
  OkToCopyLog : Boolean;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssDone then
    OkToCopyLog := True;
end;

procedure DeinitializeSetup();
begin
  if OkToCopyLog then
    FileCopy (ExpandConstant ('{log}'), ExpandConstant ('{app}\InstallationLogFile.log'), FALSE);
  RestartReplace (ExpandConstant ('{log}'), '');
end;

procedure ComponentsListCheckChanges;
begin
  WizardForm.NextButton.Enabled := (WizardSelectedComponents(False) <> '');
end;

procedure ComponentsListClickCheck(Sender: TObject);
begin
  ComponentsListCheckChanges;
end;

procedure InitializeWizard;
begin
  WizardForm.ComponentsDiskSpaceLabel.Visible := False;
  WizardForm.ComponentsList.OnClickCheck := @ComponentsListClickCheck;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectComponents then
  begin
    ComponentsListCheckChanges;
  end;
end;

[UninstallDelete]
Type: files; Name: "{app}\InstallationLogFile.log"
