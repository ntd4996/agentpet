using AgentPet.Core.Paths;

namespace AgentPet.Core.Tests;

public sealed class AgentPetPathsTests
{
    [Fact]
    public void PathsUseWindowsLocalAppDataAndLegacyHomeDirectory()
    {
        Assert.Equal(Path.Combine(AgentPetPaths.LocalAppDataDir, "AgentPet"), AgentPetPaths.BaseDir);
        Assert.Equal(Path.Combine(AgentPetPaths.HomeDir, ".agentpet"), AgentPetPaths.LegacyBaseDir);
        Assert.Equal(Path.Combine(AgentPetPaths.BaseDir, "queue"), AgentPetPaths.QueueDir);
        Assert.Equal(Path.Combine(AgentPetPaths.LegacyBaseDir, "queue"), AgentPetPaths.LegacyQueueDir);
        Assert.Equal(Path.Combine(AgentPetPaths.BaseDir, "pets"), AgentPetPaths.PetsDir);
        Assert.Equal(Path.Combine(AgentPetPaths.LegacyBaseDir, "pets"), AgentPetPaths.LegacyPetsDir);
        Assert.Equal(Path.Combine(AgentPetPaths.HomeDir, "a", "b"), AgentPetPaths.HomePath("a", "b"));
    }

    [Fact]
    public void PipeNameIsStable()
    {
        Assert.Equal("agentpet-events", AgentPetPaths.PipeName);
    }
}
