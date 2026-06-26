using System.IO;
using System.Text.Json;
using AgentPet.Core.Paths;
using AgentPet.Windows.Models;

namespace AgentPet.Windows.Services;

public sealed class ReminderSettingsService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    public string SettingsPath => Path.Combine(AgentPetPaths.BaseDir, "settings.json");

    public ReminderSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath))
            {
                return ReminderSettings.Defaults();
            }

            var settings = JsonSerializer.Deserialize<ReminderSettings>(File.ReadAllText(SettingsPath), JsonOptions) ?? ReminderSettings.Defaults();
            settings.Normalize();
            return settings;
        }
        catch (IOException)
        {
            return ReminderSettings.Defaults();
        }
        catch (UnauthorizedAccessException)
        {
            return ReminderSettings.Defaults();
        }
        catch (JsonException)
        {
            return ReminderSettings.Defaults();
        }
    }

    public void Save(ReminderSettings settings)
    {
        settings.Normalize();
        Directory.CreateDirectory(AgentPetPaths.BaseDir);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings, JsonOptions));
    }
}
