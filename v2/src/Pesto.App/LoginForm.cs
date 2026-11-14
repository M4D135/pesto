using System.Runtime.InteropServices;
using System.Security;
using System.Security.Principal;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.App;

/// <summary>Native login, before WebView creation. No password property is read as a managed string.</summary>
internal sealed class LoginForm : Form
{
    private readonly TextBox account;
    private readonly NativePasswordBox password;
    private readonly Label error;
    private readonly Button connect;
    private readonly Button? windows;
    private readonly Label caps;
    private WindowsAdCredentialSource? credential;
    private readonly LoginPalette palette;
    private readonly PictureBox logo = new();
    internal PictureBox LogoControl => logo;
    internal bool UseWindowsAccount { get; private set; }
    internal TextBox AccountControl => account;
    internal TextBox PasswordControl => password;
    internal Button ConnectControl => connect;
    internal Button? WindowsControl => windows;
    internal bool HasValidationError => error.Text.Length > 0;
    internal bool LayoutFits => Screen.FromControl(this).WorkingArea.Contains(Bounds) && Fits(this);

    private bool Fits(Control parent) => parent.Controls.Cast<Control>().All(child => !child.Visible
        || (parent.RectangleToScreen(parent.ClientRectangle).Contains(child.RectangleToScreen(child.ClientRectangle))
            && (child is not ScrollableControl scroll || !scroll.AutoScroll)
            && Fits(child)));

