using AgentPet.Core.Events;
using AgentPet.Core.Models;
using AgentPet.Core.Paths;

namespace AgentPet.Cli;

public static class HookCommand
{
    public static Task<int> RunAsync(string[] args)
    {
        var options = Parse(args);
        if (options.HelpRequested)
        {
            WriteUsage();
            return Task.FromResult(0);
        }

        if (!string.IsNullOrWhiteSpace(options.Error))
        {
            Console.Error.WriteLine(options.Error);
            Console.Error.WriteLine();
            WriteUsage();
            return Task.FromResult(1);
        }

        var evt = new AgentEvent(
            options.SessionId!,
            options.AgentKind,
            options.EventName!,
            options.Project,
            options.Message,
            options.TranscriptPath,
            options.Timestamp);

        var delivered = EventSender.Send(evt, options.PipeName, options.QueueDir);
        if (!delivered)
        {
            Console.Error.WriteLine($"queued: {evt.EventName} for {evt.SessionId}");
        }

        return Task.FromResult(0);
    }

    private static HookOptions Parse(string[] args)
    {
        var options = new HookOptions
        {
            PipeName = AgentPetPaths.PipeName,
            QueueDir = AgentPetPaths.QueueDir,
            Timestamp = DateTimeOffset.UtcNow
        };

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (arg is "-h" or "--help" or "/?")
            {
                options.HelpRequested = true;
                return options;
            }

            if (!arg.StartsWith("--", StringComparison.Ordinal))
            {
                options.Error = $"Unexpected argument '{arg}'.";
                return options;
            }

            var name = arg[2..].ToLowerInvariant();
            if (name == "agent" || name == "event" || name == "session" || name == "project" || name == "message" || name == "transcript" || name == "timestamp" || name == "pipe-name" || name == "queue-dir")
            {
                if (i + 1 >= args.Length)
                {
                    options.Error = $"Missing value for '{arg}'.";
                    return options;
                }

                var value = args[++i];
                switch (name)
                {
                    case "agent":
                        options.AgentKind = AgentKindExtensions.Parse(value);
                        break;
                    case "event":
                        options.EventName = value;
                        break;
                    case "session":
                        options.SessionId = value;
                        break;
                    case "project":
                        options.Project = value;
                        break;
                    case "message":
                        options.Message = value;
                        break;
                    case "transcript":
                        options.TranscriptPath = value;
                        break;
                    case "timestamp":
                        if (!long.TryParse(value, out var seconds))
                        {
                            options.Error = $"Invalid timestamp '{value}'.";
                            return options;
                        }
                        options.Timestamp = DateTimeOffset.FromUnixTimeSeconds(seconds);
                        break;
                    case "pipe-name":
                        options.PipeName = value;
                        break;
                    case "queue-dir":
                        options.QueueDir = value;
                        break;
                }
                continue;
            }

            options.Error = $"Unknown option '{arg}'.";
            return options;
        }

        if (options.AgentKind == AgentKind.Unknown)
        {
            options.Error = "Missing or unknown --agent value.";
        }
        else if (string.IsNullOrWhiteSpace(options.EventName))
        {
            options.Error = "Missing --event value.";
        }
        else if (string.IsNullOrWhiteSpace(options.SessionId))
        {
            options.Error = "Missing --session value.";
        }

        return options;
    }

    private static void WriteUsage()
    {
        Console.WriteLine("agentpet hook --agent <name> --event <name> --session <id> [--project <path>] [--message <text>] [--transcript <path>] [--timestamp <unix-seconds>]");
    }

    private sealed record HookOptions
    {
        public AgentKind AgentKind { get; set; } = AgentKind.Unknown;
        public string? EventName { get; set; }
        public string? SessionId { get; set; }
        public string? Project { get; set; }
        public string? Message { get; set; }
        public string? TranscriptPath { get; set; }
        public DateTimeOffset Timestamp { get; set; }
        public string PipeName { get; set; } = AgentPetPaths.PipeName;
        public string QueueDir { get; set; } = AgentPetPaths.QueueDir;
        public string? Error { get; set; }
        public bool HelpRequested { get; set; }
    }
}
