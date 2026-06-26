using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using AgentPet.Core.Paths;

namespace AgentPet.Windows.Services;

public sealed class PetCatalogService
{
    public IReadOnlyList<PetCatalogItem> Load()
    {
        var items = new List<PetCatalogItem>();
        var seenPackIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var petsDir in PetSearchDirs())
        {
            if (!Directory.Exists(petsDir))
            {
                continue;
            }

            foreach (var manifestPath in Directory.EnumerateFiles(petsDir, "pet.json", SearchOption.AllDirectories).OrderBy(path => path, StringComparer.OrdinalIgnoreCase))
            {
                var packId = Path.GetFileName(Path.GetDirectoryName(manifestPath));
                if (string.IsNullOrWhiteSpace(packId) || seenPackIds.Contains(packId))
                {
                    continue;
                }

                if (TryLoadItem(manifestPath) is { } item)
                {
                    items.Add(item);
                    seenPackIds.Add(packId);
                }
            }
        }

        if (items.Count == 0)
        {
            items.Add(DefaultItem());
        }

        return items;
    }

    private static IEnumerable<string> PetSearchDirs()
    {
        foreach (var petsDir in AgentPetPaths.PetsDirs)
        {
            yield return petsDir;
        }

        yield return Path.Combine(AppContext.BaseDirectory, "Assets", "Pets");
    }

    private static PetCatalogItem? TryLoadItem(string manifestPath)
    {
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(manifestPath));
            var root = document.RootElement;
            var spritesheetPath = StringProperty(root, "spritesheetPath") ?? StringProperty(root, "spritesheet");
            if (string.IsNullOrWhiteSpace(spritesheetPath))
            {
                return null;
            }

            var directory = Path.GetDirectoryName(manifestPath);
            if (directory is null)
            {
                return null;
            }

            var spritesheet = Path.Combine(directory, spritesheetPath);
            if (!File.Exists(spritesheet))
            {
                return null;
            }

            var name = StringProperty(root, "displayName")
                ?? StringProperty(root, "name")
                ?? Humanize(Path.GetFileName(directory));
            var description = StringProperty(root, "description") ?? "Local AgentPet sprite pack";
            return new PetCatalogItem(directory, name, description, spritesheet, LoadThumbnail(spritesheet));
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
        catch (NotSupportedException)
        {
            return null;
        }
    }

    private static PetCatalogItem DefaultItem()
    {
        var image = new BitmapImage(new Uri("pack://application:,,,/Assets/default-pet.png", UriKind.Absolute));
        image.Freeze();
        return new PetCatalogItem("default", "Claude", "Bundled Windows fallback pet", null, LoadThumbnail(image));
    }

    private static ImageSource LoadThumbnail(string path)
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.UriSource = new Uri(path, UriKind.Absolute);
        image.EndInit();
        image.Freeze();
        return LoadThumbnail(image);
    }

    private static ImageSource LoadThumbnail(BitmapSource source, byte alphaThreshold = 16)
    {
        var formatted = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var width = formatted.PixelWidth;
        var height = formatted.PixelHeight;
        if (width <= 0 || height <= 0)
        {
            return source;
        }

        if (width == 1536 && height == 1872)
        {
            var firstFrame = new CroppedBitmap(formatted, new Int32Rect(0, 0, 192, 208));
            firstFrame.Freeze();
            return firstFrame;
        }

        var stride = width * 4;
        var pixels = new byte[stride * height];
        formatted.CopyPixels(pixels, stride, 0);

        var rowHas = new bool[height];
        for (var y = 0; y < height; y++)
        {
            var rowStart = y * stride;
            for (var x = 0; x < width; x++)
            {
                if (pixels[rowStart + x * 4 + 3] > alphaThreshold)
                {
                    rowHas[y] = true;
                    break;
                }
            }
        }

        var row = Segments(rowHas).FirstOrDefault();
        if (row == default)
        {
            return source;
        }

        var colHas = new bool[width];
        for (var y = row.Lower; y < row.Upper; y++)
        {
            var rowStart = y * stride;
            for (var x = 0; x < width; x++)
            {
                if (pixels[rowStart + x * 4 + 3] > alphaThreshold)
                {
                    colHas[x] = true;
                }
            }
        }

        var col = Segments(colHas).FirstOrDefault();
        if (col == default)
        {
            return source;
        }

        var cropped = new CroppedBitmap(formatted, new Int32Rect(col.Lower, row.Lower, col.Upper - col.Lower, row.Upper - row.Lower));
        cropped.Freeze();
        return cropped;
    }

    private static IEnumerable<(int Lower, int Upper)> Segments(bool[] occupancy)
    {
        int? start = null;
        for (var i = 0; i < occupancy.Length; i++)
        {
            if (occupancy[i] && start is null)
            {
                start = i;
            }
            else if (!occupancy[i] && start is { } lower)
            {
                yield return (lower, i);
                start = null;
            }
        }

        if (start is { } finalLower)
        {
            yield return (finalLower, occupancy.Length);
        }
    }

    private static string? StringProperty(JsonElement root, string name)
    {
        return root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
    }

    private static string Humanize(string name)
    {
        return string.Join(' ', name.Replace('-', ' ').Replace('_', ' ').Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(TitleCase));
    }

    private static string TitleCase(string value) => value.Length == 0 ? value : char.ToUpperInvariant(value[0]) + value[1..];
}

public sealed record PetCatalogItem(string Id, string DisplayName, string Description, string? SpritesheetPath, ImageSource Thumbnail);
