param(
  [Parameter(Mandatory = $true)][ValidateSet('region', 'window', 'fullscreen')][string]$Mode,
  [Parameter(Mandatory = $true)][string]$OutputPath,
  [Parameter(Mandatory = $true)][string]$ResultPath,
  [int]$Delay = 0,
  [string]$Language = 'zh',
  [string]$RestoreTitle = 'DeepSeek Harness',
  [int]$RestorePid = 0,
  [string]$AutoRect = '',
  [string]$AutoWindow = '',
  [int]$AutoCancelMs = 0
)

$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace DshShot
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    internal static class Native
    {
        public const int SM_XVIRTUALSCREEN = 76;
        public const int SM_YVIRTUALSCREEN = 77;
        public const int SM_CXVIRTUALSCREEN = 78;
        public const int SM_CYVIRTUALSCREEN = 79;
        public const uint PW_RENDERFULLCONTENT = 2;
        public const int SW_RESTORE = 9;
        public const int DWMWA_CLOAKED = 14;

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();

        [DllImport("user32.dll")]
        public static extern int GetSystemMetrics(int index);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int command);

        [DllImport("user32.dll")]
        public static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        [DllImport("user32.dll")]
        public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

        [DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out int value, int size);
    }

    public class WindowInfo
    {
        public IntPtr Handle;
        public Rectangle Bounds;
        public string Title;
        public string ClassName;
        public uint ProcessId;
    }

    public class CaptureResult
    {
        public bool Ok;
        public bool Cancelled;
        public string Path;
        public int Width;
        public int Height;
        public string Error;
    }

    internal static class NativeText
    {
        public static string GetWindowTitle(IntPtr hWnd)
        {
            int length = Native.GetWindowTextLength(hWnd);
            if (length <= 0)
            {
                return string.Empty;
            }
            StringBuilder builder = new StringBuilder(length + 1);
            Native.GetWindowText(hWnd, builder, builder.Capacity);
            return builder.ToString();
        }

        public static string GetClassName(IntPtr hWnd)
        {
            StringBuilder builder = new StringBuilder(256);
            Native.GetClassName(hWnd, builder, builder.Capacity);
            return builder.ToString();
        }

        public static bool IsCloaked(IntPtr hWnd)
        {
            int cloaked = 0;
            int hr = Native.DwmGetWindowAttribute(hWnd, Native.DWMWA_CLOAKED, out cloaked, sizeof(int));
            return hr == 0 && cloaked != 0;
        }

        public static string Clip(string text, int max)
        {
            if (text == null)
            {
                return string.Empty;
            }
            if (text.Length <= max)
            {
                return text;
            }
            return text.Substring(0, max - 1) + "\u2026";
        }
    }

    internal static class Visuals
    {
        public static readonly Color Accent = Color.FromArgb(0, 120, 212);
        public static readonly Color Panel = Color.FromArgb(30, 31, 35);
        public static readonly Color PanelBorder = Color.FromArgb(70, 72, 78);
        public static readonly Color Text = Color.FromArgb(245, 246, 248);
        public static readonly Color TextMuted = Color.FromArgb(176, 180, 186);

        public static Font UiFont(float size, bool bold)
        {
            try
            {
                return new Font("Microsoft YaHei UI", size, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Point);
            }
            catch
            {
                return new Font(FontFamily.GenericSansSerif, size, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Point);
            }
        }

        public static GraphicsPath RoundedRect(Rectangle bounds, int radius)
        {
            int diameter = radius * 2;
            GraphicsPath path = new GraphicsPath();
            if (radius <= 0)
            {
                path.AddRectangle(bounds);
                path.CloseFigure();
                return path;
            }
            Rectangle arc = new Rectangle(bounds.X, bounds.Y, diameter, diameter);
            path.AddArc(arc, 180, 90);
            arc.X = bounds.Right - diameter;
            path.AddArc(arc, 270, 90);
            arc.Y = bounds.Bottom - diameter;
            path.AddArc(arc, 0, 90);
            arc.X = bounds.X;
            path.AddArc(arc, 90, 90);
            path.CloseFigure();
            return path;
        }

        public static void DrawPill(Graphics graphics, Rectangle bounds, string title, string subtitle)
        {
            using (GraphicsPath path = RoundedRect(bounds, 12))
            using (SolidBrush fill = new SolidBrush(Color.FromArgb(235, Panel)))
            using (Pen stroke = new Pen(PanelBorder, 1f))
            {
                graphics.FillPath(fill, path);
                graphics.DrawPath(stroke, path);
            }

            using (Font titleFont = UiFont(10.5f, true))
            using (Font subtitleFont = UiFont(8.5f, false))
            using (SolidBrush titleBrush = new SolidBrush(Text))
            using (SolidBrush subtitleBrush = new SolidBrush(TextMuted))
            using (StringFormat format = new StringFormat())
            {
                format.Alignment = StringAlignment.Center;
                format.LineAlignment = StringAlignment.Center;
                if (subtitle.Length == 0)
                {
                    graphics.DrawString(title, titleFont, titleBrush, new RectangleF(bounds.X + 8, bounds.Y, bounds.Width - 16, bounds.Height), format);
                }
                else
                {
                    graphics.DrawString(title, titleFont, titleBrush, new RectangleF(bounds.X + 8, bounds.Y + 8, bounds.Width - 16, bounds.Height / 2f), format);
                    graphics.DrawString(subtitle, subtitleFont, subtitleBrush, new RectangleF(bounds.X + 8, bounds.Y + bounds.Height / 2f, bounds.Width - 16, bounds.Height / 2f - 6), format);
                }
            }
        }

        public static void DrawHint(Graphics graphics, Rectangle monitorClientBounds, string title, string subtitle)
        {
            int width = 360;
            int height = subtitle.Length == 0 ? 42 : 62;
            Rectangle bounds = new Rectangle(
                monitorClientBounds.X + Math.Max(0, (monitorClientBounds.Width - width) / 2),
                monitorClientBounds.Y + 18,
                width,
                height);
            DrawPill(graphics, bounds, title, subtitle);
        }

        public static Rectangle MonitorClientRect(Rectangle virtualBounds, Point cursor)
        {
            Rectangle monitor = Screen.FromPoint(cursor).Bounds;
            return new Rectangle(
                monitor.X - virtualBounds.X,
                monitor.Y - virtualBounds.Y,
                monitor.Width,
                monitor.Height);
        }
    }

    public class CountdownForm : Form
    {
        private readonly int seconds;
        private readonly string language;
        private readonly System.Windows.Forms.Timer countdownTimer;
        private int remaining;

        public bool Cancelled = false;
        public int AutoCancelMs = 0;
        private System.Windows.Forms.Timer autoCancelTimer;

        public CountdownForm(int seconds, string language)
        {
            this.seconds = seconds;
            this.language = language;
            this.remaining = seconds;

            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.ShowInTaskbar = false;
            this.TopMost = true;
            this.KeyPreview = true;
            this.BackColor = Visuals.Panel;
            this.Opacity = 0.96;
            this.Width = 320;
            this.Height = 82;

            Rectangle work = Screen.FromPoint(Cursor.Position).WorkingArea;
            this.Location = new Point(work.Left + (work.Width - this.Width) / 2, work.Bottom - this.Height - 110);

            this.countdownTimer = new System.Windows.Forms.Timer();
            this.countdownTimer.Interval = 1000;
            this.countdownTimer.Tick += this.OnTick;

            this.SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            this.countdownTimer.Start();
            if (this.AutoCancelMs > 0)
            {
                this.autoCancelTimer = new System.Windows.Forms.Timer();
                this.autoCancelTimer.Interval = this.AutoCancelMs;
                this.autoCancelTimer.Tick += delegate(object sender, EventArgs args)
                {
                    this.autoCancelTimer.Stop();
                    this.Cancelled = true;
                    this.Close();
                };
                this.autoCancelTimer.Start();
            }
            this.Invalidate();
        }

        private void OnTick(object sender, EventArgs e)
        {
            this.remaining--;
            if (this.remaining <= 0)
            {
                this.countdownTimer.Stop();
                this.Close();
                return;
            }
            this.Invalidate();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                this.Cancelled = true;
                this.countdownTimer.Stop();
                this.Close();
            }
            base.OnKeyDown(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics graphics = e.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle rect = new Rectangle(0, 0, this.Width - 1, this.Height - 1);
            using (GraphicsPath path = Visuals.RoundedRect(rect, 14))
            using (Pen stroke = new Pen(Visuals.PanelBorder, 1f))
            {
                graphics.DrawPath(stroke, path);
            }

            string title = this.remaining.ToString() + (this.language == "en" ? " seconds" : " 秒后截图");
            string subtitle = this.language == "en" ? "Press Esc to cancel" : "按 Esc 取消";
            Visuals.DrawPill(graphics, new Rectangle(1, 1, this.Width - 2, this.Height - 2), title, subtitle);
        }
    }

    public class RegionForm : Form
    {
        private readonly Bitmap frozen;
        private readonly Rectangle virtualBounds;
        private readonly string language;
        private Point origin;
        private Point current;
        private bool dragging;
        private System.Windows.Forms.Timer autoTimer;

        public Rectangle SelectedRect;
        public bool Cancelled = false;
        public Rectangle AutoRectScreen = Rectangle.Empty;
        public int AutoCancelMs = 0;

        private string TitleText
        {
            get { return this.language == "en" ? "Drag to select an area" : "拖动鼠标选择截图区域"; }
        }

        private string SubtitleText
        {
            get { return this.language == "en" ? "Esc or right-click to cancel" : "按 Esc 或右键取消"; }
        }

        public RegionForm(Bitmap frozen, Rectangle virtualBounds, string language)
        {
            this.frozen = frozen;
            this.virtualBounds = virtualBounds;
            this.language = language;
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.Bounds = virtualBounds;
            this.ShowInTaskbar = false;
            this.TopMost = true;
            this.KeyPreview = true;
            this.Cursor = Cursors.Cross;
            this.BackColor = Color.Black;
            this.DoubleBuffered = true;
            this.SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (this.AutoCancelMs > 0)
            {
                this.autoTimer = new System.Windows.Forms.Timer();
                this.autoTimer.Interval = this.AutoCancelMs;
                this.autoTimer.Tick += delegate(object sender, EventArgs args)
                {
                    this.autoTimer.Stop();
                    this.Cancelled = true;
                    this.Close();
                };
                this.autoTimer.Start();
            }
            if (this.AutoRectScreen != Rectangle.Empty)
            {
                System.Windows.Forms.Timer selectTimer = new System.Windows.Forms.Timer();
                selectTimer.Interval = 400;
                selectTimer.Tick += delegate(object sender, EventArgs args)
                {
                    selectTimer.Stop();
                    this.SelectedRect = new Rectangle(
                        this.AutoRectScreen.X - this.virtualBounds.X,
                        this.AutoRectScreen.Y - this.virtualBounds.Y,
                        this.AutoRectScreen.Width,
                        this.AutoRectScreen.Height);
                    this.Close();
                };
                selectTimer.Start();
            }
        }

        private Rectangle Selection()
        {
            int x = Math.Min(this.origin.X, this.current.X);
            int y = Math.Min(this.origin.Y, this.current.Y);
            int width = Math.Abs(this.origin.X - this.current.X);
            int height = Math.Abs(this.origin.Y - this.current.Y);
            return new Rectangle(x, y, width, height);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Right)
            {
                this.Cancelled = true;
                this.Close();
                return;
            }
            if (e.Button == MouseButtons.Left)
            {
                this.origin = e.Location;
                this.current = e.Location;
                this.dragging = true;
                this.Invalidate();
            }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!this.dragging)
            {
                return;
            }
            this.current = e.Location;
            this.Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (!this.dragging || e.Button != MouseButtons.Left)
            {
                return;
            }
            this.dragging = false;
            Rectangle selection = this.Selection();
            if (selection.Width >= 4 && selection.Height >= 4)
            {
                this.SelectedRect = selection;
                this.Close();
            }
            else
            {
                this.origin = Point.Empty;
                this.current = Point.Empty;
                this.Invalidate();
            }
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                this.Cancelled = true;
                this.Close();
            }
            base.OnKeyDown(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics graphics = e.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;

            graphics.DrawImageUnscaled(this.frozen, 0, 0);
            using (SolidBrush dim = new SolidBrush(Color.FromArgb(120, 0, 0, 0)))
            {
                graphics.FillRectangle(dim, this.ClientRectangle);
            }

            Rectangle selection = this.Selection();
            if (selection.Width > 0 && selection.Height > 0)
            {
                graphics.DrawImage(this.frozen, selection, selection, GraphicsUnit.Pixel);
                using (Pen border = new Pen(Visuals.Accent, 2f))
                {
                    graphics.DrawRectangle(border, selection.X, selection.Y, Math.Max(0, selection.Width - 1), Math.Max(0, selection.Height - 1));
                }

                using (Font sizeFont = Visuals.UiFont(8f, true))
                using (SolidBrush sizeBrush = new SolidBrush(Visuals.Text))
                using (SolidBrush sizeFill = new SolidBrush(Color.FromArgb(210, Visuals.Panel)))
                using (StringFormat format = new StringFormat())
                {
                    format.Alignment = StringAlignment.Center;
                    format.LineAlignment = StringAlignment.Center;
                    string size = selection.Width.ToString() + " \u00d7 " + selection.Height.ToString();
                    SizeF measure = graphics.MeasureString(size, sizeFont);
                    Rectangle sizeRect = new Rectangle(
                        selection.X + 6,
                        selection.Y + 6,
                        Math.Max(40, (int)measure.Width + 14),
                        Math.Max(22, (int)measure.Height + 6));
                    graphics.FillRectangle(sizeFill, sizeRect);
                    graphics.DrawString(size, sizeFont, sizeBrush, sizeRect, format);
                }
            }

            // While the user is dragging, the selection and its size readout are
            // the useful feedback; the hint pill would sit on top of the frozen
            // image and hide part of the selection.
            if (selection.Width <= 0 || selection.Height <= 0)
            {
                Rectangle monitor = Visuals.MonitorClientRect(this.virtualBounds, Cursor.Position);
                Visuals.DrawHint(graphics, monitor, this.TitleText, this.SubtitleText);
            }
        }
    }

    public class WindowForm : Form
    {
        private readonly Bitmap frozen;
        private readonly Rectangle virtualBounds;
        private readonly string language;
        private readonly List<WindowInfo> windows;
        private WindowInfo hovered;
        private System.Windows.Forms.Timer autoTimer;

        public WindowInfo Selected;
        public bool Cancelled = false;
        public int AutoCancelMs = 0;
        public string AutoWindow = string.Empty;

        private string TitleText
        {
            get { return this.language == "en" ? "Click a window to capture" : "点击要截取的窗口"; }
        }

        private string SubtitleText
        {
            get { return this.language == "en" ? "Esc or right-click to cancel" : "按 Esc 或右键取消"; }
        }

        public WindowForm(Bitmap frozen, Rectangle virtualBounds, string language)
        {
            this.frozen = frozen;
            this.virtualBounds = virtualBounds;
            this.language = language;
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.Bounds = virtualBounds;
            this.ShowInTaskbar = false;
            this.TopMost = true;
            this.KeyPreview = true;
            this.Cursor = Cursors.Cross;
            this.BackColor = Color.Black;
            this.DoubleBuffered = true;
            this.windows = WindowList.Enumerate();
            this.SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (this.AutoCancelMs > 0)
            {
                this.autoTimer = new System.Windows.Forms.Timer();
                this.autoTimer.Interval = this.AutoCancelMs;
                this.autoTimer.Tick += delegate(object sender, EventArgs args)
                {
                    this.autoTimer.Stop();
                    this.Cancelled = true;
                    this.Close();
                };
                this.autoTimer.Start();
            }
            if (this.AutoWindow.Length > 0)
            {
                System.Windows.Forms.Timer selectTimer = new System.Windows.Forms.Timer();
                selectTimer.Interval = 400;
                selectTimer.Tick += delegate(object sender, EventArgs args)
                {
                    selectTimer.Stop();
                    for (int i = 0; i < this.windows.Count; i++)
                    {
                        WindowInfo candidate = this.windows[i];
                        if (candidate.Title.IndexOf(this.AutoWindow, StringComparison.OrdinalIgnoreCase) >= 0
                            || candidate.ClassName.IndexOf(this.AutoWindow, StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            this.Selected = candidate;
                            this.Close();
                            return;
                        }
                    }
                    this.Cancelled = true;
                    this.Close();
                };
                selectTimer.Start();
            }
            this.RefreshHovered();
        }

        private WindowInfo HitTest(Point clientPoint)
        {
            Point screenPoint = new Point(this.virtualBounds.X + clientPoint.X, this.virtualBounds.Y + clientPoint.Y);
            for (int i = 0; i < this.windows.Count; i++)
            {
                WindowInfo candidate = this.windows[i];
                if (candidate.Bounds.Contains(screenPoint))
                {
                    return candidate;
                }
            }
            return null;
        }

        private void RefreshHovered()
        {
            WindowInfo next = this.HitTest(this.PointToClient(Cursor.Position));
            if (!object.ReferenceEquals(next, this.hovered))
            {
                this.hovered = next;
                this.Invalidate();
            }
        }

        private Rectangle ClientRectOf(WindowInfo window)
        {
            Rectangle rect = window.Bounds;
            rect.Offset(-this.virtualBounds.X, -this.virtualBounds.Y);
            return rect;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            this.RefreshHovered();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Right)
            {
                this.Cancelled = true;
                this.Close();
                return;
            }
            if (e.Button == MouseButtons.Left)
            {
                WindowInfo hit = this.HitTest(e.Location);
                if (hit != null)
                {
                    this.Selected = hit;
                    this.Close();
                }
            }
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                this.Cancelled = true;
                this.Close();
            }
            base.OnKeyDown(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics graphics = e.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;

            graphics.DrawImageUnscaled(this.frozen, 0, 0);
            using (SolidBrush dim = new SolidBrush(Color.FromArgb(126, 0, 0, 0)))
            {
                graphics.FillRectangle(dim, this.ClientRectangle);
            }

            WindowInfo active = this.hovered;
            if (active != null)
            {
                Rectangle target = this.ClientRectOf(active);
                Rectangle clipped = Rectangle.Intersect(target, this.ClientRectangle);
                if (clipped.Width > 0 && clipped.Height > 0)
                {
                    Rectangle source = clipped;
                    graphics.DrawImage(this.frozen, clipped, source, GraphicsUnit.Pixel);
                    using (Pen border = new Pen(Visuals.Accent, 2f))
                    {
                        graphics.DrawRectangle(border, clipped.X, clipped.Y, Math.Max(0, clipped.Width - 1), Math.Max(0, clipped.Height - 1));
                    }

                    string title = active.Title.Length > 0 ? active.Title : active.ClassName;
                    using (Font titleFont = Visuals.UiFont(9f, true))
                    using (SolidBrush text = new SolidBrush(Visuals.Text))
                    using (SolidBrush fill = new SolidBrush(Color.FromArgb(215, Visuals.Panel)))
                    using (StringFormat format = new StringFormat())
                    {
                        format.Trimming = StringTrimming.EllipsisCharacter;
                        format.FormatFlags = StringFormatFlags.NoWrap;
                        string clippedTitle = NativeText.Clip(title, 72);
                        SizeF measure = graphics.MeasureString(clippedTitle, titleFont);
                        Rectangle labelRect = new Rectangle(
                            clipped.X + 6,
                            Math.Max(clipped.Y + 6, clipped.Y + 6),
                            Math.Min(clipped.Width - 12, (int)measure.Width + 16),
                            Math.Max(24, (int)measure.Height + 8));
                        graphics.FillRectangle(fill, labelRect);
                        graphics.DrawString(clippedTitle, titleFont, text, labelRect, format);
                    }
                }
            }

            Rectangle monitor = Visuals.MonitorClientRect(this.virtualBounds, Cursor.Position);
            Visuals.DrawHint(graphics, monitor, this.TitleText, this.SubtitleText);
        }
    }

    internal static class WindowList
    {
        public static List<WindowInfo> Enumerate()
        {
            List<WindowInfo> windows = new List<WindowInfo>();
            uint ownPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
            Native.EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
            {
                if (!Native.IsWindowVisible(hWnd) || Native.IsIconic(hWnd))
                {
                    return true;
                }
                RECT raw;
                if (!Native.GetWindowRect(hWnd, out raw))
                {
                    return true;
                }
                int width = raw.Right - raw.Left;
                int height = raw.Bottom - raw.Top;
                if (width < 24 || height < 24)
                {
                    return true;
                }
                uint pid;
                Native.GetWindowThreadProcessId(hWnd, out pid);
                if (pid == ownPid)
                {
                    return true;
                }
                if (NativeText.IsCloaked(hWnd))
                {
                    return true;
                }
                string className = NativeText.GetClassName(hWnd);
                if (WindowList.IsIgnoredClass(className))
                {
                    return true;
                }
                WindowInfo info = new WindowInfo();
                info.Handle = hWnd;
                info.Bounds = new Rectangle(raw.Left, raw.Top, width, height);
                info.Title = NativeText.GetWindowTitle(hWnd);
                info.ClassName = className;
                info.ProcessId = pid;
                windows.Add(info);
                return true;
            }, IntPtr.Zero);
            return windows;
        }

        private static bool IsIgnoredClass(string className)
        {
            string[] ignored = new string[]
            {
                "Progman",
                "WorkerW",
                "Shell_TrayWnd",
                "Shell_SecondaryTrayWnd",
                "Windows.UI.Core.CoreWindow",
                "ApplicationManager_DesktopShellWindow",
                "MultitaskingViewFrame",
                "ForegroundStaging",
                "XamlExplorerHostIslandWindow",
                "TopLevelWindowForOverflowXamlIsland"
            };
            for (int i = 0; i < ignored.Length; i++)
            {
                if (string.Equals(className, ignored[i], StringComparison.Ordinal))
                {
                    return true;
                }
            }
            return false;
        }
    }

    public static class Capture
    {
        public static CaptureResult Run(
            string mode,
            int delay,
            string outputPath,
            string language,
            string restoreTitle,
            uint restorePid,
            string autoRect,
            string autoWindow,
            int autoCancelMs)
        {
            CaptureResult result = new CaptureResult();
            IntPtr previousForeground = Native.GetForegroundWindow();
            try
            {
                EnableDpiAwareness();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                Rectangle virtualBounds = GetVirtualBounds();
                if (virtualBounds.Width < 2 || virtualBounds.Height < 2)
                {
                    throw new InvalidOperationException("No usable screen bounds were reported.");
                }

                if (delay > 0)
                {
                    CountdownForm countdown = new CountdownForm(delay, language);
                    countdown.AutoCancelMs = autoCancelMs;
                    countdown.ShowDialog();
                    if (countdown.Cancelled)
                    {
                        result.Cancelled = true;
                        RestoreForeground(previousForeground, restoreTitle, restorePid);
                        return result;
                    }
                    Thread.Sleep(180);
                }

                Bitmap frozen = null;
                Bitmap output = null;
                try
                {
                    if (mode == "fullscreen")
                    {
                        output = CaptureScreen(virtualBounds);
                    }
                    else
                    {
                        frozen = CaptureScreen(virtualBounds);
                        if (mode == "region")
                        {
                            RegionForm region = new RegionForm(frozen, virtualBounds, language);
                            region.AutoRectScreen = ParseRect(autoRect);
                            region.AutoCancelMs = autoCancelMs;
                            region.ShowDialog();
                            Rectangle selectedRegion = region.SelectedRect;
                            if (region.Cancelled || selectedRegion.Width < 2 || selectedRegion.Height < 2)
                            {
                                result.Cancelled = true;
                            }
                            else
                            {
                                output = Crop(frozen, selectedRegion);
                            }
                        }
                        else if (mode == "window")
                        {
                            WindowForm picker = new WindowForm(frozen, virtualBounds, language);
                            picker.AutoWindow = autoWindow == null ? string.Empty : autoWindow;
                            picker.AutoCancelMs = autoCancelMs;
                            picker.ShowDialog();
                            if (picker.Cancelled || picker.Selected == null)
                            {
                                result.Cancelled = true;
                            }
                            else
                            {
                                output = CaptureWindow(picker.Selected, frozen, virtualBounds);
                            }
                        }
                        else
                        {
                            throw new ArgumentException("Unknown capture mode: " + mode);
                        }
                    }

                    if (result.Cancelled)
                    {
                        RestoreForeground(previousForeground, restoreTitle, restorePid);
                        return result;
                    }
                    if (output == null)
                    {
                        throw new InvalidOperationException("The capture produced no image.");
                    }

                    string directory = Path.GetDirectoryName(outputPath);
                    if (directory != null && directory.Length > 0)
                    {
                        Directory.CreateDirectory(directory);
                    }
                    output.Save(outputPath, ImageFormat.Png);
                    result.Ok = true;
                    result.Path = outputPath;
                    result.Width = output.Width;
                    result.Height = output.Height;
                }
                finally
                {
                    if (output != null)
                    {
                        output.Dispose();
                    }
                    if (frozen != null)
                    {
                        frozen.Dispose();
                    }
                }
            }
            catch (Exception error)
            {
                result.Ok = false;
                result.Cancelled = false;
                result.Error = error.ToString();
            }
            finally
            {
                RestoreForeground(previousForeground, restoreTitle, restorePid);
            }
            return result;
        }

        private static void EnableDpiAwareness()
        {
            try
            {
                if (!Native.SetProcessDpiAwarenessContext(new IntPtr(-4)))
                {
                    Native.SetProcessDPIAware();
                }
            }
            catch
            {
                try
                {
                    Native.SetProcessDPIAware();
                }
                catch
                {
                }
            }
        }

        private static Rectangle GetVirtualBounds()
        {
            int x = Native.GetSystemMetrics(Native.SM_XVIRTUALSCREEN);
            int y = Native.GetSystemMetrics(Native.SM_YVIRTUALSCREEN);
            int width = Native.GetSystemMetrics(Native.SM_CXVIRTUALSCREEN);
            int height = Native.GetSystemMetrics(Native.SM_CYVIRTUALSCREEN);
            return new Rectangle(x, y, width, height);
        }

        private static Rectangle ParseRect(string raw)
        {
            if (raw == null || raw.Length == 0)
            {
                return Rectangle.Empty;
            }
            string[] parts = raw.Split(',');
            if (parts.Length != 4)
            {
                return Rectangle.Empty;
            }
            int x;
            int y;
            int width;
            int height;
            if (!int.TryParse(parts[0], out x) || !int.TryParse(parts[1], out y)
                || !int.TryParse(parts[2], out width) || !int.TryParse(parts[3], out height))
            {
                return Rectangle.Empty;
            }
            return new Rectangle(x, y, width, height);
        }

        private static Bitmap CaptureScreen(Rectangle bounds)
        {
            Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                CopyPixelOperation operation = CopyPixelOperation.SourceCopy;
                graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size, operation);
            }
            return bitmap;
        }

        private static Bitmap Crop(Bitmap source, Rectangle rect)
        {
            Rectangle safe = Rectangle.Intersect(rect, new Rectangle(0, 0, source.Width, source.Height));
            if (safe.Width < 1 || safe.Height < 1)
            {
                throw new InvalidOperationException("The selected area is outside the capturable screen.");
            }
            return source.Clone(safe, PixelFormat.Format32bppArgb);
        }

        private static Bitmap CaptureWindow(WindowInfo window, Bitmap frozen, Rectangle virtualBounds)
        {
            Rectangle bounds = window.Bounds;
            Bitmap bitmap = null;
            bool printed = false;
            try
            {
                bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
                using (Graphics graphics = Graphics.FromImage(bitmap))
                {
                    IntPtr hdc = graphics.GetHdc();
                    try
                    {
                        printed = Native.PrintWindow(window.Handle, hdc, Native.PW_RENDERFULLCONTENT);
                    }
                    finally
                    {
                        graphics.ReleaseHdc(hdc);
                    }
                }
                if (printed && !IsMostlyBlank(bitmap))
                {
                    return bitmap;
                }
            }
            catch
            {
                printed = false;
            }

            if (bitmap != null)
            {
                bitmap.Dispose();
                bitmap = null;
            }

            Rectangle source = window.Bounds;
            source.Offset(-virtualBounds.X, -virtualBounds.Y);
            return Crop(frozen, source);
        }

        private static bool IsMostlyBlank(Bitmap bitmap)
        {
            int stepX = Math.Max(1, bitmap.Width / 24);
            int stepY = Math.Max(1, bitmap.Height / 24);
            int samples = 0;
            int lit = 0;
            for (int y = stepY / 2; y < bitmap.Height; y += stepY)
            {
                for (int x = stepX / 2; x < bitmap.Width; x += stepX)
                {
                    Color color = bitmap.GetPixel(x, y);
                    samples++;
                    if (color.R + color.G + color.B > 24)
                    {
                        lit++;
                    }
                }
            }
            return samples > 0 && lit * 20 < samples;
        }

        private static void RestoreForeground(IntPtr previous, string title, uint pid)
        {
            IntPtr target = previous;
            if (target == IntPtr.Zero || !Native.IsWindow(target))
            {
                target = FindRestoreWindow(title, pid);
            }
            if (target == IntPtr.Zero || !Native.IsWindow(target))
            {
                target = FindRestoreWindow(title, pid);
            }
            if (target == IntPtr.Zero)
            {
                return;
            }
            try
            {
                if (Native.IsIconic(target))
                {
                    Native.ShowWindow(target, Native.SW_RESTORE);
                }
                Native.SetForegroundWindow(target);
                Native.BringWindowToTop(target);
            }
            catch
            {
            }
        }

        private static IntPtr FindRestoreWindow(string title, uint pid)
        {
            IntPtr best = IntPtr.Zero;
            int bestArea = 0;
            uint ownPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
            Native.EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
            {
                if (!Native.IsWindowVisible(hWnd) || Native.IsIconic(hWnd))
                {
                    return true;
                }
                uint windowPid;
                Native.GetWindowThreadProcessId(hWnd, out windowPid);
                if (windowPid == ownPid)
                {
                    return true;
                }
                bool pidMatches = pid != 0 && windowPid == pid;
                string windowTitle = NativeText.GetWindowTitle(hWnd);
                bool titleMatches = title != null && title.Length > 0
                    && windowTitle.IndexOf(title, StringComparison.OrdinalIgnoreCase) >= 0;
                if (!pidMatches && !titleMatches)
                {
                    return true;
                }
                RECT raw;
                if (!Native.GetWindowRect(hWnd, out raw))
                {
                    return true;
                }
                int area = (raw.Right - raw.Left) * (raw.Bottom - raw.Top);
                if (area > bestArea)
                {
                    best = hWnd;
                    bestArea = area;
                }
                return true;
            }, IntPtr.Zero);
            return best;
        }
    }
}
'@

$result = @{
  ok        = $false
  cancelled = $false
  path      = ''
  width     = 0
  height    = 0
  error     = ''
}

try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  Add-Type -TypeDefinition $source -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing', 'System.Core') -ErrorAction Stop

  $capture = [DshShot.Capture]::Run(
    $Mode,
    $Delay,
    $OutputPath,
    $Language,
    $RestoreTitle,
    [uint32]$RestorePid,
    $AutoRect,
    $AutoWindow,
    $AutoCancelMs
  )

  $result.ok = [bool]$capture.Ok
  $result.cancelled = [bool]$capture.Cancelled
  $result.path = [string]$capture.Path
  $result.width = [int]$capture.Width
  $result.height = [int]$capture.Height
  $result.error = [string]$capture.Error
}
catch {
  $result.error = $_.Exception.ToString()
}
finally {
  try {
    $json = $result | ConvertTo-Json -Compress
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ResultPath, $json, $utf8)
  }
  catch {
  }
}

if ($result.ok -or $result.cancelled) {
  exit 0
}
exit 1
