using AgentPet.Core.Paths;

namespace AgentPet.Cli;

public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        if (args.Length == 0 || IsHelp(args[0]))
        {
            WriteUsage();
            return 0;
        }

        var command = args[0].ToLowerInvariant();
        return command switch
        {
            "hook" => await HookCommand.RunAsync(args[1..]).ConfigureAwait(false),
            _ => Fail($"Unknown command '{args[0]}'.")
        };
    }

    private static bool IsHelp(string arg) => arg is "-h" or "--help" or "/?" or "help";

    private static int Fail(string message)
    {
        Console.Error.WriteLine(message);
        Console.Error.WriteLine();
        WriteUsage();
        return 1;
    }

    private static void WriteUsage()
    {
        Console.WriteLine("agentpet hook --agent <name> --event <name> --session <id> [--project <path>] [--message <text>] [--transcript <path>] [--timestamp <unix-seconds>]");
        Console.WriteLine();
        Console.WriteLine($"Defaults: pipe={AgentPetPaths.PipeName}, queue={AgentPetPaths.QueueDir}");
    }
}
