param(
    [string]$Version = "0.1.0",
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [switch]$SkipTests,
    [switch]$SkipInstaller,
    [switch]$Sign,
    [string]$CertificateThumbprint = "",
    [string]$TimestampUrl = "http://timestamp.digicert.com",
    [string]$SignToolPath = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsDir = Resolve-Path (Join-Path $scriptDir "..")
$repoRoot = Resolve-Path (Join-Path $windowsDir "..")
$dotnet = "C:\Program Files\dotnet\dotnet.exe"

function Find-SignTool {
    if (-not [string]::IsNullOrWhiteSpace($SignToolPath)) {
        if (Test-Path $SignToolPath) { return $SignToolPath }
        throw "SignToolPath does not exist: $SignToolPath"
    }

    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (Test-Path $kitsRoot) {
        $candidate = Get-ChildItem $kitsRoot -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like "*\x64\signtool.exe" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }

    throw "signtool.exe not found. Install Windows SDK or pass -SignToolPath."
}

function Invoke-CodeSign([string]$Path) {
    if (-not $Sign) { return }
    if (-not (Test-Path $Path)) {
        throw "Cannot sign missing file: $Path"
    }

    $signtool = Find-SignTool
    if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        & $signtool sign /fd SHA256 /td SHA256 /tr $TimestampUrl /a $Path
    }
    else {
        & $signtool sign /fd SHA256 /td SHA256 /tr $TimestampUrl /sha1 $CertificateThumbprint $Path
    }
}

if (-not (Test-Path $dotnet)) {
    throw "dotnet SDK not found at $dotnet. Install .NET SDK 8 on the build machine."
}

$appProject = Join-Path $repoRoot "Windows\src\AgentPet.Windows\AgentPet.Windows.csproj"
$cliProject = Join-Path $repoRoot "Windows\src\AgentPet.Cli\AgentPet.Cli.csproj"
$solution = Join-Path $repoRoot "Windows\AgentPet.sln"
$appPublishDir = Join-Path $repoRoot "Windows\publish\AgentPet.Windows-win-x64"
$cliPublishDir = Join-Path $repoRoot "Windows\publish\AgentPet.Cli-win-x64"
$installerDir = Join-Path $repoRoot "Windows\publish\installer"
$installerScript = Join-Path $repoRoot "Windows\installer\AgentPet.iss"

$running = Get-Process AgentPet.Windows -ErrorAction SilentlyContinue
if ($running) {
    $ids = ($running | ForEach-Object { $_.Id }) -join ", "
    Write-Warning "AgentPet.Windows is running (PID: $ids). Stop it if publish reports locked files."
}

if (-not $SkipTests) {
    & $dotnet test $solution -c $Configuration
}

Remove-Item $appPublishDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $cliPublishDir -Recurse -Force -ErrorAction SilentlyContinue
if (-not $SkipInstaller) {
    Remove-Item $installerDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force $appPublishDir | Out-Null
New-Item -ItemType Directory -Force $cliPublishDir | Out-Null
New-Item -ItemType Directory -Force $installerDir | Out-Null

& $dotnet publish $appProject -c $Configuration -r $Runtime --self-contained true -p:Version=$Version -p:AssemblyVersion="$Version.0" -p:FileVersion="$Version.0" -o $appPublishDir
& $dotnet publish $cliProject -c $Configuration -r $Runtime --self-contained true -p:PublishSingleFile=true -p:Version=$Version -p:AssemblyVersion="$Version.0" -p:FileVersion="$Version.0" -o $cliPublishDir

$cliExe = Join-Path $cliPublishDir "agentpet.exe"
if (-not (Test-Path $cliExe)) {
    throw "CLI helper missing after publish: $cliExe"
}
Copy-Item $cliExe (Join-Path $appPublishDir "agentpet.exe") -Force

$required = @(
    (Join-Path $appPublishDir "AgentPet.Windows.exe"),
    (Join-Path $appPublishDir "agentpet.exe"),
    (Join-Path $appPublishDir "Assets\app.ico")
)
foreach ($path in $required) {
    if (-not (Test-Path $path)) {
        throw "Required release file is missing: $path"
    }
}

Invoke-CodeSign (Join-Path $appPublishDir "AgentPet.Windows.exe")
Invoke-CodeSign (Join-Path $appPublishDir "agentpet.exe")

if ($SkipInstaller) {
    Write-Host "Self-contained publish: $appPublishDir"
    exit 0
}

$iscc = $null
$command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($command) {
    $iscc = $command.Source
}
if (-not $iscc) {
    $candidate = Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"
    if (Test-Path $candidate) {
        $iscc = $candidate
    }
}
if (-not $iscc) {
    throw "Inno Setup compiler (ISCC.exe) not found. Install it on the build machine with: winget install JRSoftware.InnoSetup"
}

& $iscc "/DAppVersion=$Version" "/DSourceDir=$appPublishDir" "/DOutputDir=$installerDir" $installerScript

$installer = Join-Path $installerDir "AgentPet-Setup-x64.exe"
if (-not (Test-Path $installer)) {
    throw "Installer missing after build: $installer"
}

Invoke-CodeSign $installer

$hash = Get-FileHash $installer -Algorithm SHA256
Write-Host "Installer: $installer"
Write-Host "SHA256: $($hash.Hash)"
if (-not $Sign) {
    Write-Host "Note: installer is unsigned. Re-run with -Sign and a certificate to code-sign app, CLI, and installer."
}
