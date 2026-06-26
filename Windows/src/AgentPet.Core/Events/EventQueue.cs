using System.Text;
using AgentPet.Core.Models;

namespace AgentPet.Core.Events;

public static class EventQueue
{
    public static string Enqueue(AgentEvent evt, string queueDir) => Enqueue(EventCoding.EncodeLineBytes(evt), queueDir);

    public static string Enqueue(string encodedLine, string queueDir) => Enqueue(Encoding.UTF8.GetBytes(encodedLine), queueDir);

    public static string Enqueue(byte[] encodedLine, string queueDir)
    {
        Directory.CreateDirectory(queueDir);
        var fileName = $"{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}-{Guid.NewGuid():N}.json";
        var path = Path.Combine(queueDir, fileName);
        File.WriteAllBytes(path, encodedLine);
        return path;
    }

    public static IReadOnlyList<AgentEvent> Drain(string queueDir)
    {
        var events = new List<AgentEvent>();
        Drain(queueDir, events.Add);
        return events;
    }

    public static void Drain(string queueDir, Action<AgentEvent> onEvent)
    {
        if (!Directory.Exists(queueDir))
        {
            return;
        }

        foreach (var path in Directory.EnumerateFiles(queueDir).OrderBy(Path.GetFileName, StringComparer.Ordinal))
        {
            try
            {
                var text = File.ReadAllText(path, Encoding.UTF8);
                foreach (var evt in EventCoding.DecodeLines(text))
                {
                    onEvent(evt);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
            finally
            {
                try
                {
                    File.Delete(path);
                }
                catch (IOException)
                {
                }
                catch (UnauthorizedAccessException)
                {
                }
            }
        }
    }
}
