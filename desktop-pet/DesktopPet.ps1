# Desktop Pet: a pixel cat that walks along the bottom of your screen.
# It only shows while the app named in -FollowApp is running (Claude by default).
# Use -FollowApp "" to keep it on screen all the time.
param([string]$FollowApp = "claude")

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Text;
using System.Threading;
using System.Windows.Forms;

public class DesktopPet : Form
{
    const int S = 4;                 // pixel size
    const int SW = 20, SH = 13;      // sprite size in cells
    const int FW = 190, FH = 130;    // window size
    static readonly Color Key = Color.FromArgb(255, 0, 255);

    static readonly Dictionary<string, string[]> Frames = new Dictionary<string, string[]>() {
        {"walkA", new string[]{
            "............k...k...",
            "...........kpk.kpk..",
            "...........kooooook.",
            "..k........kokoookok",
            ".kok.......kooooopok",
            ".kok.......kwwoowwk.",
            "..kok.....kkkwwwwk..",
            "...kokkkkkkooooooook",
            "....koooooooooooook.",
            "....kooooowwwwwoook.",
            "....koooowwwwwwwook.",
            "....kkoooooooooookk.",
            ".....kok.kok.kok.kok",
            ".....kk..kk...kk.kk."}},
        {"walkB", new string[]{
            "............k...k...",
            "...........kpk.kpk..",
            "...........kooooook.",
            "..k........kokoookok",
            ".kok.......kooooopok",
            ".kok.......kwwoowwk.",
            "..kok.....kkkwwwwk..",
            "...kokkkkkkooooooook",
            "....koooooooooooook.",
            "....kooooowwwwwoook.",
            "....koooowwwwwwwook.",
            "....kkoooooooooookk.",
            "......kok.kok.kok.ko",
            "......kk...kk.kk...k"}},
        {"sit", new string[]{
            "............k...k...",
            "...........kpk.kpk..",
            "...........kooooook.",
            "..k........kokoookok",
            ".kok.......kooooopok",
            ".kok.......kwwoowwk.",
            "..kok.....kkkwwwwk..",
            "...kokkkkkkooooooook",
            "....koooooooooooook.",
            "...kooooowwwwwoooook",
            "..koooooowwwwwwooook",
            "..kooooooooooooooook",
            "..kkkkkkkkkkkkkkkkkk"}},
        {"sleep", new string[]{
            "............k...k...",
            "...........kpk.kpk..",
            "...........kooooook.",
            "..k........koooooook",
            ".kok.......kkoookkok",
            ".kok.......kwwoowwk.",
            "..kok.....kkkwwwwk..",
            "...kokkkkkkooooooook",
            "....koooooooooooook.",
            "...kooooowwwwwoooook",
            "..koooooowwwwwwooook",
            "..kooooooooooooooook",
            "..kkkkkkkkkkkkkkkkkk"}}
    };

    readonly Dictionary<string, Bitmap> right = new Dictionary<string, Bitmap>();
    readonly Dictionary<string, Bitmap> left = new Dictionary<string, Bitmap>();
    readonly Random rnd = new Random();
    readonly System.Windows.Forms.Timer tick = new System.Windows.Forms.Timer();
    readonly System.Windows.Forms.Timer watch = new System.Windows.Forms.Timer();
    readonly string followApp;

    enum Mode { Walk, Sit, Sleep, Fall, Drag, Chase }
    Mode mode = Mode.Walk;
    double x, y, vy;
    int dir = 1;
    int frameCount;
    double modeTime, modeLen = 4;
    string bubble; double bubbleTime;
    double heartsTime;
    double hunger;
    Point dragOffset; Point downAt; bool moved;
    bool wanted = true;

    public DesktopPet(string app)
    {
        followApp = app;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Key;
        TransparencyKey = Key;
        DoubleBuffered = true;
        Size = new Size(FW, FH);
        Text = "Desktop Pet";
        foreach (var kv in Frames) { var b = Build(kv.Value); right[kv.Key] = b; var m = (Bitmap)b.Clone(); m.RotateFlip(RotateFlipType.RotateNoneFlipX); left[kv.Key] = m; }

        var wa = Screen.PrimaryScreen.WorkingArea;
        x = wa.Left + wa.Width * 0.6; y = wa.Bottom - FH;
        Location = new Point((int)x, (int)y);

        var menu = new ContextMenuStrip();
        menu.Items.Add("Feed", null, delegate { Feed(); });
        menu.Items.Add("Pet", null, delegate { Pet(); });
        menu.Items.Add("Sleep", null, delegate { SetMode(Mode.Sleep, 20); });
        menu.Items.Add("Wake up", null, delegate { SetMode(Mode.Walk, 5); Say("I'm up!"); });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, delegate { Application.Exit(); });
        ContextMenuStrip = menu;

