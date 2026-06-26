using AgentPet.Core.Models;

namespace AgentPet.Core.State;

public static class MoodResolver
{
    public static PetMood Aggregate(IEnumerable<AgentSession> sessions)
    {
        var snapshot = sessions as AgentSession[] ?? sessions.ToArray();
        if (snapshot.Any(session => session.State == AgentState.Waiting))
        {
            return PetMood.Waiting;
        }

        if (snapshot.Any(session => session.State == AgentState.Working))
        {
            return PetMood.Working;
        }

        if (snapshot.Any(session => session.State == AgentState.Done))
        {
            return PetMood.Done;
        }

        return PetMood.Idle;
    }
}
