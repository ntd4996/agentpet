namespace AgentPet.Core.Models;

public enum PetMood
{
    Idle,
    Working,
    Waiting,
    Done,
    Celebrate
}

public static class PetMoodExtensions
{
    public static string DisplayName(this PetMood mood) => mood switch
    {
        PetMood.Working => "working",
        PetMood.Waiting => "waiting",
        PetMood.Done => "done",
        PetMood.Celebrate => "celebrate",
        _ => "idle"
    };
}
