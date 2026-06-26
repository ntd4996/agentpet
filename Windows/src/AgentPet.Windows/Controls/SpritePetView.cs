using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using AgentPet.Core.Paths;
using Image = System.Windows.Controls.Image;

namespace AgentPet.Windows.Controls;

public sealed class SpritePetView : Image
{
    public static readonly DependencyProperty MoodProperty = DependencyProperty.Register(
        nameof(Mood),
        typeof(string),
        typeof(SpritePetView),
        new PropertyMetadata("idle", OnMoodChanged));

    public static readonly DependencyProperty SpritesheetPathProperty = DependencyProperty.Register(
        nameof(SpritesheetPath),
        typeof(string),
        typeof(SpritePetView),
        new PropertyMetadata(null, OnSpritesheetPathChanged));

    private readonly DispatcherTimer _timer;
    private List<List<BitmapSource>> _clips = new();
    private int _frameIndex;

    public SpritePetView()
    {
        Stretch = Stretch.Uniform;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        _timer = new DispatcherTimer { Interval = FrameInterval("idle") };
        _timer.Tick += (_, _) => AdvanceFrame();
        Loaded += (_, _) => Start();
        Unloaded += (_, _) => _timer.Stop();
    }

    public string Mood
    {
        get => (string)GetValue(MoodProperty);
        set => SetValue(MoodProperty, value);
    }

    public string? SpritesheetPath
    {
        get => (string?)GetValue(SpritesheetPathProperty);
        set => SetValue(SpritesheetPathProperty, value);
    }

