using System.Drawing.Imaging;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;
using Pesto.Engine.Live;

namespace Pesto.App;

/// <summary>Real native controls and DPAPI, fixed synthetic credential only. No directory or ordinary profile.</summary>
internal static class NativeLoginQualification
{
    internal static int Run(string destination)
    {
        var output = Path.TrimEndingDirectorySeparator(Path.GetFullPath(destination));
        var temporary = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) + Path.DirectorySeparatorChar;
        if (!output.StartsWith(temporary, StringComparison.OrdinalIgnoreCase) || output.Length <= temporary.Length
            || Directory.Exists(output) || File.Exists(output))
            throw new PestoException("qualification.path", "Un nouveau sous-dossier temporaire dédié est requis.");
        OperatorProfile.RejectLinks(output); Directory.CreateDirectory(output);
        var checks = new JsonArray();
        var proof = new JsonObject { ["kind"] = "pesto.native-login-qualification", ["schemaVersion"] = 1,
            ["success"] = false, ["adExecuted"] = false, ["ordinaryProfileAccess"] = false,
            ["checks"] = checks, ["utc"] = DateTimeOffset.UtcNow.ToString("O"),
            ["captures"] = new JsonArray() };
        void Check(bool value, string name)
        {
            if (!value) throw new PestoException("qualification.login." + name, "Contrôle de connexion non satisfait : " + name);
            checks.Add(name);
        }
        void Capture(LoginForm form, string name)
        {
            form.Refresh(); Application.DoEvents();
            using var image = new Bitmap(form.Width, form.Height);
            form.DrawToBitmap(image, new Rectangle(Point.Empty, image.Size));
            image.Save(Path.Combine(output, name), ImageFormat.Png);
            ((JsonArray)proof["captures"]!).Add(name);
        }
        void Run(LoginForm form, Action action)
        {
            Exception? failure = null;
            form.Shown += (_, _) =>
            {
                try { action(); }
                catch (Exception ex) { failure = ex; form.Close(); }
            };
            form.ShowDialog();
            if (failure is not null) throw failure;
        }
        try
        {
            const string sentinel = "Synthetic-é-東京-Login-42";
            var preference = new LoginThemePreference(Path.Combine(output, "synthetic-profile"));
            var light = LoginPalette.Resolve("light", false, true);
            var dark = LoginPalette.Resolve("dark", false, false);
            var contrast = LoginPalette.Resolve("contrast", false, false);
            Check(preference.Read() == "system" && LoginPalette.Resolve("system", false, false) == light
                && LoginPalette.Resolve("system", false, true) == dark, "systemFollowsWindows");
            Check(LoginPalette.Resolve("light", true, false) is { Theme: "contrast", ForcedColors: true } forced
                && forced.Background == SystemColors.Window && forced.Ink == SystemColors.WindowText, "windowsForcedColorsWin");
            preference.Save("dark"); preference.Save("unknown");
            Check(new LoginThemePreference(Path.Combine(output, "synthetic-profile")).Read() == "dark", "onlyKnownThemePersists");
            Check(HostAuthentication.Select(true, false) == HostAuthenticationMode.Windows, "domainAutoLogin");
            Check(HostAuthentication.Select(false, false) == HostAuthenticationMode.ExplicitAd, "workgroupRequiresLogin");
            Check(HostAuthentication.Select(true, true) == HostAuthenticationMode.ChooseAccount, "explicitAccountChoice");
            using (var form = new LoginForm(false, light))
            {
                Run(form, () =>
                {
                proof["deviceDpi"] = form.DeviceDpi;
                Check(form.Visible && form.WindowsControl is null && form.AccountControl.Focused, "explicitNativeForm");
                Check(form.PasswordControl.UseSystemPasswordChar && form.PasswordControl.MaxLength == 4096, "maskedBoundedPassword");
                Check(form.LayoutFits, "explicitFormFitsWithoutScrolling");
                Check(form.BackColor == light.Background && form.AccountControl.BackColor == light.Input
                    && form.AccountControl.ForeColor == light.Ink && form.ConnectControl.ForeColor == light.OnAccent, "lightControls");
                Check(LogoCornersMatch(form.LogoControl) && form.LogoControl.SizeMode == PictureBoxSizeMode.Zoom, "completeLogoAtDeviceDpi");
                proof["logoPixels"] = form.LogoControl.Width;
                Capture(form, "login-ad.png");
                var naturalSize = form.LogoControl.Size;
                var scaledSizes = new JsonArray();
                foreach (var dpi in new[] { 96, 120, 144, 192 })
                {
                    var pixels = (40 * dpi + 48) / 96;
                    form.LogoControl.Size = new Size(pixels, pixels);
                    if (LogoCornersMatch(form.LogoControl)) scaledSizes.Add(pixels);
                }
                form.LogoControl.Size = naturalSize;
                proof["testedLogoPixelSizes"] = scaledSizes;
                Check(scaledSizes.Count == 4, "completeLogoAtScaledPixelSizes");
                form.ClientSize = new Size(420, form.ClientSize.Height);
                form.AccountControl.Text = "unqualified";
                form.ConnectControl.PerformClick(); Application.DoEvents();
                Check(form.Visible && form.HasValidationError && form.TakeCredential() is null && form.LayoutFits, "invalidAccountStaysOpen");
                Capture(form, "login-validation.png");
                form.AccountControl.Text = "EXAMPLE\\fixture";
                form.ConnectControl.PerformClick(); Application.DoEvents();
                Check(form.Visible && form.HasValidationError && form.PasswordControl.Focused && form.LayoutFits, "emptyPasswordStaysOpen");
                form.PasswordControl.Text = sentinel;
                form.ConnectControl.PerformClick(); Application.DoEvents();
                using var acquired = form.TakeCredential();
                Check(form.DialogResult == DialogResult.OK && acquired is not null && form.PasswordControl.TextLength == 0, "submitAndClear");
                var envelope = acquired!.CreateProtectedPayload();
                Check(!envelope.ToString().Contains(sentinel, StringComparison.Ordinal) && !envelope.Blob.Contains(sentinel, StringComparison.Ordinal), "protectedEnvelope");
                using var roundTrip = WindowsAdCredentialSource.FromProtectedPayload(envelope);
                using var diagnostic = roundTrip.AcquireForDiagnostic();
                Check(diagnostic is not null && diagnostic.TakePassword() == sentinel, "unicodeDpapiRoundTrip");
                });
            }
            using (var form = new LoginForm(true, LoginPalette.Resolve(preference.Read(), false, false), @"EXAMPLE\fixture"))
            {
                Run(form, () =>
                {
                Check(form.WindowsControl is { Focused: true } && form.AcceptButton == form.WindowsControl, "windowsDefaultOnExplicitChooser");
                Check(form.LayoutFits, "accountChoiceFitsWithoutScrolling");
                Check(form.BackColor == dark.Background && form.AccountControl.ForeColor == dark.Ink
                    && form.WindowsControl!.FlatAppearance.MouseOverBackColor == dark.Hover, "darkControlsAfterRestart");
                Capture(form, "login-account-choice.png");
                form.PasswordControl.Text = sentinel;
                form.WindowsControl!.PerformClick(); Application.DoEvents();
                Check(form.UseWindowsAccount && form.DialogResult == DialogResult.OK && form.TakeCredential() is null
                    && form.PasswordControl.TextLength == 0, "windowsChoiceClearsPassword");
                });
            }
            using (var form = new LoginForm(false, contrast))
            {
                Run(form, () =>
                {
                Check(form.BackColor == Color.Black && form.AccountControl.ForeColor == Color.White
                    && form.ConnectControl.ForeColor == Color.Black && form.LayoutFits, "explicitContrastControls");
                Capture(form, "login-contrast.png");
                form.PasswordControl.Text = sentinel;
                ((Button)form.CancelButton!).PerformClick(); Application.DoEvents();
                Check(form.DialogResult == DialogResult.Cancel && form.TakeCredential() is null
                    && form.PasswordControl.TextLength == 0, "cancelClearsPassword");
                });
            }
            Check(Program.UiFailure is null, "noUiException");
            proof["executableSha256"] = UpdatePackage.Hash(Environment.ProcessPath!);
            proof["success"] = true;
        }
        catch (PestoException ex) { proof["failureCode"] = ex.Code; }
        catch (Exception) { proof["failureCode"] = "qualification.login.unexpected"; }
        File.WriteAllText(Path.Combine(output, "proof.json"), proof.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        return proof["success"]!.GetValue<bool>() ? 0 : 2;
    }

    private static bool LogoCornersMatch(PictureBox logo)
    {
        if (logo.Width != logo.Height || logo.Width < 16 || logo.Image is not Bitmap mark) return false;
        using var painted = new Bitmap(logo.Width, logo.Height);
        logo.DrawToBitmap(painted, logo.ClientRectangle);
        foreach (var x in new[] { 1, painted.Width - 2 })
        foreach (var y in new[] { 1, painted.Height - 2 })
        {
            var expected = mark.GetPixel((int)((x + .5) * mark.Width / painted.Width), (int)((y + .5) * mark.Height / painted.Height));
            var actual = painted.GetPixel(x, y);
            if (Math.Abs(expected.R - actual.R) > 24 || Math.Abs(expected.G - actual.G) > 24 || Math.Abs(expected.B - actual.B) > 24) return false;
        }
        return true;
    }
}
