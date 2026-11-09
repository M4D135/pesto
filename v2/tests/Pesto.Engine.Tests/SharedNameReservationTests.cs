using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class SharedNameReservationTests
{
    private sealed class Access : ISharedCoordinationAccess
    {
        public int Calls;
        public bool Forbidden;
        public T Run<T>(Func<T> operation) { Calls++; if (Forbidden) throw new InvalidOperationException("unexpected shared IO"); return operation(); }
    }

    /// <summary>Portable local fixture only. Windows runs the actual handle-based editor/deleter on a temporary folder;
    /// the Linux branch does not claim to qualify SMB or Windows impersonation.</summary>
    private sealed class Files : ISharedNameReservationFiles, ISharedCoordinationDeletion
    {
        public int Creates, Rewrites, Deletes;
        public Action<string, byte[]>? BeforeWrite;
        public Action<string, byte[]>? AfterCreate;
        public SharedNameReservationCreation CreateNew(string path, byte[] bytes)
        {
            Creates++;
            BeforeWrite?.Invoke(path, bytes);
            SharedNameReservationCreation result;
            if (OperatingSystem.IsWindows()) result = new WindowsNameReservationFiles().CreateNew(path, bytes);
            else
            {
                FileStream stream;
                try { stream = new(path, FileMode.CreateNew, FileAccess.Write, FileShare.None); }
                catch (IOException) when (File.Exists(path)) { return SharedNameReservationCreation.AlreadyExists; }
                using (stream) { stream.Write(bytes); stream.Flush(true); }
                result = SharedNameReservationCreation.Created;
            }
            if (result == SharedNameReservationCreation.Created) AfterCreate?.Invoke(path, bytes);
            return result;
        }
        public void RewriteExisting(string path, byte[] replacement, Func<byte[], bool> mayReplace)
        {
            Rewrites++;
            BeforeWrite?.Invoke(path, replacement);
            if (OperatingSystem.IsWindows()) { new WindowsNameReservationFiles().RewriteExisting(path, replacement, mayReplace); return; }
            FileStream stream;
            try { stream = new(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) { throw new PestoException("names.reservation_held", "exclusive fixture collision"); }
            using (stream)
            {
                if (stream.Length is < 1 or > SharedNameReservationProtocol.MaximumLeaseBytes) throw new PestoException("names.reservation_held", "invalid fixture file");
                var current = new byte[(int)stream.Length]; stream.ReadExactly(current);
                if (!mayReplace(current)) throw new PestoException("names.reservation_held", "foreign or changed lease");
                stream.Position = 0; stream.Write(replacement); stream.SetLength(replacement.Length); stream.Flush(true);
            }
        }
        public CoordinationDeletionResult DeleteExact(string path, string expectedSha256, int maximumBytes)
        {
            Deletes++;
            if (OperatingSystem.IsWindows()) return new WindowsCoordinationDeletion().DeleteExact(path, expectedSha256, maximumBytes);
            if (!File.Exists(path)) return CoordinationDeletionResult.Missing;
            if (SharedCoordinationProtocol.Hash(SharedCoordinationProtocol.ReadBounded(path, maximumBytes)) != expectedSha256) return CoordinationDeletionResult.Changed;
            File.Delete(path); return CoordinationDeletionResult.Deleted;
        }
    }

    private sealed class Fixture
    {
        public readonly string Root = Path.Combine(Path.GetTempPath(), "pesto-name-registry-" + Guid.NewGuid().ToString("N"));
        public readonly string Journal = Path.Combine(Path.GetTempPath(), "pesto-name-intents-" + Guid.NewGuid().ToString("N"));
        public readonly string Owner = Guid.NewGuid().ToString("N");
        public readonly FixedClock Clock = new();
        public readonly Files Files = new();
        public readonly Access Access = new();
        public readonly string Configuration;
        public readonly SharedNameReservationService Service;
        public string Stamp => SharedCoordinationProtocol.Hash(File.ReadAllBytes(Configuration));
        public Fixture()
        {
            Directory.CreateDirectory(Path.Combine(Root, "locks")); Directory.CreateDirectory(Path.Combine(Root, "reservations"));
            File.WriteAllText(Path.Combine(Root, "pesto-coordination.json"), "{\"Schema\":1,\"Domain\":\"example.local\",\"Purpose\":\"PestoCoordination\"}");
            var config = JsonNode.Parse(LiveTestConfig.Valid)!;
            config["POLICY"]!["CoordinationRoot"] = Root; config["POLICY"]!["CoordinationRequired"] = true;
            config["POLICY"]!["NameReservationMinutes"] = 15;
            Configuration = Path.Combine(LiveTestConfig.Write(config.ToJsonString()), "cfg.json");
            Service = NewService();
        }
        public SharedNameReservationService NewService(string? owner = null, string? journal = null) => new(Configuration,
            journal ?? Journal, SharedCoordinationAccessMode.Live, Files, Files, Access, Clock, sessionOwner: owner ?? Owner, station: "PC-TECH", user: "operator");
        public SharedNameReservationProof Reserve(string name = "PC-NEW", string preview = "preview-1") => Service.ReservePreviewName("example.local", name, preview, Stamp)!;
        public string PathFor(string name) => Path.Combine(Root, "reservations", name + ".json");
        public void Foreign(string name, int ageMinutes = 0, string? owner = null)
        {
            var config = SharedNameReservationConfiguration.ReadBytes(File.ReadAllBytes(Configuration)) with { Minutes = 5 };
            var intent = SharedNameReservationProtocol.CreateIntent(config, name, "foreign-preview", owner ?? Guid.NewGuid().ToString("N"),
                "OTHER-PC", "another-operator", Clock.GetUtcNow().AddMinutes(-ageMinutes));
            File.WriteAllText(PathFor(name), intent.Content);
        }
    }

    [Test]
    public void PreviewWritesItsImmutableIntentBeforeTheFirstSharedByteAndConfirmsExactV1Evidence()
    {
        var f = new Fixture();
        f.Files.BeforeWrite = (_, replacement) =>
        {
            var intents = Directory.GetFiles(f.Journal, "*.intent.json");
            Check.Equal(1, intents.Length, "pending local intent exists before first share write");
            var saved = JsonSerializer.Deserialize<SharedNameReservationIntent>(File.ReadAllBytes(intents[0]))!;
            Check.Equal(SharedCoordinationProtocol.Hash(replacement), saved.Proof.LeaseSha256, "intent binds exact planned bytes");
            Check.Equal(0, Directory.GetFiles(f.Journal, "*.confirmed.json").Length, "cannot announce confirmation before shared success");
        };
        var proof = f.Reserve();
        Check.Equal(f.Owner, proof.Owner, "session GUID owner, separate from mutation receipt owner");
        Check.Equal(f.Clock.GetUtcNow().AddMinutes(15), proof.ExpiresAt, "effective V1 policy duration");
        Check.Equal(1, Directory.GetFiles(f.Journal, "*.confirmed.json").Length, "durable confirmation after exact reread");
        using var lease = JsonDocument.Parse(File.ReadAllBytes(f.PathFor("PC-NEW")));
        Check.Equal("preview-1", lease.RootElement.GetProperty("Context").GetString(), "V1-compatible context");
        Check.Equal("PC-TECH", lease.RootElement.GetProperty("Station").GetString(), "V1-compatible station");
        f.Service.VerifyPreviewName(proof, f.Stamp);
        Check.Equal(0, Directory.GetFiles(Path.Combine(f.Root, "locks")).Length, "preview creates no mutation lock or AD account");
    }

    [Test]
    public void ActiveOtherOwnersAndEveryUnreadableCandidateAreExcludedWithoutAnyWrite()
    {
        var f = new Fixture(); f.Foreign("PC-ACTIVE"); f.Foreign("PC-EXPIRED", ageMinutes: 20); f.Foreign("PC-OWN", owner: f.Owner);
        File.WriteAllText(f.PathFor("PC-UNKNOWN"), "{interrupted");
        File.SetLastWriteTimeUtc(f.PathFor("PC-UNKNOWN"), new DateTime(2000, 1, 1));
        var before = Directory.GetFiles(Path.Combine(f.Root, "reservations")).ToDictionary(p => p, File.ReadAllText);
        var names = f.Service.OtherReservedNames("example.local");
        Check.True(names.Contains("PC-ACTIVE") && names.Contains("PC-UNKNOWN"), "active foreign and unknown evidence excluded");
        Check.False(names.Contains("PC-EXPIRED") || names.Contains("PC-OWN"), "known expired/own evidence is not a foreign lease");
        Check.Equal(0, f.Files.Creates + f.Files.Rewrites + f.Files.Deletes, "snapshot is read only");
        foreach (var pair in before) Check.Equal(pair.Value, File.ReadAllText(pair.Key), "all foreign bytes preserved");
        Check.Pesto(() => f.Reserve("PC-UNKNOWN"), "names.reservation_held", "old malformed lease never expires from a guessed mtime");
    }

    [Test]
    public void OwnRenewalBindsPreviousBytesAndInvalidatesTheOldPreviewWithoutChangingTheName()
    {
        var f = new Fixture(); var first = f.Reserve(); f.Clock.Advance(TimeSpan.FromMinutes(1));
        var renewed = f.Reserve(preview: "preview-2");
        Check.Equal(first.Name, renewed.Name, "renewal never chooses another name");
        Check.Equal(first.Owner, renewed.Owner, "same session owner");
        Check.True(first.IntentId != renewed.IntentId && first.LeaseSha256 != renewed.LeaseSha256, "renewal has a fresh durable intent and exact bytes");
        Check.Pesto(() => { f.Service.VerifyPreviewName(first, f.Stamp); return null; }, "names.reservation_changed", "old confirmation no longer authorizes send");
        Check.Pesto(() => { f.Service.ReleasePreviewName(first); return null; }, "names.reservation_changed", "old preview cannot delete a renewed lease");
        f.Service.VerifyPreviewName(renewed, f.Stamp);
        f.Service.ReleasePreviewName(renewed);
        Check.False(File.Exists(f.PathFor(renewed.Name)), "current exact owner removes its own lease");
    }

    [Test]
    public void ForeignActiveLeaseIsNeverOverwrittenButAnExpiredValidLeaseCanBeAcquiredExclusively()
    {
        var f = new Fixture(); f.Foreign("PC-NEW"); var old = File.ReadAllText(f.PathFor("PC-NEW"));
        Check.Pesto(() => f.Reserve(), "names.reservation_held", "active foreign owner blocks");
        Check.Equal(old, File.ReadAllText(f.PathFor("PC-NEW")), "foreign content preserved");
        f.Clock.Advance(TimeSpan.FromMinutes(6));
        var proof = f.Reserve(preview: "preview-after-expiry");
        Check.Equal(f.Owner, proof.Owner, "expired lease reclaimed only after exclusive read of a valid expiry");
        f.Service.VerifyPreviewName(proof, f.Stamp);
    }

    [Test]
    public void ConcurrentlyChangedBytesCannotBeRenewedVerifiedOrDeletedEvenWithTheSameOwner()
    {
        var f = new Fixture(); var proof = f.Reserve();
        var changed = File.ReadAllText(f.PathFor(proof.Name)) + " "; File.WriteAllText(f.PathFor(proof.Name), changed);
        Check.Pesto(() => { f.Service.VerifyPreviewName(proof, f.Stamp); return null; }, "names.reservation_changed", "verification binds bytes not just owner");
        Check.Pesto(() => f.Reserve(preview: "preview-after-edit"), "names.reservation_held", "own renewal requires exact previous bytes");
        Check.Pesto(() => { f.Service.ReleasePreviewName(proof); return null; }, "names.reservation_changed", "changed lease cannot be removed");
        Check.Equal(changed, File.ReadAllText(f.PathFor(proof.Name)), "concurrent bytes intact");
    }

    [Test]
    public void LostCreateResponseNeverBecomesASuccessfulRenewalOrAnIssuedPreview()
    {
        var f = new Fixture(); f.Files.AfterCreate = (_, _) => throw new IOException("simulated lost server reply after write");
        var failed = false;
        try { f.Reserve(); } catch (IOException) { failed = true; }
        Check.True(failed, "ambiguous write propagated");
        Check.Equal(0, f.Files.Rewrites, "no retry via renewal after an ambiguous create/write");
        Check.Equal(1, Directory.GetFiles(f.Journal, "*.intent.json").Length, "durable pending evidence preserved");
        Check.Equal(0, Directory.GetFiles(f.Journal, "*.confirmed.json").Length, "no false local success");
        Check.True(File.Exists(f.PathFor("PC-NEW")), "uncertain own lease kept, not erased or silently reissued");
        f.Files.AfterCreate = null;
        Check.Pesto(() => f.Reserve(preview: "preview-retry"), "names.reservation_held", "unknown same-owner bytes cannot be claimed without previous confirmed proof");
    }

    [Test]
    public void AnExpiredLeaseRequiresANewPreviewEvenWhenTheFileStillExists()
    {
        var f = new Fixture(); var proof = f.Reserve(); f.Clock.Advance(TimeSpan.FromMinutes(15));
        Check.Pesto(() => { f.Service.VerifyPreviewName(proof, f.Stamp); return null; }, "names.reservation_expired", "expiration is a hard send boundary");
        Check.True(File.Exists(f.PathFor(proof.Name)), "expiry does not silently delete evidence");
        var renewed = f.Reserve(preview: "preview-fresh");
        Check.True(renewed.ExpiresAt > proof.ExpiresAt, "new explicit preview supplies a new bounded lease");
    }

    [Test]
    public void ChangedConfigurationAndChangedLocalIntentFailBeforeAnyFurtherSharedIo()
    {
        var f = new Fixture(); f.Access.Forbidden = true;
        Check.Pesto(() => f.Service.ReservePreviewName("example.local", "PC-NEW", "preview-1", new string('0', 64)), "names.reservation_changed", "stale form stamp refuses before share");
        Check.Equal(0, f.Access.Calls, "no identity scope before matching config");
        Check.False(Directory.Exists(f.Journal), "no journal creation for stale plan");
        f.Access.Forbidden = false; var proof = f.Reserve();
        var calls = f.Access.Calls;
        File.AppendAllText(Path.Combine(f.Journal, proof.IntentId + ".intent.json"), " ");
        f.Access.Forbidden = true;
        Check.Pesto(() => { f.Service.VerifyPreviewName(proof, f.Stamp); return null; }, "names.reservation_changed", "changed local intent blocks before remote read");
        Check.Pesto(() => { f.Service.ReleasePreviewName(proof); return null; }, "names.reservation_changed", "changed local intent blocks before remote deletion");
        Check.Equal(calls, f.Access.Calls, "changed local evidence never reaches share");
    }

    [Test]
    public void MissingRegistryDirectoriesAreNeverCreatedByAPreview()
    {
        var f = new Fixture(); Directory.Delete(Path.Combine(f.Root, "reservations"));
        Check.Pesto(() => f.Reserve(), "coordination.unprepared", "explicit preparation required");
        Check.False(Directory.Exists(Path.Combine(f.Root, "reservations")), "acquisition cannot repair registry implicitly");
        Check.Equal(0, f.Files.Creates + f.Files.Rewrites, "no remote writes attempted");
    }

    [Test]
    public void IsolatedModesRefuseBeforeConfigurationJournalOrRemoteAccessEvenByDirectApi()
    {
        var proof = new SharedNameReservationProof(@"\\never-access.example.invalid\share\registry", "example.local", "PC-NEW", Guid.NewGuid().ToString("N"),
            "preview-1", new string('a', 64), new string('b', 64), DateTimeOffset.UtcNow.AddMinutes(15), "name-intent-" + Guid.NewGuid().ToString("N"));
        foreach (var mode in new[] { SharedCoordinationAccessMode.Demo, SharedCoordinationAccessMode.HealthCheck, SharedCoordinationAccessMode.BinaryRecovery })
        {
            var access = new Access { Forbidden = true }; var files = new Files();
            var service = new SharedNameReservationService(@"\\never-access.example.invalid\profile\cfg.json", @"\\never-access.example.invalid\journal", mode, files, files, access);
            Check.Pesto(() => service.OtherReservedNames("example.local"), "coordination.isolated", "snapshot isolated");
            Check.Pesto(() => service.ReservePreviewName("example.local", "PC-NEW", "preview-1", proof.ConfigSha256), "coordination.isolated", "reservation isolated");
            Check.Pesto(() => { service.VerifyPreviewName(proof, proof.ConfigSha256); return null; }, "coordination.isolated", "verification isolated");
            Check.Pesto(() => { service.ReleasePreviewName(proof); return null; }, "coordination.isolated", "cleanup isolated");
            Check.Pesto(() => { SharedNameReservationProtocol.Verify(proof, mode); return null; }, "coordination.isolated", "pure adapter direct verification isolated");
            Check.Pesto(() => { SharedNameReservationProtocol.Release(proof, mode, files); return null; }, "coordination.isolated", "pure adapter direct cleanup isolated");
            Check.Equal(0, access.Calls + files.Creates + files.Rewrites + files.Deletes, "no configuration/network/editor access");
        }
    }

    [Test]
    public void TwoConcurrentSessionsCannotBothAcquireTheSamePreviewName()
    {
        var f = new Fixture();
        var second = f.NewService(Guid.NewGuid().ToString("N"), f.Journal + "-second");
        var acquired = 0; var held = 0; var uncertain = 0;
        Parallel.Invoke(() => Attempt(f.Service), () => Attempt(second));
        Check.True(acquired <= 1, "at most one session can report the name acquired");
        Check.Equal(2, acquired + held + uncertain, "a competing exclusive verification may conservatively refuse; it never claims acquisition");
        Check.True(held >= 1, "foreign session denied without overwrite");
        void Attempt(SharedNameReservationService service)
        {
            try { service.ReservePreviewName("example.local", "PC-NEW", "preview-parallel", f.Stamp); Interlocked.Increment(ref acquired); }
            catch (PestoException error) when (error.Code == "names.reservation_held") { Interlocked.Increment(ref held); }
            catch (IOException) { Interlocked.Increment(ref uncertain); }
        }
    }
}
