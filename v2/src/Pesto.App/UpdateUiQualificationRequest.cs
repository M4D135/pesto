using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

internal sealed record UpdateUiQualificationRequest(int SchemaVersion, string Kind, string RequestId, string Root,
    string Installation, string CandidateZip, string ReportDirectory, string Channel, string SourceFingerprint,
    string TargetFingerprint, string SourceExecutableSha256, string TargetExecutableSha256, string SourceCommit,
    string TargetSourceCommit, string CandidateZipSha256)
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true, PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };

    internal static UpdateUiQualificationRequest Read(string requestPath)
    {
        requestPath = LocalPath(requestPath);
        var root = Path.GetDirectoryName(requestPath)!;
        var temporary = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) + Path.DirectorySeparatorChar;
        Require(root.StartsWith(temporary, StringComparison.OrdinalIgnoreCase)
            && Regex.IsMatch(Path.GetFileName(root), "^Pesto-native-update-[0-9a-f]{32}$")
            && SamePath(requestPath, Path.Combine(root, "ui-request.json")), "request-path");
        Require(new FileInfo(requestPath).Length is > 0 and <= 32 * 1024, "request-size");
        var request = JsonSerializer.Deserialize<UpdateUiQualificationRequest>(File.ReadAllText(requestPath), Json)
            ?? throw Invalid("request-json");
        Require(request.SchemaVersion == 1 && request.Kind == "pesto.native-update-ui-request"
            && Regex.IsMatch(request.RequestId ?? "", "^[0-9a-f]{32}$"), "request-schema");
        Require(SamePath(LocalPath(request.Root), root)
            && request.RequestId == Path.GetFileName(root)["Pesto-native-update-".Length..]
            && SamePath(LocalPath(request.Installation), Path.Combine(root, "cases", "normal", "installation"))
            && SamePath(LocalPath(request.ReportDirectory), Path.Combine(root, "evidence", "normal", "ui")), "request-layout");
        Require(SamePath(AppPaths.AppDirectory, request.Installation)
            && SamePath(Environment.ProcessPath!, Path.Combine(request.Installation, "Pesto.exe")), "running-copy");
        Require(request.Channel is "PROD" or "DEV", "channel");
        foreach (var hash in new[] { request.SourceFingerprint, request.TargetFingerprint, request.SourceExecutableSha256,
            request.TargetExecutableSha256, request.CandidateZipSha256 })
            Require(Regex.IsMatch(hash ?? "", "^[0-9a-f]{64}$"), "hash");
        Require(Regex.IsMatch(request.SourceCommit ?? "", "^[0-9a-f]{40}$")
            && Regex.IsMatch(request.TargetSourceCommit ?? "", "^[0-9a-f]{40}$")
            && request.SourceCommit != request.TargetSourceCommit
            && request.SourceExecutableSha256 != request.TargetExecutableSha256
            && request.SourceFingerprint != request.TargetFingerprint, "distinct-builds");
        var archive = LocalPath(request.CandidateZip);
        Require(archive.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)
            && !Within(archive, request.Installation) && !Within(archive, request.ReportDirectory)
            && File.Exists(archive) && new FileInfo(archive).Length is > 0 and <= UpdatePackage.MaxBytes, "archive");
        Require(!Directory.Exists(request.ReportDirectory) && !File.Exists(request.ReportDirectory), "new-report");
        return request;
    }

    internal static string LocalPath(string? path)
    {
        Require(!string.IsNullOrWhiteSpace(path) && Path.IsPathFullyQualified(path)
            && !path.StartsWith(@"\\", StringComparison.Ordinal) && !path.StartsWith("//", StringComparison.Ordinal)
            && !path.Any(char.IsControl), "local-path");
        var full = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path!));
        OperatorProfile.RejectLinks(full);
        Require(new DriveInfo(Path.GetPathRoot(full)!).DriveType == DriveType.Fixed, "local-volume");
        return full;
    }

    internal static bool SamePath(string left, string right) => string.Equals(
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(left)), Path.TrimEndingDirectorySeparator(Path.GetFullPath(right)),
        StringComparison.OrdinalIgnoreCase);
    internal static bool Within(string path, string root) => Path.GetFullPath(path).StartsWith(
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    internal void RequireOwned(string path)
    {
        Require(Within(LocalPath(path), Root), "owned-path");
    }
    internal static void Require(bool value, string code) { if (!value) throw Invalid(code); }
    private static PestoException Invalid(string code) => new("qualification.update-ui." + code,
        "La qualification de mise à jour exige une demande bornée à sa copie temporaire et à ses deux builds exacts.");
}