    internal LoginForm(bool allowWindowsAccount, LoginPalette palette, string? displayedWindowsAccount = null)
    {
        this.palette = palette;
        Text = "Pesto — Connexion";
        Icon = ApplicationBrand.CreateWindowIcon();
        AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Segoe UI", 10);
        BackColor = palette.Background; ForeColor = palette.Ink;
        ClientSize = new Size(540, allowWindowsAccount ? 620 : 520);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MinimizeBox = false; MaximizeBox = false;
        var body = new Panel { Dock = DockStyle.Fill, Padding = new Padding(32, 24, 32, 24) };
        Controls.Add(body);
        var content = new TableLayoutPanel { AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top, ColumnCount = 1, RowCount = 0, Margin = Padding.Empty };
        content.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        body.Controls.Add(content);
        var usualGaps = new Dictionary<Control, int>();
        void Row(Control control, int bottom = 12)
        {
            usualGaps.Add(control, bottom);
            control.Dock = DockStyle.Top; control.Margin = new Padding(0, 0, 0, bottom);
            content.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            content.Controls.Add(control, 0, content.RowCount++);
        }
        Label Label(string text, float size, Color color, FontStyle style = FontStyle.Regular) => new()
        {
            Text = text, AutoSize = true, ForeColor = color, Font = new Font("Segoe UI", size, style),
            MaximumSize = new Size(460, 0), UseMnemonic = false
        };
        Row(BrandHeader(), 12);
        Row(Label("Connexion à l’annuaire", 20, palette.Ink, FontStyle.Bold), 16);
        if (allowWindowsAccount)
        {
            string effective;
            if (displayedWindowsAccount is not null) effective = displayedWindowsAccount;
            else { using var identity = WindowsIdentity.GetCurrent(); effective = identity.Name; }
            windows = MakeButton("Continuer avec le compte Windows", false);
            windows.AccessibleDescription = "Utilise le compte effectif après élévation UAC : " + effective;
            windows.Click += (_, _) => SelectWindows();
            Row(windows, 5);
            Row(Label(effective, 9, palette.Muted), 16);

        }
        account = new TextBox { BorderStyle = BorderStyle.None, BackColor = palette.Input, ForeColor = palette.Ink,
            Font = new Font("Segoe UI", 11), MaxLength = 512, AccessibleName = "Compte Active Directory",
            PlaceholderText = "DOMAINE\\utilisateur", TabIndex = 0 };
        Row(Label("Compte Active Directory", 10, palette.Ink, FontStyle.Bold), 7);
        Row(Frame(account), 6);
        Row(Label("DOMAINE\\utilisateur ou utilisateur@domaine", 9, palette.Muted), 14);
        password = new NativePasswordBox { BorderStyle = BorderStyle.None, BackColor = palette.Input, ForeColor = palette.Ink,
            Font = new Font("Segoe UI", 11), MaxLength = 4096, UseSystemPasswordChar = true,
            AccessibleName = "Mot de passe", TabIndex = 1 };
        Row(Label("Mot de passe", 10, palette.Ink, FontStyle.Bold), 7);
        Row(Frame(password), 5);
        caps = Label("", 9, palette.Muted);
        caps.Visible = false;
        Row(caps, 0);
        void Caps() { caps.Text = "Verr. maj. est activé"; caps.Visible = IsKeyLocked(Keys.CapsLock); }
        password.KeyUp += (_, _) => Caps(); password.Enter += (_, _) => Caps();
        error = Label("", 9, palette.Alert);
        error.AccessibleRole = AccessibleRole.Alert;
        error.MinimumSize = new Size(0, 32);
        Row(error, 4);
        connect = MakeButton("Se connecter", true);
        connect.Click += (_, _) => Submit();
        Row(connect, 10);
        var cancel = MakeButton("Continuer dans les paramètres", false);
        cancel.DialogResult = DialogResult.Cancel;
        cancel.Click += (_, _) => { password.Clear(); Close(); };
        Row(cancel, 14);
        Row(Label("Mot de passe utilisé uniquement pour cette session.", 9, palette.Muted), 0);
        AcceptButton = connect; CancelButton = cancel;
        FormClosing += (_, _) => password.Clear();
        var fitting = false;
        void FitContents()
        {
            if (fitting || !IsHandleCreated || !Visible || IsDisposed) return;
            fitting = true;
            try
            {
                var area = Screen.FromControl(this).WorkingArea;
                int Px(int logical) => LogicalToDeviceUnits(logical);
                var maxWidth = Math.Max(1, area.Width - (Width - ClientSize.Width) - Px(12));
                var maxHeight = Math.Max(1, area.Height - (Height - ClientSize.Height) - Px(12));
                if (ClientSize.Width > maxWidth) ClientSize = new Size(maxWidth, ClientSize.Height);
                int Measure(bool compact)
                {
                    body.Padding = new Padding(Px(compact ? 16 : 32), Px(compact ? 6 : 24), Px(compact ? 16 : 32), Px(compact ? 6 : 24));
                    foreach (var (control, gap) in usualGaps)
                    {
                        control.Margin = new Padding(0, 0, 0, Px(compact ? Math.Min(gap, 3) : gap));
                        if (control is Label label) label.MaximumSize = new Size(Math.Max(1, body.ClientSize.Width - body.Padding.Horizontal), 0);
                        if (control is Button) control.Height = Px(compact ? 34 : 43);
                        if (control is Panel frame && frame.Controls.Count == 1 && frame.Controls[0] is TextBox)
                        {
                            frame.Height = Px(compact ? 36 : 48);
                            frame.Padding = new Padding(Px(14), Px(compact ? 6 : 13), Px(14), Px(compact ? 5 : 10));
                        }
                    }
                    content.PerformLayout();
                    return content.GetPreferredSize(new Size(Math.Max(1, body.ClientSize.Width - body.Padding.Horizontal), 0)).Height + body.Padding.Vertical;
                }
                var needed = Measure(false);
                if (needed > maxHeight) needed = Measure(true);
                ClientSize = new Size(ClientSize.Width, needed);
                if (needed > maxHeight)
                {
                    var fit = (float)maxHeight / needed;
                    Scale(new SizeF(fit, fit));
                }
                Location = new Point(area.Left + (area.Width - Width) / 2, area.Top + (area.Height - Height) / 2);
            }
            finally { fitting = false; }
        }
        error.TextChanged += (_, _) => FitContents();
        caps.VisibleChanged += (_, _) => FitContents();
        DpiChanged += (_, _) => BeginInvoke((Action)FitContents);
        Shown += (_, _) =>
        {
            FitContents();
            if (windows is not null) { AcceptButton = windows; windows.Focus(); } else account.Focus();
        };
        account.Enter += (_, _) => AcceptButton = connect;
        password.Enter += (_, _) => AcceptButton = connect;
        if (windows is not null) windows.Enter += (_, _) => AcceptButton = windows;
    }

