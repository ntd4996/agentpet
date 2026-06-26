using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using AgentPet.Core.Models;

namespace AgentPet.Core.Events;

public static class EventCoding
{
    public static readonly JsonSerializerOptions Options = CreateOptions();

    public static string EncodeLine(AgentEvent evt) => JsonSerializer.Serialize(evt, Options) + "\n";

    public static byte[] EncodeLineBytes(AgentEvent evt) => Encoding.UTF8.GetBytes(EncodeLine(evt));

    public static AgentEvent? DecodeLine(string line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return null;
        }

        try
        {
            return JsonSerializer.Deserialize<AgentEvent>(line, Options);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static AgentEvent? DecodeBytes(ReadOnlySpan<byte> bytes)
    {
        try
        {
            return JsonSerializer.Deserialize<AgentEvent>(bytes, Options);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static IEnumerable<AgentEvent> DecodeLines(string text)
    {
        foreach (var line in text.Split('\n'))
        {
            var trimmed = line.TrimEnd('\r');
            var evt = DecodeLine(trimmed);
            if (evt is not null)
            {
                yield return evt;
            }
        }
    }

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = null,
            WriteIndented = false,
            DefaultIgnoreCondition = JsonIgnoreCondition.Never
        };
        options.Converters.Add(new AgentKindJsonConverter());
        options.Converters.Add(new UnixSecondsDateTimeOffsetJsonConverter());
        return options;
    }
}

public sealed class AgentKindJsonConverter : JsonConverter<AgentKind>
{
    public override AgentKind Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        return reader.TokenType == JsonTokenType.String
            ? AgentKindExtensions.Parse(reader.GetString())
            : AgentKind.Unknown;
    }

    public override void Write(Utf8JsonWriter writer, AgentKind value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.WireName());
    }
}

public sealed class UnixSecondsDateTimeOffsetJsonConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        return reader.TokenType switch
        {
            JsonTokenType.Number when reader.TryGetInt64(out var seconds) => DateTimeOffset.FromUnixTimeSeconds(seconds),
            JsonTokenType.Number => DateTimeOffset.FromUnixTimeMilliseconds((long)(reader.GetDouble() * 1000)),
            JsonTokenType.String when DateTimeOffset.TryParse(reader.GetString(), out var parsed) => parsed,
            _ => throw new JsonException("Expected Unix timestamp seconds or ISO date string.")
        };
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
    {
        writer.WriteNumberValue(value.ToUnixTimeSeconds());
    }
}
