#ifndef AppVersion
#define AppVersion "0.1.0"
#endif
#ifndef SourceDir
#define SourceDir "..\publish\AgentPet.Windows-win-x64"
#endif
#ifndef OutputDir
#define OutputDir "..\publish\installer"
#endif

[Setup]
AppId={{A7F0AB8C-498F-4B37-9F05-0A032A8F7838}
AppName=AgentPet
AppVersion={#AppVersion}
AppPublisher=AgentPet
AppPublisherURL=https://github.com/
AppSupportURL=https://github.com/
AppUpdatesURL=https://github.com/
DefaultDirName={localappdata}\Programs\AgentPet
DefaultGroupName=AgentPet
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=AgentPet-Setup-x64
SetupIconFile={#SourceDir}\Assets\app.ico
UninstallDisplayIcon={app}\AgentPet.Windows.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Tạo biểu tượng ngoài Desktop"; GroupDescription: "Tùy chọn bổ sung:"; Flags: unchecked
Name: "startup"; Description: "Chạy AgentPet cùng Windows"; GroupDescription: "Tùy chọn bổ sung:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AgentPet"; Filename: "{app}\AgentPet.Windows.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\app.ico"
Name: "{autodesktop}\AgentPet"; Filename: "{app}\AgentPet.Windows.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\app.ico"; Tasks: desktopicon
Name: "{userstartup}\AgentPet"; Filename: "{app}\AgentPet.Windows.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\app.ico"; Tasks: startup

[Run]
Filename: "{app}\AgentPet.Windows.exe"; Description: "Mở AgentPet"; Flags: nowait postinstall skipifsilent
