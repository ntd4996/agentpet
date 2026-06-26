using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using AgentPet.Core.Paths;

namespace AgentPet.Windows.Services;

public sealed class UpdateService
{
    private const string LatestReleaseUrl = "https://api.github.com/repos/DungDT293/agentpet/releases/latest";
    private const string InstallerAssetName = "AgentPet-Setup-x64.exe";

    private static readonly HttpClient Http = new()
    {
        Timeout = TimeSpan.FromSeconds(30)
    };

    static UpdateService()
    {
        Http.DefaultRequestHeaders.UserAgent.ParseAdd("AgentPet-Windows-Updater/0.1");
        Http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
    }

    public async Task<UpdateCheckResult> CheckAndDownloadLatestAsync(CancellationToken cancellationToken = default)
    {
        using var response = await Http.GetAsync(LatestReleaseUrl, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            return UpdateCheckResult.Failed($"Không thể kiểm tra cập nhật trên GitHub ({(int)response.StatusCode}).");
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        var release = await JsonSerializer.DeserializeAsync<GitHubRelease>(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
        if (release is null || string.IsNullOrWhiteSpace(release.TagName))
        {
            return UpdateCheckResult.Failed("Không đọc được thông tin bản phát hành mới nhất.");
        }

        if (!TryParseVersion(release.TagName, out var latestVersion))
        {
            return UpdateCheckResult.Failed($"Không đọc được phiên bản mới nhất: {release.TagName}.");
        }

        var currentVersion = CurrentVersion();
        if (latestVersion <= currentVersion)
        {
            return UpdateCheckResult.UpToDate($"Bạn đang dùng phiên bản mới nhất ({currentVersion}).");
        }

        var asset = release.Assets.FirstOrDefault(item => string.Equals(item.Name, InstallerAssetName, StringComparison.OrdinalIgnoreCase));
        if (asset is null || string.IsNullOrWhiteSpace(asset.DownloadUrl))
        {
            return UpdateCheckResult.Failed($"Bản {release.TagName} chưa có file {InstallerAssetName}.");
        }

        var updateDir = Path.Combine(AgentPetPaths.BaseDir, "updates");
        Directory.CreateDirectory(updateDir);
        var installerPath = Path.Combine(updateDir, InstallerAssetName);
        await DownloadFileAsync(asset.DownloadUrl, installerPath, cancellationToken).ConfigureAwait(false);
        return UpdateCheckResult.UpdateDownloaded(release.TagName, installerPath);
    }

    public void LaunchInstaller(string installerPath)
    {
        if (!File.Exists(installerPath))
        {
            throw new FileNotFoundException("Installer update không tồn tại.", installerPath);
        }

        var appPath = Environment.ProcessPath ?? Assembly.GetEntryAssembly()?.Location ?? string.Empty;
        var scriptPath = Path.Combine(Path.GetDirectoryName(installerPath) ?? AgentPetPaths.BaseDir, "run-agentpet-update.ps1");
        File.WriteAllText(scriptPath, UpdateScript);

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            CreateNoWindow = true
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-WindowStyle");
        startInfo.ArgumentList.Add("Hidden");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(scriptPath);
        startInfo.ArgumentList.Add("-InstallerPath");
        startInfo.ArgumentList.Add(installerPath);
        startInfo.ArgumentList.Add("-ParentProcessId");
        startInfo.ArgumentList.Add(Environment.ProcessId.ToString());
        startInfo.ArgumentList.Add("-AppPath");
        startInfo.ArgumentList.Add(appPath);
        Process.Start(startInfo);
    }

    private static async Task DownloadFileAsync(string url, string destinationPath, CancellationToken cancellationToken)
    {
        using var response = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        await using var remote = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        await using var local = File.Create(destinationPath);
        await remote.CopyToAsync(local, cancellationToken).ConfigureAwait(false);
    }

    private static Version CurrentVersion()
    {
        var version = Assembly.GetEntryAssembly()?.GetName().Version;
        return version is null ? new Version(0, 0, 0) : new Version(version.Major, version.Minor, Math.Max(0, version.Build));
    }

    private static bool TryParseVersion(string tag, out Version version)
    {
        var normalized = tag.Trim().TrimStart('v', 'V');
        return Version.TryParse(normalized, out version!);
    }

    private const string UpdateScript = """
param(
    [Parameter(Mandatory=$true)][string]$InstallerPath,
    [Parameter(Mandatory=$true)][int]$ParentProcessId,
    [string]$AppPath = ""
)

$ErrorActionPreference = 'SilentlyContinue'
try {
    Wait-Process -Id $ParentProcessId -Timeout 20
} catch {
}

$process = Start-Process -FilePath $InstallerPath -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait -PassThru
if ($process.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($AppPath) -and (Test-Path $AppPath)) {
    Start-Process -FilePath $AppPath | Out-Null
}
""";

    private sealed class GitHubRelease
    {
        [JsonPropertyName("tag_name")]
        public string TagName { get; set; } = string.Empty;

        [JsonPropertyName("assets")]
        public List<GitHubAsset> Assets { get; set; } = [];
    }

    private sealed class GitHubAsset
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("browser_download_url")]
        public string DownloadUrl { get; set; } = string.Empty;
    }
}

public sealed record UpdateCheckResult(bool HasUpdate, bool IsUpToDate, string Message, string? InstallerPath)
{
    public static UpdateCheckResult UpToDate(string message) => new(false, true, message, null);
    public static UpdateCheckResult Failed(string message) => new(false, false, message, null);
    public static UpdateCheckResult UpdateDownloaded(string version, string installerPath) =>
        new(true, false, $"Đã tải bản {version}. AgentPet sẽ đóng để chạy trình cập nhật.", installerPath);
}