    private Control Frame(TextBox input)
    {
        var panel = new Panel { Height = 48, Padding = new Padding(14, 13, 14, 10), BackColor = palette.Input };
        input.Dock = DockStyle.Fill; panel.Controls.Add(input);
        panel.Paint += (_, e) =>
        {
            using var pen = new Pen(input.Focused ? palette.Accent : palette.Border, input.Focused ? 2 : 1);
            e.Graphics.DrawRectangle(pen, 1, 1, panel.Width - 3, panel.Height - 3);
        };
        input.Enter += (_, _) => panel.Invalidate(); input.Leave += (_, _) => panel.Invalidate();
        return panel;
    }

    private Button MakeButton(string text, bool primary)
    {
        var button = new Button { Text = text, Height = 43, FlatStyle = FlatStyle.Flat,
            BackColor = primary ? palette.Accent : palette.Input,
            ForeColor = primary ? palette.OnAccent : palette.Ink, Cursor = Cursors.Hand,
            Font = new Font("Segoe UI", 10, primary ? FontStyle.Bold : FontStyle.Regular), UseVisualStyleBackColor = false };
        button.FlatAppearance.BorderColor = primary ? button.BackColor : palette.Border;
        button.FlatAppearance.MouseOverBackColor = primary ? palette.AccentHover : palette.Hover;
        return button;
    }

    private void SelectWindows()
    {
        UseWindowsAccount = true; password.Clear(); DialogResult = DialogResult.OK; Close();
    }

    private void Submit()
    {
        error.Text = "";
        try
        {
            using var secret = password.ReadSecure();
            credential = WindowsAdCredentialSource.FromSecurePassword(account.Text, secret);
            password.Clear(); DialogResult = DialogResult.OK; Close();
        }
        catch (PestoException ex)
        {
            error.Text = ex.Message;
            if (ex.Code == "credential.invalid") account.Focus(); else password.Focus();
        }
    }

    internal WindowsAdCredentialSource? TakeCredential()
    {
        var result = credential; credential = null; return result;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { logo.Image = null; password.Clear(); credential?.Dispose(); credential = null; }
        base.Dispose(disposing);
    }

    private sealed class NativePasswordBox : TextBox
    {
        internal SecureString ReadSecure()
        {
            // WM_GETTEXT goes directly to a bounded native buffer. Never read Text or SelectedText.
            var bytes = checked((MaxLength + 1) * 2);
            var buffer = Marshal.AllocHGlobal(bytes);
            try
            {
                var count = (int)SendMessageW(Handle, 0x000D, MaxLength + 1, buffer);
                if (count is < 0 or > 4096) throw new PestoException("credential.empty", "Mot de passe invalide.");
                var value = new SecureString();
                try
                {
                    for (var i = 0; i < count; i++) value.AppendChar((char)Marshal.ReadInt16(buffer, i * 2));
                    value.MakeReadOnly(); return value;
                }
                catch { value.Dispose(); throw; }
            }
            finally
            {
                for (var i = 0; i < bytes; i++) Marshal.WriteByte(buffer, i, 0);
                Marshal.FreeHGlobal(buffer);
            }
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern nint SendMessageW(nint window, uint message, nint wParam, nint lParam);
    }

    private Control BrandHeader()
    {
        var header = new TableLayoutPanel
        {
            AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, ColumnCount = 2, RowCount = 1,
            Padding = Padding.Empty, Margin = Padding.Empty, TabStop = false
        };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        header.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        // WinForms scales the control per monitor. Zoom fits the complete bitmap in its actual bounds.
        logo.Image = ApplicationBrand.Mark; logo.SizeMode = PictureBoxSizeMode.Zoom;
        logo.Size = new Size(40, 40); logo.Anchor = AnchorStyles.Left; logo.Margin = new Padding(0, 0, 10, 0);
        logo.AccessibleRole = AccessibleRole.Graphic; logo.AccessibleName = "Logo Pesto"; logo.TabStop = false;
        header.Controls.Add(logo, 0, 0);
        header.Controls.Add(new Label { Text = "Pesto", AutoSize = true, Anchor = AnchorStyles.Left,
            Margin = Padding.Empty, Font = new Font("Segoe UI", 19, FontStyle.Bold), ForeColor = palette.Ink }, 1, 0);
        return header;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        if (!palette.ForcedColors)
        {
            var dark = palette.Theme == "light" ? 0 : 1;
            _ = DwmSetWindowAttribute(Handle, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, ref dark, sizeof(int));
        }
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(nint window, int attribute, ref int value, int bytes);
}
