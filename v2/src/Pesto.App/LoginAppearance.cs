using Microsoft.Win32;
using Pesto.Core;
using Pesto.Engine;
using System.Security;
using System.Text;

namespace Pesto.App;

// Only this four-value appearance hint crosses from the live shell to the next native login.
internal sealed class LoginThemePreference(string dataRoot)
{
    private readonly string path = Path.Combine(dataRoot, "login-theme.txt");
    internal static bool IsKnown(string? value) => value is "light" or "dark" or "contrast" or "system";

    internal string Read()
    {
        try
        {
            UpdatePackage.RequireNoLinks(path);
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is < 4 or > 8) return "system";
            var bytes = new byte[(int)stream.Length];
            stream.ReadExactly(bytes);
            var value = Encoding.ASCII.GetString(bytes);
            return IsKnown(value) ? value : "system";
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or SecurityException or PestoException) { return "system"; }
    }

    internal void Save(string? value)
    {
        if (!IsKnown(value) || value == Read()) return;
        try { UpdatePackage.WriteAtomic(path, value!); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or SecurityException or PestoException) { }
    }
}

internal sealed record LoginPalette(string Theme, Color Background, Color Input, Color Ink, Color Muted,
    Color Border, Color Accent, Color OnAccent, Color AccentHover, Color Hover, Color Alert, bool ForcedColors = false)
{
    internal static LoginPalette ForWindows(string preference)
    {
        var systemDark = false;
        if (preference == "system" && !SystemInformation.HighContrast)
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                systemDark = key?.GetValue("AppsUseLightTheme") is 0;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or SecurityException) { }
        }
        return Resolve(preference, SystemInformation.HighContrast, systemDark);
    }

    // Same roles as wad/web/css/tokens.css. Forced Windows colors override explicit colors, as in the shell.
    internal static LoginPalette Resolve(string preference, bool highContrast, bool systemDark)
    {
        if (highContrast) return new("contrast", SystemColors.Window, SystemColors.Window, SystemColors.WindowText,
            SystemColors.WindowText, SystemColors.WindowText, SystemColors.Highlight, SystemColors.HighlightText,
            SystemColors.Highlight, SystemColors.Control, SystemColors.WindowText, true);
        static Color C(int rgb) => Color.FromArgb(255, Color.FromArgb(rgb));
        return preference switch
        {
            "contrast" => new("contrast", Color.Black, Color.Black, Color.White, Color.White, Color.White,
                C(0x1aebff), Color.Black, Color.Yellow, C(0x1a1a1a), C(0xff6b6b)),
            "dark" or "system" when preference == "dark" || systemDark => new("dark", C(0x0d1625), C(0x13203a),
                C(0xedf4ff), C(0xbfcee2), C(0x64809f), C(0x2470d6), Color.White, C(0x1f6fd1), C(0x1d3050), C(0xfca5a5)),
            _ => new("light", C(0xf3f6fb), Color.White, C(0x17243a), C(0x52627b), C(0x8392a8), C(0x066ddb),
                Color.White, C(0x0a5fbf), C(0xf0f6ff), C(0xb91c1c))
        };
    }
}