        tick.Interval = 40; tick.Tick += delegate { Step(0.04); Invalidate(); }; tick.Start();
        watch.Interval = 2000; watch.Tick += delegate { CheckApp(); }; watch.Start();
        Say("Meow! Hi!");
        CheckApp();
    }

    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams
    {
        get { var cp = base.CreateParams; cp.ExStyle |= 0x80 | 0x08000000; return cp; } // tool window, no-activate
    }

    static Bitmap Build(string[] rows)
    {
        var bmp = new Bitmap(SW * S, SH * S);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.Transparent);
            int off = SH - rows.Length;
            for (int r = 0; r < rows.Length; r++)
                for (int c = 0; c < rows[r].Length; c++)
                {
                    Color col;
                    switch (rows[r][c])
                    {
                        case 'k': col = Color.FromArgb(40, 30, 30); break;
                        case 'o': col = Color.FromArgb(245, 150, 60); break;
                        case 'w': col = Color.FromArgb(255, 245, 230); break;
                        case 'p': col = Color.FromArgb(255, 140, 170); break;
                        default: continue;
                    }
                    using (var br = new SolidBrush(col)) g.FillRectangle(br, c * S, (r + off) * S, S, S);
                }
        }
        return bmp;
    }

    void CheckApp()
    {
        bool run = string.IsNullOrEmpty(followApp);
        if (!run)
        {
            foreach (var name in followApp.Split(','))
            {
                var ps = Process.GetProcessesByName(name.Trim());
                if (ps.Length > 0) run = true;
                foreach (var p in ps) p.Dispose();
                if (run) break;
            }
        }
        if (run != wanted || run != Visible)
        {
            wanted = run;
            if (run) { Show(); TopMost = true; Say("I'm back!"); } else Hide();
        }
    }

    void SetMode(Mode m, double len) { mode = m; modeTime = 0; modeLen = len; }
    void Say(string s) { bubble = s; bubbleTime = 3.2; }
    void Feed() { hunger = 0; heartsTime = 2.5; Say("Yum! Fish!"); Jump(); }
    void Pet() { heartsTime = 2.5; Say("*purr*"); if (mode == Mode.Sleep) SetMode(Mode.Sit, 3); }
    void Jump() { if (mode == Mode.Drag) return; vy = -9; SetMode(Mode.Fall, 0); }

    double Ground() { return Screen.PrimaryScreen.WorkingArea.Bottom - FH; }

    void Step(double dt)
    {
        if (!Visible) return;
        var wa = Screen.PrimaryScreen.WorkingArea;
        modeTime += dt; frameCount++;
        if (bubbleTime > 0) bubbleTime -= dt;
        if (heartsTime > 0) heartsTime -= dt;
        hunger += dt / 90.0;   // gets hungry after a few minutes
        double minX = wa.Left - 40, maxX = wa.Right - FW + 40;

        switch (mode)
        {
            case Mode.Walk:
            case Mode.Chase:
                if (mode == Mode.Chase)
                {
                    double target = Cursor.Position.X - FW / 2;
                    if (Math.Abs(target - x) < 8) { SetMode(Mode.Sit, 2 + rnd.NextDouble() * 3); Say("Got you!"); break; }
                    dir = target > x ? 1 : -1;
                }
                x += dir * (mode == Mode.Chase ? 4.2 : 2.0);
                if (x < minX) { x = minX; dir = 1; }
                if (x > maxX) { x = maxX; dir = -1; }
                if (modeTime > modeLen)
                {
                    int roll = rnd.Next(10);
                    if (roll < 4) SetMode(Mode.Sit, 3 + rnd.NextDouble() * 5);
                    else if (roll < 5) SetMode(Mode.Sleep, 10 + rnd.NextDouble() * 15);
                    else if (roll < 7) { SetMode(Mode.Chase, 8); }
                    else { dir = rnd.Next(2) == 0 ? -1 : 1; SetMode(Mode.Walk, 3 + rnd.NextDouble() * 6); }
                }
                break;
            case Mode.Sit:
                if (modeTime > modeLen) { dir = rnd.Next(2) == 0 ? -1 : 1; SetMode(Mode.Walk, 3 + rnd.NextDouble() * 6); }
                break;
            case Mode.Sleep:
                if (modeTime > modeLen) { SetMode(Mode.Sit, 2); Say("*yawn*"); }
                break;
            case Mode.Fall:
                vy += 0.6; y += vy;
                if (y >= Ground()) { y = Ground(); vy = 0; SetMode(Mode.Sit, 1.5); }
                break;
            case Mode.Drag:
                break;
        }
        if (mode != Mode.Fall && mode != Mode.Drag) y = Ground();

        if (bubbleTime <= 0 && mode != Mode.Sleep && rnd.NextDouble() < dt / 25.0)
        {
            string[] lines = hunger > 1 ? new string[] { "I'm hungry!", "Feed me!", "Fish please?" }
                                         : new string[] { "Meow!", "*purr*", "Take a break!", "Drink water!", "You got this!", "Mrrp?" };
            Say(lines[rnd.Next(lines.Length)]);
        }
        Location = new Point((int)x, (int)y);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.None;
        g.TextRenderingHint = TextRenderingHint.SingleBitPerPixelGridFit;
        string f;
        if (mode == Mode.Sleep) f = "sleep";
        else if (mode == Mode.Sit || mode == Mode.Drag) f = "sit";
        else if (mode == Mode.Fall) f = "walkA";
        else f = (frameCount / 6) % 2 == 0 ? "walkA" : "walkB";
        var bmp = dir > 0 ? right[f] : left[f];
        int bx = (FW - bmp.Width) / 2, by = FH - bmp.Height;
        if (mode == Mode.Drag) by -= 4;
        g.DrawImage(bmp, bx, by, bmp.Width, bmp.Height);

        using (var font = new Font("Segoe UI", 9f, FontStyle.Bold))
        {
            if (mode == Mode.Sleep)
            {
                int z = (int)(modeTime * 2) % 3;
                for (int i = 0; i <= z; i++)
                    g.DrawString("z", font, Brushes.SteelBlue, bx + (dir > 0 ? 70 : 2) + i * 8, by - 6 - i * 10);
            }
            if (heartsTime > 0)
            {
                using (var hf = new Font("Segoe UI Symbol", 12f, FontStyle.Bold))
                    for (int i = 0; i < 3; i++)
                        g.DrawString("♥", hf, Brushes.Crimson, bx + 10 + i * 22, by - 22 - (float)((2.5 - heartsTime) * 10) - (i % 2) * 6);
            }
            if (bubbleTime > 0 && !string.IsNullOrEmpty(bubble))
            {
                var sz = g.MeasureString(bubble, font);
                int w = (int)sz.Width + 14, h = (int)sz.Height + 8;
                int lx = Math.Max(2, Math.Min(FW - w - 2, (FW - w) / 2 + (dir > 0 ? 18 : -18)));
                int ty = Math.Max(2, by - h - 22);
                var r = new Rectangle(lx, ty, w, h);
                g.FillRectangle(Brushes.White, r);
                using (var pen = new Pen(Color.FromArgb(40, 30, 30), 2)) g.DrawRectangle(pen, r);
                g.FillRectangle(Brushes.White, lx + w / 2 - 4, ty + h - 1, 8, 6);
                g.DrawString(bubble, font, new SolidBrush(Color.FromArgb(40, 30, 30)), lx + 7, ty + 4);
            }
        }
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        dragOffset = new Point(Cursor.Position.X - Left, Cursor.Position.Y - Top);
        downAt = Cursor.Position; moved = false;
        SetMode(Mode.Drag, 0);
    }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (mode != Mode.Drag) return;
        var c = Cursor.Position;
        if (Math.Abs(c.X - downAt.X) + Math.Abs(c.Y - downAt.Y) > 4) moved = true;
        x = c.X - dragOffset.X; y = c.Y - dragOffset.Y;
        Location = new Point((int)x, (int)y);
    }
    protected override void OnMouseUp(MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left || mode != Mode.Drag) return;
        if (!moved) { SetMode(Mode.Sit, 2); Pet(); }
        else { vy = 0; SetMode(Mode.Fall, 0); Say("Wheee!"); }
    }

    public static void Run(string app)
    {
        bool fresh;
        using (var mutex = new Mutex(true, "DesktopPetCat_SingleInstance", out fresh))
        {
            if (!fresh) return;
            Application.EnableVisualStyles();
            Application.Run(new DesktopPet(app));
        }
    }
}
'@

[DesktopPet]::Run($FollowApp)
