using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

public sealed record UpdateTransactionResult(string Status, string Message);
public sealed record UpdateTransactionSummary(string Id, string TransactionDirectory, string Status, DateTimeOffset CreatedUtc, string CurrentVersion = "");

/// <summary>Durable binary replacement. Stage, backup and failed candidate share the target volume; user data is never moved.</summary>
public static class UpdateTransaction
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly HashSet<string> States = new(StringComparer.Ordinal)
    {
        "prepared", "backingUp", "backedUp", "installing", "installed", "checking", "completed", "rollbackRequested",
        "recoveryRequested", "rollingBack", "restored", "rolledBack", "rollbackHealthFailed", "cancelled"
    };

    public static UpdateInstallRequest Create(string installation, string source, UpdatePackageInfo current, UpdatePackageInfo next, string action,
        string? sourceDefaultSha256)
    {
        if (action != "install") throw new PestoException("update.action", "Une transaction doit commencer par une installation préparée.");
        installation = NormalizeInstallation(installation);
        if (UpdatePackage.Validate(installation, current.Channel).Fingerprint != current.Fingerprint
            || UpdatePackage.Validate(source, next.Channel).Fingerprint != next.Fingerprint)
            throw new PestoException("update.changed", "Le pack a changé avant la préparation transactionnelle.");
        var root = TransactionRoot(installation);
        Directory.CreateDirectory(root);
        using var admission = Lock(root);
        if (List(installation).Any(t => t.Status is not ("completed" or "rolledBack" or "cancelled")))
            throw new PestoException("update.pending", "Une transaction interrompue doit être traitée avant une nouvelle installation.");
        var id = Guid.NewGuid().ToString("N");
        var directory = Path.Combine(root, id);
        Directory.CreateDirectory(directory);
        try
        {
            UpdatePackage.CopyToNew(source, Path.Combine(directory, "stage"));
            // The source's default configuration is outside its identity: it must still be the one inspected and prepared.
            if (UpdatePackage.Validate(Path.Combine(directory, "stage"), next.Channel).Fingerprint != next.Fingerprint
                || InstallationDefaults.Inspect(Path.Combine(directory, "stage")).Sha256 != sourceDefaultSha256)
                throw new PestoException("update.changed", "La copie de préparation n’est pas identique au pack vérifié.");
            // LIGHT packs never ship WebView2: the installation's Socle, validated exactly above, follows the new version.
            var socle = Path.Combine(installation, SocleRuntime.RelativeDirectory);
            var carried = Path.Combine(directory, "stage", SocleRuntime.RelativeDirectory);
            if (Directory.Exists(socle) && !Directory.Exists(carried))
            {
                UpdatePackage.CopyToNew(socle, carried);
                var stage = UpdatePackage.Validate(Path.Combine(directory, "stage"), next.Channel);
                if (stage.Fingerprint != next.Fingerprint || !stage.SoclePresent)
                    throw new PestoException("update.socle", "Le pack WebView2 du Socle n’a pas pu être recopié à l’identique vers la nouvelle version.");
            }
            // The installation's default configuration follows the new version too (GLPI-Pilot 3.10.1 rule): it is outside
            // the pack identity, a different default brought by the source is refused, and its digest is sealed for Execute.
            var installationDefault = InstallationDefaults.CarryIntoStage(installation, Path.Combine(directory, "stage"));
            if (UpdatePackage.Validate(Path.Combine(directory, "stage"), next.Channel).Fingerprint != next.Fingerprint)
                throw new PestoException("update.changed", "La copie de préparation n’est pas identique au pack vérifié.");
            InstallationDefaults.WriteMarker(directory, installationDefault, InstallationDefaults.Inspect(Path.Combine(directory, "stage")).Sha256);
            Directory.CreateDirectory(Path.Combine(directory, "helper"));
            var helper = Path.Combine(directory, "helper", "Pesto.exe");
            File.Copy(Path.Combine(installation, "Pesto.exe"), helper, false);
            using var parent = Process.GetCurrentProcess();
            var record = new TransactionRecord
            {
                Id = id, Installation = installation, Channel = current.Channel,
                CurrentFingerprint = current.Fingerprint, NextFingerprint = next.Fingerprint,
                CurrentVersion = current.Version, NextVersion = next.Version,
                CurrentExecutableHash = UpdatePackage.Hash(Path.Combine(installation, "Pesto.exe")),
                NextExecutableHash = UpdatePackage.Hash(Path.Combine(source, "Pesto.exe")),
                HelperHash = UpdatePackage.Hash(helper), CreatedUtc = DateTimeOffset.UtcNow,
                ParentProcessId = parent.Id, ParentStartUtc = parent.StartTime.ToUniversalTime(),
                Status = "prepared", Action = "install"
            };
            if (UpdatePackage.Validate(installation, current.Channel).Fingerprint != current.Fingerprint
                || record.HelperHash != record.CurrentExecutableHash || InstallationDefaults.CurrentSha256(installation) != installationDefault)
                throw new PestoException("update.changed", "L’installation a changé pendant la préparation du programme de remplacement.");
            Save(directory, record);
            return new(directory, helper, id, action);
        }
        catch { UpdatePackage.TryRemoveOwned(directory); throw; }
    }

    public static IReadOnlyList<UpdateTransactionSummary> List(string installation)
    {
        installation = NormalizeInstallation(installation);
        var root = TransactionRoot(installation);
        UpdatePackage.RequireNoLinks(root);
        if (!Directory.Exists(root)) return [];
        var results = new List<UpdateTransactionSummary>();
        foreach (var directory in Directory.EnumerateDirectories(root))
        {
            UpdatePackage.RequireNoLinks(directory);
            if (!Regex.IsMatch(Path.GetFileName(directory), "^[0-9a-f]{32}$")) continue;
            if (!File.Exists(Path.Combine(directory, "transaction.json")))
            {
                // An interrupted preparation has not touched the installation; it cannot authorize a replacement.
                continue;
            }
            var record = Read(directory);
            results.Add(new(record.Id, directory, record.Status, record.CreatedUtc, record.CurrentVersion));
        }
        return results.OrderByDescending(r => r.CreatedUtc).ToArray();
    }

    public static UpdateInstallRequest RequestRollback(string transactionDirectory, bool recovery)
    {
        var record = Read(transactionDirectory);
        using var admission = Lock(TransactionRoot(record.Installation));
        record = Read(transactionDirectory);
        if (!recovery && record.Status != "completed") throw new PestoException("update.rollback", "Ce retour ne correspond pas à une installation terminée.");
        if (recovery && record.Status is "completed" or "rolledBack" or "cancelled")
            throw new PestoException("update.recovery", "Cette transaction ne demande aucune reprise.");
        ValidateTrees(transactionDirectory, record);
        // The helper is the program of CurrentVersion. Before 2.0.14 its validator refuses an undeclared defaults file and
        // would never finish: the local default is set aside in this transaction directory, never deleted.
        if (Version.Parse(record.CurrentVersion) < InstallationDefaults.MinimumVersion)
            InstallationDefaults.SetAsideForLegacyHelper(record.Installation, transactionDirectory);
        record.Action = recovery ? "recover" : "rollback";
        record.Status = recovery ? "recoveryRequested" : "rollbackRequested";
        using var parent = Process.GetCurrentProcess();
        record.ParentProcessId = parent.Id;
        record.ParentStartUtc = parent.StartTime.ToUniversalTime();
        Save(transactionDirectory, record);
        return new(transactionDirectory, Path.Combine(transactionDirectory, "helper", "Pesto.exe"), record.Id, record.Action);
    }

    public static string ReadInstallationDirectory(string transactionDirectory) => Read(transactionDirectory).Installation;

    /// <summary>Read the durable, closed health-attempt receipts without changing their state.</summary>
    public static IReadOnlyList<JsonObject> ReadHealthAttempts(string transactionDirectory)
    {
        var record = Read(transactionDirectory);
        return ReadHealthAttempts(transactionDirectory, record);
    }

    public static void ValidateHelperInvocation(string transactionDirectory, string currentExecutable)
    {
        var record = Read(transactionDirectory);
        var expected = Path.Combine(Path.GetFullPath(transactionDirectory), "helper", "Pesto.exe");
        if (!string.Equals(Path.GetFullPath(currentExecutable), expected, StringComparison.OrdinalIgnoreCase)
            || UpdatePackage.Hash(expected) != record.HelperHash)
            throw new PestoException("update.helper", "Le programme de mise à jour ne correspond pas à la transaction préparée.");
    }

    public static async Task<UpdateTransactionResult> ExecuteAsync(string transactionDirectory,
        Func<string, string, string, CancellationToken, Task<bool>> healthCheck, CancellationToken cancellationToken = default,
        Func<CancellationToken, Task>? beforeReplacement = null)
    {
        var record = Read(transactionDirectory);
        await WaitParentAsync(record, cancellationToken).ConfigureAwait(false);
        if (beforeReplacement is not null) await beforeReplacement(cancellationToken).ConfigureAwait(false);
        return await ExecuteCoreAsync(transactionDirectory, healthCheck, cancellationToken).ConfigureAwait(false);
    }

    internal static async Task<UpdateTransactionResult> ExecuteCoreAsync(string transactionDirectory,
        Func<string, string, string, CancellationToken, Task<bool>> healthCheck, CancellationToken cancellationToken = default,
        Action<string>? checkpoint = null)
    {
        var record = Read(transactionDirectory);
        using var admission = Lock(TransactionRoot(record.Installation));
        record = Read(transactionDirectory);
        ValidateTrees(transactionDirectory, record);
        if (record.Status is "rolledBack" or "cancelled") return new(record.Status, "La transaction a déjà été rétablie ; aucun fichier n’a été rejoué.");
        if (record.Status == "completed" && record.Action == "install") return new("completed", "Cette installation est déjà terminée.");
        if (record.Action != "install" || record.Status != "prepared")
            return await RollbackAsync(transactionDirectory, record, healthCheck, cancellationToken, checkpoint).ConfigureAwait(false);
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!Directory.Exists(record.Installation) || Directory.Exists(Path.Combine(transactionDirectory, "backup")))
                throw new PestoException("update.state", "L’état des dossiers ne permet pas de commencer l’installation.");
            if (InstallationDefaults.TryReadMarker(transactionDirectory, out var preparedDefault, out var stagedDefault)
                && (InstallationDefaults.CurrentSha256(record.Installation) != preparedDefault
                    || InstallationDefaults.CurrentSha256(Path.Combine(transactionDirectory, "stage")) != stagedDefault))
                throw new PestoException("update.changed", "La configuration par défaut de l’installation a changé depuis la préparation de la mise à jour. Aucun fichier n’a été remplacé ; préparez de nouveau la mise à jour.");
            SetState(transactionDirectory, record, "backingUp", checkpoint);
            Directory.Move(record.Installation, Path.Combine(transactionDirectory, "backup"));
            checkpoint?.Invoke("backupMoved");
            SetState(transactionDirectory, record, "backedUp", checkpoint);
            SetState(transactionDirectory, record, "installing", checkpoint);
            Directory.Move(Path.Combine(transactionDirectory, "stage"), record.Installation);
            checkpoint?.Invoke("candidateMoved");
            SetState(transactionDirectory, record, "installed", checkpoint);
            var installed = UpdatePackage.Validate(record.Installation, record.Channel);
            if (installed.Fingerprint != record.NextFingerprint) throw new PestoException("update.changed", "Le pack installé ne correspond pas à la préparation.");
            SetState(transactionDirectory, record, "checking", checkpoint);
            if (!await CheckHealthAsync(transactionDirectory, record, false, healthCheck, cancellationToken).ConfigureAwait(false))
                throw new PestoException("update.health", "Le contrôle de santé du nouveau programme n’a pas confirmé le démarrage de WebView2.");
            SetState(transactionDirectory, record, "completed", checkpoint);
            return new("completed", "Mise à jour installée et contrôle de santé confirmé. La configuration utilisateur est conservée.");
        }
        catch (UpdateInterruptionException) { throw; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or PestoException or JsonException or OperationCanceledException)
        {
            record.Failure = error is PestoException pe ? pe.Code : "update.interrupted";
            record.Action = "recover";
            Save(transactionDirectory, record);
            // Once replacement has begun, cancelling the request must not cancel restoration of the backup.
            return await RollbackAsync(transactionDirectory, record, healthCheck, CancellationToken.None, checkpoint).ConfigureAwait(false);
        }
    }

    private static async Task<UpdateTransactionResult> RollbackAsync(string directory, TransactionRecord record,
        Func<string, string, string, CancellationToken, Task<bool>> healthCheck, CancellationToken cancellationToken, Action<string>? checkpoint)
    {
        var backup = Path.Combine(directory, "backup");
        var failed = Path.Combine(directory, "failed-candidate");
        ValidateTrees(directory, record);
        if (!Directory.Exists(backup))
        {
            if (!Directory.Exists(record.Installation) || UpdatePackage.Validate(record.Installation, record.Channel).Fingerprint != record.CurrentFingerprint)
                throw new PestoException("update.recovery", "La sauvegarde binaire est absente et l’état initial n’est pas confirmé. Aucun dossier n’a été supprimé.");
            if (!Directory.Exists(failed) && record.Status is "prepared" or "backingUp" or "recoveryRequested")
            {
                SetState(directory, record, "cancelled", checkpoint);
                return new("cancelled", "La préparation a été annulée avant tout remplacement. Le programme et la configuration sont conservés.");
            }
        }
        else
        {
            SetState(directory, record, "rollingBack", checkpoint);
            if (Directory.Exists(record.Installation) && Directory.Exists(failed))
                throw new PestoException("update.recovery", "Un candidat conservé existe déjà. La reprise s’arrête sans écraser de dossier.");
            // The latest local default configuration, or its deliberate deletion, survives the return to the old files. It is
            // carried while the candidate is still in place: a refusal here leaves a startable installation and a resumable return.
            _ = InstallationDefaults.TryReadMarker(directory, out _, out var stagedDefault);
            InstallationDefaults.PreserveLatestForRollback(Directory.Exists(record.Installation) ? record.Installation : failed, backup, directory, stagedDefault);
            checkpoint?.Invoke("defaultsPreserved");
            if (Directory.Exists(record.Installation))
            {
                Directory.Move(record.Installation, failed);
                checkpoint?.Invoke("failedCandidateMoved");
            }
            Directory.Move(backup, record.Installation);
            checkpoint?.Invoke("backupRestored");
            SetState(directory, record, "restored", checkpoint);
        }
        if (!await CheckHealthAsync(directory, record, true, healthCheck, cancellationToken).ConfigureAwait(false))
        {
            SetState(directory, record, "rollbackHealthFailed", checkpoint);
            return new("rollbackHealthFailed", "Les anciens fichiers sont rétablis, mais leur démarrage n’est pas confirmé. Aucun succès n’est annoncé ; la configuration est conservée.");
        }
        SetState(directory, record, "rolledBack", checkpoint);
        return new("rolledBack", "Les anciens fichiers ont été rétablis et leur contrôle de santé a réussi. Aucun paramètre utilisateur n’a été remplacé.");
    }

    private static async Task<bool> CheckHealthAsync(string directory, TransactionRecord record, bool old,
        Func<string, string, string, CancellationToken, Task<bool>> healthCheck, CancellationToken cancellationToken)
    {
        var path = Path.Combine(directory, "health.json");
        // Complete an interrupted attempt before its shared health.json can be replaced by another probe.
        foreach (var pending in ReadHealthAttempts(directory, record).Where(p => p["status"]!.GetValue<string>() == "started"))
        {
            var previousNonce = pending["nonce"]!.GetValue<string>();
            CompleteHealthAttempt(directory, pending, "interrupted", null, false, "health.interrupted", CaptureHealthProof(path, previousNonce));
        }
        var nonce = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32));
        if (File.Exists(path)) File.Delete(path);
        var attempt = new JsonObject
        {
            ["schemaVersion"] = 1, ["transactionId"] = record.Id, ["nonce"] = nonce,
            ["target"] = old ? "rollback" : "candidate",
            ["expectedVersion"] = old ? record.CurrentVersion : record.NextVersion,
            ["expectedExecutableSha256"] = old ? record.CurrentExecutableHash : record.NextExecutableHash,
            ["status"] = "started", ["startedUtc"] = DateTimeOffset.UtcNow.ToString("O"),
            ["finishedUtc"] = null, ["reportedSuccess"] = null, ["accepted"] = null, ["failureCode"] = null, ["proof"] = null
        };
        SaveHealthAttempt(directory, attempt); // Flush the intent before the native process is started.
        bool reported;
        try { reported = await healthCheck(record.Installation, path, nonce, cancellationToken).ConfigureAwait(false); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException or OperationCanceledException or System.ComponentModel.Win32Exception)
        {
            CompleteHealthAttempt(directory, attempt, "failed", null, false,
                error is OperationCanceledException ? "health.cancelled" : "health.callback", CaptureHealthProof(path));
            return false;
        }
        if (!reported || !File.Exists(path) || new FileInfo(path).Length > 16384)
        {
            CompleteHealthAttempt(directory, attempt, "failed", reported, false, "health.unconfirmed", CaptureHealthProof(path));
            return false;
        }
        UpdatePackage.RequireNoLinks(path);
        bool accepted;
        JsonObject? captured = null;
        try
        {
            using var proof = UpdatePackage.ReadJson(path);
            var p = proof.RootElement;
            // Keep the existing acceptance contract: recording evidence must not relax or extend it.
            accepted = p.GetProperty("schemaVersion").GetInt32() == 1 && UpdatePackage.Text(p, "nonce") == nonce
                && UpdatePackage.Text(p, "transactionId") == record.Id
                && UpdatePackage.Text(p, "version") == (old ? record.CurrentVersion : record.NextVersion)
                && UpdatePackage.Text(p, "executableSha256") == (old ? record.CurrentExecutableHash : record.NextExecutableHash)
                && p.GetProperty("webViewReady").GetBoolean() && p.GetProperty("success").GetBoolean();
            captured = ProjectHealthProof(p);
        }
        catch (Exception error) when (error is JsonException or KeyNotFoundException or InvalidOperationException or PestoException) { accepted = false; }
        // A receipt write failure must propagate, never be swallowed as a successfully stored health result.
        CompleteHealthAttempt(directory, attempt, accepted ? "passed" : "failed", reported, accepted,
            accepted ? null : "health.proof", captured);
        return accepted;
    }

    private static readonly string[] HealthAttemptFields = ["schemaVersion", "transactionId", "nonce", "target", "expectedVersion",
        "expectedExecutableSha256", "status", "startedUtc", "finishedUtc", "reportedSuccess", "accepted", "failureCode", "proof"];
    private static readonly string[] HealthProofFields = ["schemaVersion", "transactionId", "nonce", "version", "executableSha256",
        "webViewReady", "success", "closeReturned", "failureCode"];

    private static IReadOnlyList<JsonObject> ReadHealthAttempts(string directory, TransactionRecord record)
    {
        var root = Path.Combine(directory, "health-attempts");
        UpdatePackage.RequireNoLinks(root);
        if (File.Exists(root)) InvalidHealthReceipt();
        if (!Directory.Exists(root)) return [];
        var attempts = new List<JsonObject>();
        var count = 0;
        foreach (var file in Directory.EnumerateFileSystemEntries(root))
        {
            if (++count > 256) InvalidHealthReceipt();
            UpdatePackage.RequireNoLinks(file);
            var name = Path.GetFileName(file);
            // An interrupted atomic write can leave its own unfinished temporary. Preserve it without
            // treating partial JSON as a completed receipt or deleting evidence of the interruption.
            if (Regex.IsMatch(name, "^[0-9a-f]{64}\\.json\\.[0-9a-f]{32}\\.tmp$") && File.Exists(file)) continue;
            if (!Regex.IsMatch(name, "^[0-9a-f]{64}\\.json$") || !File.Exists(file) || new FileInfo(file).Length > 32768)
                InvalidHealthReceipt();
            using var document = UpdatePackage.ReadJson(file);
            ValidateHealthAttempt(document.RootElement, record, name[..64]);
            attempts.Add(JsonNode.Parse(document.RootElement.GetRawText())!.AsObject());
        }
        return attempts.OrderBy(a => a["startedUtc"]!.GetValue<string>(), StringComparer.Ordinal)
            .ThenBy(a => a["nonce"]!.GetValue<string>(), StringComparer.Ordinal).ToArray();
    }

    private static void ValidateHealthAttempt(JsonElement value, TransactionRecord record, string nonce)
    {
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Count() != HealthAttemptFields.Length
            || value.EnumerateObject().Any(p => !HealthAttemptFields.Contains(p.Name))
            || !value.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number
            || !schema.TryGetInt32(out var version) || version != 1) InvalidHealthReceipt();
        var target = ReceiptText(value, "target");
        var status = ReceiptText(value, "status");
        if (!DateTimeOffset.TryParse(ReceiptText(value, "startedUtc"), out var started) || started == default) InvalidHealthReceipt();
        if (ReceiptText(value, "transactionId") != record.Id || ReceiptText(value, "nonce") != nonce
            || target is not ("candidate" or "rollback") || status is not ("started" or "passed" or "failed" or "interrupted")
            || ReceiptText(value, "expectedVersion") != (target == "candidate" ? record.NextVersion : record.CurrentVersion)
            || ReceiptText(value, "expectedExecutableSha256") != (target == "candidate" ? record.NextExecutableHash : record.CurrentExecutableHash))
            InvalidHealthReceipt();
        var finished = value.GetProperty("finishedUtc");
        var reported = value.GetProperty("reportedSuccess");
        var accepted = value.GetProperty("accepted");
        var failure = value.GetProperty("failureCode");
        var proof = value.GetProperty("proof");
        if (reported.ValueKind is not (JsonValueKind.True or JsonValueKind.False or JsonValueKind.Null)
            || accepted.ValueKind is not (JsonValueKind.True or JsonValueKind.False or JsonValueKind.Null)
            || failure.ValueKind is not (JsonValueKind.String or JsonValueKind.Null)
            || failure.ValueKind == JsonValueKind.String && (failure.GetString()!.Length is < 1 or > 256)
            || proof.ValueKind is not (JsonValueKind.Object or JsonValueKind.Null)) InvalidHealthReceipt();
        if (proof.ValueKind == JsonValueKind.Object) ValidateHealthProof(proof);
        if (status == "started")
        {
            if (new[] { finished, reported, accepted, failure, proof }.Any(p => p.ValueKind != JsonValueKind.Null)) InvalidHealthReceipt();
            return;
        }
        if (finished.ValueKind != JsonValueKind.String || !DateTimeOffset.TryParse(finished.GetString(), out var ended)
            || ended == default || ended < started || accepted.ValueKind == JsonValueKind.Null) InvalidHealthReceipt();
        if (status == "passed")
        {
            if (reported.ValueKind != JsonValueKind.True || accepted.ValueKind != JsonValueKind.True || failure.ValueKind != JsonValueKind.Null
                || proof.ValueKind != JsonValueKind.Object || ReceiptText(proof, "transactionId") != record.Id || ReceiptText(proof, "nonce") != nonce
                || ReceiptText(proof, "version") != ReceiptText(value, "expectedVersion")
                || ReceiptText(proof, "executableSha256") != ReceiptText(value, "expectedExecutableSha256")
                || !proof.GetProperty("webViewReady").GetBoolean() || !proof.GetProperty("success").GetBoolean()) InvalidHealthReceipt();
        }
        else if (accepted.ValueKind != JsonValueKind.False || failure.ValueKind != JsonValueKind.String
            || status == "interrupted" && reported.ValueKind != JsonValueKind.Null) InvalidHealthReceipt();
    }

    private static void ValidateHealthProof(JsonElement proof)
    {
        if (proof.ValueKind != JsonValueKind.Object || proof.EnumerateObject().Any(p => !HealthProofFields.Contains(p.Name))
            || !proof.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number
            || !schema.TryGetInt32(out var version) || version != 1) InvalidHealthReceipt();
        foreach (var field in new[] { "transactionId", "nonce", "version", "executableSha256" }) _ = ReceiptText(proof, field);
        foreach (var field in new[] { "webViewReady", "success" })
            if (!proof.TryGetProperty(field, out var value) || value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) InvalidHealthReceipt();
        if (proof.TryGetProperty("closeReturned", out var closed) && closed.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) InvalidHealthReceipt();
        if (proof.TryGetProperty("failureCode", out var failure) && (failure.ValueKind is not (JsonValueKind.Null or JsonValueKind.String)
            || failure.ValueKind == JsonValueKind.String && failure.GetString()!.Length > 256)) InvalidHealthReceipt();
    }

    private static string ReceiptText(JsonElement value, string name)
    {
        if (!value.TryGetProperty(name, out var field) || field.ValueKind != JsonValueKind.String || field.GetString()!.Length is < 1 or > 4096)
            InvalidHealthReceipt();
        return field.GetString()!;
    }

    private static JsonObject? CaptureHealthProof(string path, string? matchingNonce = null)
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > 16384) return null;
            using var document = UpdatePackage.ReadJson(path);
            var proof = ProjectHealthProof(document.RootElement);
            return proof is not null && (matchingNonce is null || proof["nonce"]!.GetValue<string>() == matchingNonce) ? proof : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or KeyNotFoundException or InvalidOperationException or PestoException)
        { return null; }
    }

    private static JsonObject? ProjectHealthProof(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) return null;
        var projection = new JsonObject();
        foreach (var field in HealthProofFields)
        {
            if (!value.TryGetProperty(field, out var item)) continue;
            // Optional diagnostic fields never alter the original acceptance contract.
            if (field == "closeReturned" && item.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) continue;
            if (field == "failureCode" && (item.ValueKind is not (JsonValueKind.Null or JsonValueKind.String)
                || item.ValueKind == JsonValueKind.String && item.GetString()!.Length > 256)) continue;
            projection[field] = JsonNode.Parse(item.GetRawText());
        }
        try
        {
            using var document = JsonDocument.Parse(projection.ToJsonString());
            ValidateHealthProof(document.RootElement);
            return projection;
        }
        catch (PestoException) { return null; }
    }

    private static void CompleteHealthAttempt(string directory, JsonObject attempt, string status, bool? reported, bool accepted,
        string? failureCode, JsonObject? proof)
    {
        attempt["status"] = status; attempt["finishedUtc"] = DateTimeOffset.UtcNow.ToString("O");
        attempt["reportedSuccess"] = reported; attempt["accepted"] = accepted; attempt["failureCode"] = failureCode; attempt["proof"] = proof;
        SaveHealthAttempt(directory, attempt);
    }

    private static void SaveHealthAttempt(string directory, JsonObject attempt)
    {
        var nonce = attempt["nonce"]!.GetValue<string>();
        if (!Regex.IsMatch(nonce, "^[0-9a-f]{64}$")) InvalidHealthReceipt();
        UpdatePackage.WriteJson(Path.Combine(directory, "health-attempts", nonce + ".json"), attempt);
    }

    private static void InvalidHealthReceipt() => throw new PestoException("update.healthReceipt", "Un reçu durable de contrôle de santé est invalide. Aucune preuve de succès n’est admise.");

    private static void ValidateTrees(string directory, TransactionRecord record)
    {
        foreach (var (name, expected) in new[] { ("stage", record.NextFingerprint), ("backup", record.CurrentFingerprint), ("failed-candidate", record.NextFingerprint) })
        {
            var path = Path.Combine(directory, name);
            if (Directory.Exists(path) && UpdatePackage.Validate(path, record.Channel).Fingerprint != expected)
                throw new PestoException("update.changed", "Un dossier de la transaction a été modifié. Aucun remplacement n’est autorisé.");
        }
        if (Directory.Exists(record.Installation))
        {
            var actual = UpdatePackage.Validate(record.Installation, record.Channel).Fingerprint;
            if (actual != record.CurrentFingerprint && actual != record.NextFingerprint)
                throw new PestoException("update.changed", "L’installation a été modifiée par une autre opération. La transaction s’arrête sans écraser ces changements.");
        }
    }

    private static async Task WaitParentAsync(TransactionRecord record, CancellationToken cancellationToken)
    {
        if (record.ParentProcessId == Environment.ProcessId) throw new PestoException("update.helper", "Le remplacement doit être exécuté par la copie isolée après fermeture de l’application.");
        Process? parent;
        try { parent = Process.GetProcessById(record.ParentProcessId); }
        catch (ArgumentException) { return; }
        using (parent)
        {
            try { if (parent.StartTime.ToUniversalTime() != record.ParentStartUtc.UtcDateTime) return; }
            catch (InvalidOperationException) { return; }
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(90));
            try { await parent.WaitForExitAsync(timeout.Token).ConfigureAwait(false); }
            catch (OperationCanceledException) { throw new PestoException("update.parent", "L’application initiale ne s’est pas fermée à temps. Aucun fichier n’a été remplacé."); }
        }
    }

    private static TransactionRecord Read(string directory)
    {
        directory = Path.GetFullPath(directory);
        UpdatePackage.RequireNoLinks(directory);
        var file = Path.Combine(directory, "transaction.json");
        if (!File.Exists(file) || new FileInfo(file).Length > 32768) throw new PestoException("update.journal", "Le journal de mise à jour est absent ou invalide.");
        using var doc = UpdatePackage.ReadJson(file);
        Arguments.Only(doc.RootElement, "schemaVersion", "id", "installation", "channel", "currentFingerprint", "nextFingerprint",
            "currentExecutableHash", "nextExecutableHash", "helperHash", "currentVersion", "nextVersion", "action", "status",
            "createdUtc", "parentProcessId", "parentStartUtc", "failure");
        var record = doc.RootElement.Deserialize<TransactionRecord>(JsonOptions) ?? throw new PestoException("update.journal", "Journal de mise à jour illisible.");
        if (record.SchemaVersion != 1 || !Regex.IsMatch(record.Id, "^[0-9a-f]{32}$") || !States.Contains(record.Status)
            || record.Action is not ("install" or "rollback" or "recover") || record.Channel is not ("DEV" or "PROD")
            || record.ParentProcessId < 1 || record.CreatedUtc == default || record.ParentStartUtc == default
            || !Version.TryParse(record.CurrentVersion, out var old) || old.Major != 2
            || !Version.TryParse(record.NextVersion, out var next) || next.Major != 2
            || new[] { record.CurrentFingerprint, record.NextFingerprint, record.HelperHash, record.CurrentExecutableHash, record.NextExecutableHash }.Any(h => !Regex.IsMatch(h, "^[0-9a-f]{64}$"))
            || !string.Equals(directory, Path.Combine(TransactionRoot(record.Installation), record.Id), StringComparison.OrdinalIgnoreCase))
            throw new PestoException("update.journal", "Le journal n’est pas lié à cette installation. Aucun dossier n’est modifié.");
        var helper = Path.Combine(directory, "helper", "Pesto.exe");
        if (!File.Exists(helper) || UpdatePackage.Hash(helper) != record.HelperHash)
            throw new PestoException("update.helper", "La copie du programme de mise à jour a changé.");
        return record;
    }

    private static string NormalizeInstallation(string installation)
    {
        var full = Path.GetFullPath(installation).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (string.IsNullOrEmpty(Path.GetFileName(full)) || Path.GetDirectoryName(full) is null || full == Path.GetPathRoot(full)?.TrimEnd(Path.DirectorySeparatorChar))
            throw new PestoException("update.installation", "Une racine de volume ne peut pas être une installation Pesto.");
        UpdatePackage.RequireNoLinks(full);
        return full;
    }

    private static string TransactionRoot(string installation)
    {
        installation = NormalizeInstallation(installation);
        var key = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(installation.ToUpperInvariant())))[..16];
        return Path.Combine(Path.GetDirectoryName(installation)!, ".pesto-v2-update-" + key);
    }

    private static FileStream Lock(string root)
    {
        UpdatePackage.RequireNoLinks(root);
        Directory.CreateDirectory(root);
        try { return new FileStream(Path.Combine(root, "transaction.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException) { throw new PestoException("update.busy", "Une autre instance traite déjà une mise à jour de cette installation."); }
    }

    private static void SetState(string directory, TransactionRecord record, string state, Action<string>? checkpoint)
    {
        record.Status = state; Save(directory, record); checkpoint?.Invoke(state);
    }
    private static void Save(string directory, TransactionRecord record) => UpdatePackage.WriteJson(Path.Combine(directory, "transaction.json"), record);

    private sealed class TransactionRecord
    {
        public int SchemaVersion { get; set; } = 1;
        public string Id { get; set; } = "";
        public string Installation { get; set; } = "";
        public string Channel { get; set; } = "";
        public string CurrentFingerprint { get; set; } = "";
        public string NextFingerprint { get; set; } = "";
        public string CurrentExecutableHash { get; set; } = "";
        public string NextExecutableHash { get; set; } = "";
        public string HelperHash { get; set; } = "";
        public string CurrentVersion { get; set; } = "";
        public string NextVersion { get; set; } = "";
        public string Action { get; set; } = "";
        public string Status { get; set; } = "";
        public DateTimeOffset CreatedUtc { get; set; }
        public int ParentProcessId { get; set; }
        public DateTimeOffset ParentStartUtc { get; set; }
        public string? Failure { get; set; }
    }
}

/// <summary>Only the portable crash harness injects an uncatchable power-loss boundary.</summary>
internal sealed class UpdateInterruptionException : Exception;