    private static void OnMoodChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var view = (SpritePetView)d;
        view._timer.Interval = FrameInterval((string)e.NewValue);
        view.ShowFrame(animate: true);
    }

    private static void OnSpritesheetPathChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var view = (SpritePetView)d;
        view._clips = LoadClips((string?)e.NewValue);
        view._frameIndex = 0;
        view.ShowFrame(animate: false);
    }

    private void Start()
    {
        if (_clips.Count == 0)
        {
            _clips = LoadClips(SpritesheetPath);
        }

        ShowFrame();
        _timer.Interval = FrameInterval(Mood);
        _timer.Start();
    }

    private void AdvanceFrame()
    {
        var frames = FramesForMood();
        if (frames.Count == 0)
        {
            return;
        }

        for (var offset = 1; offset <= frames.Count; offset++)
        {
            var candidateIndex = (_frameIndex + offset) % frames.Count;
            if (IsUsableFrame(frames[candidateIndex]))
            {
                _frameIndex = candidateIndex;
                SetFrame(frames[_frameIndex], animate: false);
                return;
            }
        }
    }

    private void ShowFrame(bool animate = false)
    {
        var frames = FramesForMood();
        if (frames.Count == 0)
        {
            return;
        }

        _frameIndex %= frames.Count;
        if (!IsUsableFrame(frames[_frameIndex]))
        {
            for (var offset = 0; offset < frames.Count; offset++)
            {
                var candidateIndex = (_frameIndex + offset) % frames.Count;
                if (IsUsableFrame(frames[candidateIndex]))
                {
                    _frameIndex = candidateIndex;
                    break;
                }
            }
        }

        SetFrame(frames[_frameIndex], animate);
    }

    private void SetFrame(BitmapSource frame, bool animate)
    {
        if (!IsUsableFrame(frame) && Source is not null)
        {
            return;
        }

        Source = frame;
        if (!animate || !IsLoaded)
        {
            Opacity = 1;
            return;
        }

        BeginAnimation(OpacityProperty, new DoubleAnimation(0.94, 1.0, TimeSpan.FromMilliseconds(70))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        });
    }

    private static bool IsUsableFrame(BitmapSource frame)
    {
        var formatted = new FormatConvertedBitmap(frame, PixelFormats.Bgra32, null, 0);
        var stride = formatted.PixelWidth * 4;
        var pixels = new byte[stride * formatted.PixelHeight];
        formatted.CopyPixels(pixels, stride, 0);
        for (var y = 0; y < formatted.PixelHeight; y++)
        {
            var rowStart = y * stride;
            for (var x = 0; x < formatted.PixelWidth; x++)
            {
                if (pixels[rowStart + x * 4 + 3] > 12)
                {
                    return true;
                }
            }
        }

        return false;
    }

    private List<BitmapSource> FramesForMood()
    {
        if (_clips.Count == 0)
        {
            return [];
        }

        var row = Mood switch
        {
            "idle" => 0,
            "working" => 1,
            "waiting" => 2,
            "done" => 3,
            "celebrate" => 4,
            _ => 0
        };
        return _clips[Math.Min(row, _clips.Count - 1)];
    }

    private static TimeSpan FrameInterval(string mood)
    {
        var fps = mood switch
        {
            "working" or "celebrate" => 8.0,
            "waiting" => 4.0,
            _ => 3.0
        };
        return TimeSpan.FromSeconds(1.0 / fps);
    }

    private static List<List<BitmapSource>> LoadClips(string? selectedSpritesheetPath)
    {
        if (!string.IsNullOrWhiteSpace(selectedSpritesheetPath))
        {
            var selectedClips = TryLoadClips(selectedSpritesheetPath);
            if (selectedClips.Count > 0)
            {
                return selectedClips;
            }
        }

        foreach (var path in CandidateSpritesheets())
        {
            var clips = TryLoadClips(path);
            if (clips.Count > 0)
            {
                return clips;
            }
        }

        return Slice(new BitmapImage(new Uri("pack://application:,,,/Assets/default-pet.png", UriKind.Absolute)));
    }

    private static List<List<BitmapSource>> TryLoadClips(string path)
    {
        try
        {
            var source = new BitmapImage(new Uri(path, UriKind.Absolute));
            return Slice(source);
        }
        catch (IOException)
        {
        }
        catch (NotSupportedException)
        {
        }
        catch (UriFormatException)
        {
        }

        return [];
    }

    private static IEnumerable<string> CandidateSpritesheets()
    {
        foreach (var petsDir in AgentPetPaths.PetsDirs)
        {
            if (!Directory.Exists(petsDir))
            {
                continue;
            }

            foreach (var manifestPath in Directory.EnumerateFiles(petsDir, "pet.json", SearchOption.AllDirectories).OrderBy(path => path, StringComparer.OrdinalIgnoreCase))
            {
                var manifest = JsonSerializer.Deserialize<PetManifest>(File.ReadAllText(manifestPath));
                if (manifest?.SpritesheetPath is null)
                {
                    continue;
                }

                var directory = Path.GetDirectoryName(manifestPath);
                if (directory is null)
                {
                    continue;
                }

                var spritesheet = Path.Combine(directory, manifest.SpritesheetPath);
                if (File.Exists(spritesheet))
                {
                    yield return spritesheet;
                }
            }
        }
    }

    private static List<List<BitmapSource>> Slice(BitmapSource source, byte alphaThreshold = 16)
    {
        var formatted = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var width = formatted.PixelWidth;
        var height = formatted.PixelHeight;
        if (width <= 0 || height <= 0)
        {
            return [];
        }

        var gridClips = TrySliceFixedGrid(formatted);
        if (gridClips.Count > 0)
        {
            return gridClips;
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

        var rowBands = Segments(rowHas).ToArray();
        var clips = new List<List<BitmapSource>>();
        foreach (var row in rowBands)
        {
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

            var clip = new List<BitmapSource>();
            foreach (var col in Segments(colHas))
            {
                var rect = new Int32Rect(col.Lower, row.Lower, col.Upper - col.Lower, row.Upper - row.Lower);
                var cropped = new CroppedBitmap(formatted, rect);
                cropped.Freeze();
                clip.Add(cropped);
            }

            if (clip.Count > 0)
            {
                clips.Add(clip);
            }
        }

        return clips;
    }

    private static List<List<BitmapSource>> TrySliceFixedGrid(BitmapSource source)
    {
        const int cols = 8;
        const int rows = 9;
        const int cellWidth = 192;
        const int cellHeight = 208;

        if (source.PixelWidth != cols * cellWidth || source.PixelHeight != rows * cellHeight)
        {
            return [];
        }

        var clips = new List<List<BitmapSource>>(rows);
        for (var row = 0; row < rows; row++)
        {
            var clipsInRow = new List<BitmapSource>(cols);
            for (var col = 0; col < cols; col++)
            {
                var rect = new Int32Rect(col * cellWidth, row * cellHeight, cellWidth, cellHeight);
                var cropped = new CroppedBitmap(source, rect);
                cropped.Freeze();
                clipsInRow.Add(cropped);
            }

            clips.Add(clipsInRow);
        }

        return clips;
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

    private sealed record PetManifest(string? SpritesheetPath);
}
