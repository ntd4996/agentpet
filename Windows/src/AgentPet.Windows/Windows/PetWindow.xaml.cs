using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace AgentPet.Windows.Windows;

public partial class PetWindow : System.Windows.Window
{
    private const double EdgePadding = 4;
    private const double DragThreshold = 4;

    private bool _isClamping;
    private readonly DispatcherTimer _clickTimer;
    private bool _isMouseDown;
    private bool _isDragging;
    private int _pendingClickCount = 1;
    private int _queuedClickCount;
    private System.Windows.Point _dragStartMouse;
    private double _dragStartLeft;
    private double _dragStartTop;

    public PetWindow()
    {
        InitializeComponent();
        _clickTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(260) };
        _clickTimer.Tick += (_, _) => FlushQueuedClick();
        MouseLeftButtonDown += OnMouseLeftButtonDown;
        MouseMove += OnMouseMove;
        MouseLeftButtonUp += OnMouseLeftButtonUp;
        LostMouseCapture += (_, _) => ResetDragState();
        Loaded += (_, _) => EnsurePetVisible();
        LocationChanged += (_, _) => EnsurePetVisible();
        SizeChanged += (_, _) => EnsurePetVisible();
    }

    public event Action<int>? PetClicked;

    public void EnsurePetVisible()
    {
        if (_isClamping || !IsLoaded)
        {
            return;
        }

        _isClamping = true;
        try
        {
            ClampPetToWorkArea();
            UpdateBubblePlacement();
        }
        finally
        {
            _isClamping = false;
        }

        Dispatcher.BeginInvoke(new Action(() =>
        {
            if (!IsLoaded || _isClamping)
            {
                return;
            }

            _isClamping = true;
            try
            {
                ClampPetToWorkArea();
                UpdateBubblePlacement();
            }
            finally
            {
                _isClamping = false;
            }
        }), DispatcherPriority.Render);
    }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs args)
    {
        _isMouseDown = true;
        _isDragging = false;
        _pendingClickCount = Math.Max(1, args.ClickCount);
        _dragStartMouse = PointToScreen(args.GetPosition(this));
        _dragStartLeft = Left;
        _dragStartTop = Top;
        CaptureMouse();
        args.Handled = true;
    }

    private void OnMouseMove(object sender, System.Windows.Input.MouseEventArgs args)
    {
        if (!_isMouseDown || args.LeftButton != MouseButtonState.Pressed)
        {
            return;
        }

        var current = PointToScreen(args.GetPosition(this));
        var dx = current.X - _dragStartMouse.X;
        var dy = current.Y - _dragStartMouse.Y;
        if (!_isDragging && Math.Abs(dx) < DragThreshold && Math.Abs(dy) < DragThreshold)
        {
            return;
        }

        _isDragging = true;
        Left = _dragStartLeft + dx;
        Top = _dragStartTop + dy;
        EnsurePetVisible();
    }

    private void OnMouseLeftButtonUp(object sender, MouseButtonEventArgs args)
    {
        ReleaseMouseCapture();
        var wasDragging = _isDragging;
        ResetDragState();

        if (wasDragging)
        {
            EnsurePetVisible();
            args.Handled = true;
            return;
        }

        _queuedClickCount = Math.Max(_queuedClickCount, Math.Max(_pendingClickCount, args.ClickCount));
        _clickTimer.Stop();
        _clickTimer.Start();
        args.Handled = true;
    }

    private void FlushQueuedClick()
    {
        _clickTimer.Stop();
        var clickCount = Math.Max(1, _queuedClickCount);
        _queuedClickCount = 0;

        PetClicked?.Invoke(clickCount);
        if (clickCount >= 3)
        {
            AnimatePet(1.24, 190);
        }
        else if (clickCount == 2)
        {
            AnimatePet(1.18, 170);
        }
        else
        {
            AnimatePet(1.08, 130);
        }

        EnsurePetVisible();
    }

    private void ResetDragState()
    {
        _isMouseDown = false;
        _isDragging = false;
    }

    private void AnimatePet(double scale, int milliseconds)
    {
        if (PetSprite.RenderTransform is not ScaleTransform transform)
        {
            return;
        }

        var up = new DoubleAnimation(1, scale, TimeSpan.FromMilliseconds(milliseconds / 2.0))
        {
            AutoReverse = true,
            EasingFunction = new BackEase { Amplitude = 0.25, EasingMode = EasingMode.EaseOut }
        };
        transform.BeginAnimation(ScaleTransform.ScaleXProperty, up);
        transform.BeginAnimation(ScaleTransform.ScaleYProperty, up.Clone());
    }

    private void ClampPetToWorkArea()
    {
        var petBounds = PetBoundsInScreen();
        if (petBounds.Width <= 0 || petBounds.Height <= 0)
        {
            return;
        }

        var workArea = SystemParameters.WorkArea;
        var dx = 0.0;
        var dy = 0.0;

        if (petBounds.Left < workArea.Left + EdgePadding)
        {
            dx = workArea.Left + EdgePadding - petBounds.Left;
        }
        else if (petBounds.Right > workArea.Right - EdgePadding)
        {
            dx = workArea.Right - EdgePadding - petBounds.Right;
        }

        if (petBounds.Top < workArea.Top + EdgePadding)
        {
            dy = workArea.Top + EdgePadding - petBounds.Top;
        }
        else if (petBounds.Bottom > workArea.Bottom - EdgePadding)
        {
            dy = workArea.Bottom - EdgePadding - petBounds.Bottom;
        }

        if (Math.Abs(dx) > 0.1)
        {
            Left += dx;
        }

        if (Math.Abs(dy) > 0.1)
        {
            Top += dy;
        }
    }

    private Rect PetBoundsInScreen()
    {
        var width = PetSprite.ActualWidth > 0 ? PetSprite.ActualWidth : PetSprite.Width;
        var height = PetSprite.ActualHeight > 0 ? PetSprite.ActualHeight : PetSprite.Height;
        if (double.IsNaN(width) || double.IsNaN(height))
        {
            return Rect.Empty;
        }

        var topLeft = PetSprite.TransformToAncestor(this).Transform(new System.Windows.Point(0, 0));
        return new Rect(Left + topLeft.X, Top + topLeft.Y, width, height);
    }

    private void UpdateBubblePlacement()
    {
        var petBounds = PetBoundsInScreen();
        if (petBounds.IsEmpty)
        {
            return;
        }

        var workArea = SystemParameters.WorkArea;
        var bubbleHeight = BubblePanel.ActualHeight > 0 ? BubblePanel.ActualHeight : 140;
        var shouldPlaceBelow = petBounds.Top - bubbleHeight - 12 < workArea.Top;

        var bubbleWidth = BubblePanel.ActualWidth > 0 ? BubblePanel.ActualWidth : 340;
        var desiredLeft = petBounds.Left + petBounds.Width / 2 - bubbleWidth / 2;
        var offsetX = 0.0;
        if (desiredLeft < workArea.Left + EdgePadding)
        {
            offsetX = workArea.Left + EdgePadding - desiredLeft;
        }
        else if (desiredLeft + bubbleWidth > workArea.Right - EdgePadding)
        {
            offsetX = workArea.Right - EdgePadding - (desiredLeft + bubbleWidth);
        }

        Grid.SetRow(BubblePanel, shouldPlaceBelow ? 2 : 0);
        BubblePanel.VerticalAlignment = shouldPlaceBelow ? VerticalAlignment.Top : VerticalAlignment.Bottom;
        BubblePanel.Margin = shouldPlaceBelow ? new Thickness(10, 4, 10, 0) : new Thickness(10, 0, 10, 4);
        BubblePanel.RenderTransform = new TranslateTransform(offsetX, 0);
        BubbleArrowUp.Visibility = shouldPlaceBelow ? Visibility.Visible : Visibility.Collapsed;
        BubbleArrowDown.Visibility = shouldPlaceBelow ? Visibility.Collapsed : Visibility.Visible;
    }
}
