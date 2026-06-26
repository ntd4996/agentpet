namespace AgentPet.Core.Paths;

public static class AgentPetPaths
{
    public const string PipeName = "agentpet-events";

    public static string HomeDir
    {
        get
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (!string.IsNullOrWhiteSpace(home))
            {
                return home;
            }

            home = Environment.GetEnvironmentVariable("USERPROFILE");
            return string.IsNullOrWhiteSpace(home) ? Environment.CurrentDirectory : home;
        }
    }

    public static string LocalAppDataDir
    {
        get
        {
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return string.IsNullOrWhiteSpace(localAppData) ? HomeDir : localAppData;
        }
    }

    public static string BaseDir => Path.Combine(LocalAppDataDir, "AgentPet");

    public static string LegacyBaseDir => Path.Combine(HomeDir, ".agentpet");

    public static string QueueDir => Path.Combine(BaseDir, "queue");

    public static string LegacyQueueDir => Path.Combine(LegacyBaseDir, "queue");

    public static string PetsDir => Path.Combine(BaseDir, "pets");

    public static string LegacyPetsDir => Path.Combine(LegacyBaseDir, "pets");

    public static string SocketPath => Path.Combine(BaseDir, "agentpet.sock");

    public static IEnumerable<string> QueueDirs => ExistingDistinct(QueueDir, LegacyQueueDir);

    public static IEnumerable<string> PetsDirs => ExistingDistinct(PetsDir, LegacyPetsDir);

    public static string HomePath(params string[] components)
    {
        return components.Aggregate(HomeDir, Path.Combine);
    }

    private static IEnumerable<string> ExistingDistinct(params string[] paths)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in paths)
        {
            if (seen.Add(path))
            {
                yield return path;
            }
        }
    }
}
