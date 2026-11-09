using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>
/// Real adapter. It reports only facts it can actually observe: the local identity, the V1 configuration read from the
/// installation path passed in, and directory facts supplied by an injected read-only gateway. Every path whose reader
/// has not been qualified yet is refused with an actionable reason. It never invents a computer, a name, a site or a
/// success, and it never enables a write implicitly. The Windows/AD qualification of these paths is a separate delivery
/// gate (docs/PARITY.md).
/// </summary>
internal sealed partial class LiveBackend(string? v1InstallationPath, IDirectoryGateway? gateway, IMutationGateway? mutation, TimeProvider clock, string? gpRoot) : IPestoBackend
{
    private const int SearchHardLimit = 100;
    private const int InventoryHardLimit = 20000;
    private const int PreviewMinutes = 5;
    private const int PlanMinutes = 5;
    private static readonly string[] Kinds = ["join", "rename", "move", "renameMove"];
    private const string WriteUnavailable = "Les écritures réelles ne sont pas activées : mode lecture seule et adaptateur de mutation non qualifié.";
    private const string NamesUnavailable = "Aucun nom n’est proposé sans une lecture AD complète et récente de la portée : sans adaptateur annuaire actif, la disponibilité reste inconnue plutôt que simulée.";

    private readonly object gate = new();
    private readonly Random random = new();
    private long serial;
    private readonly Dictionary<string, LivePreview> previews = [];
    private readonly Dictionary<string, LivePreview> latestByKey = [];
    private readonly Dictionary<string, string> alternatives = [];
    private readonly Dictionary<string, LivePlan> plans = [];
    private readonly List<LiveQueueItem> queue = [];
    private readonly Dictionary<string, LiveBatch> batches = [];
    private int queueVersion;
    private readonly List<Receipt> receipts = [];
    private readonly List<LogEntry> logs = [];
    private bool configLoaded;
    private V1Config? config;
    private PestoException? configError;
    private string? configStamp;
    private NamingConvention? conventionCache;
    private V1Config? conventionCacheOwner;
    private string? discoveredDc;
    private bool dcDiscovered;
    /// <summary>Dossier GP de l'historique durable (Interventions V1 + reçus de l'adaptateur). Null = aucun emplacement connu sur ce poste.</summary>
    private readonly string? gpRoot = gpRoot ?? DefaultGpRoot();

    /// <summary>Emplacement durable V1 (%ProgramData%\GP) ; hors Windows, aucun équivalent n'est supposé : l'historique reste inconnu, jamais vide-par-défaut.</summary>
    private static string? DefaultGpRoot()
    {
        if (!OperatingSystem.IsWindows()) return null;
        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        return string.IsNullOrEmpty(programData) ? null : Path.Combine(programData, "GP");
    }

    public Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using var timing = DirectoryReadEvents.Log.Measure(operation, "backend.total");
        lock (gate)
        {
            timing.Mark("backend.gateWait");
            cancellationToken.ThrowIfCancellationRequested();
            if (discoveredDc is null) dcDiscovered = false; // Retry a failed discovery on the next request.
            // Imports/defaults may atomically replace this profile's configuration in another window.
            // Execute paths retain their original stamp and reject stale plans before sending anything.
            if (operation is not ("operation.execute" or "queue.execute" or "settings.save")) RefreshConfigurationIfChanged();
            object? result = operation switch
            {
                "session.info" => SessionInfo(),
                "dashboard.read" => Dashboard(!args.TryGetProperty("inventory", out _) || Arguments.Flag(args, "inventory")),
                "directory.sites" => DirectorySites(),
                "directory.services" => DirectoryServices(args),
                "directory.search" => DirectorySearch(args),
                "computer.inspect" => ComputerInspect(args),
                "names.preview" => NamesPreview(args),
                "join.precreated.preview" => JoinPrecreatedPreview(args),
                "operation.prepare" => OperationPrepare(args),
                "operation.execute" => OperationExecute(args),
                "queue.add" => QueueAdd(args),
                "queue.list" => QueueList(),
                "queue.remove" => QueueRemove(args),
                "queue.prepare" => QueuePrepare(args),
                "queue.execute" => QueueExecute(args, cancellationToken),
                "receipts.list" => ReceiptsList(args),
                "receipts.get" => ReceiptsGet(args),
                "receipts.reconcile" => ReceiptsReconcile(args),
                "receipts.prepareMove" => ReceiptsPrepareMove(args),
                "receipts.prepareAcknowledgement" => ReceiptsPrepareAcknowledgement(args),
                "receipts.acknowledge" => ReceiptsAcknowledge(args),
                "receipts.prepareRestart" => ReceiptsPrepareRestart(args),
                "receipts.restart" => ReceiptsRestart(args),
                "reservations.list" => ReservationsList(args),
                "reservations.inspect" => ReservationsInspect(args),
                "reservations.prepare" => ReservationsPrepare(args),
                "reservations.execute" => ReservationsExecute(args),
                "attributes.inspect" => AttributesInspect(args),
                "attributes.prepare" => AttributesPrepare(args),
                "attributes.apply" => AttributesApply(args),
                "attributes.observe" => AttributesObserve(args),
                "logs.list" => LogsList(args),
                "settings.get" => SettingsGet(),
                "settings.save" => SettingsSave(args),
                "diagnostics.read" => Diagnostics(),
                _ => throw new PestoException("operation.unknown", "Cette opération n’est pas déclarée dans le pont Pesto."),
            };
            return Task.FromResult<object?>(result);
        }
    }

    // ---- identity and dashboard ---------------------------------------------------

    private V1OperationPolicy Policy(V1Config read)
    {
        if (mutation is not IMutationManagedPolicy managed) return read.OperationPolicy;
        try { return read.OperationPolicy.WithManaged(managed.ReadManagedPolicy()); }
        catch (Exception) { return read.OperationPolicy with { VerificationFailure = "La politique administrée n’a pas pu être confirmée : aucune mutation." }; }
    }

    private int MaximumBatch(V1Config read) => Math.Min(read.MaxBatch, Policy(read).ManagedMaxBatch ?? read.MaxBatch);

    private bool WritesAvailable => mutation is not null && gateway is not null && ConfigOrNull() is not null
        && (mutation is not IMutationAvailability availability || availability.IsAvailable)
        && Policy(ConfigOrNull()!).BlockReason("queue") is null
        && CoordinationProviderRefusal(Policy(ConfigOrNull()!)) is null;

    private string? WriteBlockReason => mutation is null ? WriteUnavailable
        : gateway is null ? "Adaptateur annuaire absent : aucune écriture sans relecture."
        : ConfigOrNull() is null ? "Configuration V1 absente ou invalide : aucune écriture."
        : mutation is IMutationAvailability { IsAvailable: false } availability
            ? availability.UnavailableReason ?? "Adaptateur de mutation indisponible sur ce poste."
            : Policy(ConfigOrNull()!).BlockReason("queue") ?? CoordinationProviderRefusal(Policy(ConfigOrNull()!));

    private string? CapabilityBlockReason(string action) => action == "acknowledge" ? AcknowledgementCapabilityBlockReason()
        : action == "attributes" ? AttributesCapabilityBlockReason()
        : action == "joinPrecreated" ? PrecreatedJoinCapabilityBlockReason() : WriteBlockReason
        ?? (ConfigOrNull() is { } read ? Policy(read).BlockReason(action) : null)
        ?? (action == "join" && ConfigOrNull()?.OperationPolicy.ReserveNamesInAd == true && mutation is not IMutationJoinReservation
            ? "POLICY.ReserveNamesInAD : adaptateur de réservation AD absent, aucune jonction préparée sans ce parcours." : null);

    private JsonObject SessionInfo() => Resp.Obj(
        ("version", EngineVersion.Current),
        ("mode", "live"),
        ("domain", ConfigOrNull()?.Domain),
        ("dc", DcOrNull()),
        ("account", DirectoryAccount()),
        ("computer", Environment.MachineName),
        ("localJoined", gateway is ILocalDomainMembership membership ? membership.LocalComputerJoined : null),
        ("readOnly", !WritesAvailable),
        ("capabilities", Resp.Arr<string>(["join", "joinPrecreated", "rename", "move", "renameMove", "queue", "acknowledge", "attributes"],
            id => Resp.Obj(("id", id), ("enabled", CapabilityBlockReason(id) is null), ("reason", CapabilityBlockReason(id))))));

    /// <summary>
    /// Tableau de bord réel (constat 3 de la revue) : plus de null/listes constants. Les compteurs viennent de lectures
    /// réelles — inventaire borné de la racine gérée via l'adaptateur annuaire injecté, et registre durable GP relu sur
    /// disque (port de Get-PestoHomeReceiptSummary/Get-PestoInterventionCatalogue). Le null reste réservé à l'inconnu :
    /// lecture d'inventaire incomplète, registre durable indisponible, ou disponibilité de noms qui n'est jamais un fait
    /// global (elle ne se lit que par portée, dans names.preview). Sans adaptateur annuaire, le lecteur refuse avec une
    /// raison exploitable plutôt que de rendre un tableau vide.
    /// </summary>
    private JsonObject Dashboard(bool includeInventory)
    {
        var read = RequireConfig();
        var adapter = includeInventory ? RequireGateway() : null;
        var inventory = adapter?.ListComputerNames(read.Domain, DcOrNull(), read.RootOu, InventoryHardLimit);
        var convention = GetConvention(read);
        var history = GpHistory.Read(gpRoot);
        var merged = MergedReceipts(history);
        var bySite = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        if (inventory?.Complete == true)
            foreach (var name in inventory.Names)
            {
                var parts = convention.TryParse(name);
                if (parts is not null) bySite[parts.Site] = bySite.GetValueOrDefault(parts.Site) + 1;
            }
        return Resp.Obj(
            ("computers", inventory?.Complete == true ? inventory.Names.Count : (int?)null),
            ("availableNames", null), // disponibilité = fait par portée, lu par names.preview ; jamais un compteur global inventé
            ("pendingRestart", history.Available ? merged.Count(m => m.Receipt.Status == "pendingRestart" && !m.Acknowledged) : (int?)null),
            ("uncertain", history.Available ? merged.Count(m => m.Receipt.Status == "uncertain" && !m.Acknowledged) : (int?)null),
            ("lastActivity", Resp.Arr(merged.Take(5), m => ReceiptWithRestartInfo(m.Receipt, m.Acknowledged))),
            ("inventoryRead", includeInventory),
            ("sites", adapter is null ? new JsonArray() : Resp.Arr(ResolveSites(read, adapter), s => Resp.Obj(("name", s.Name), ("count", inventory?.Complete == true ? bySite.GetValueOrDefault(s.Code) : (int?)null)))),
            ("history", Resp.Obj(
                ("readable", history.Available),
                ("source", history.Available ? GpHistory.Source : null),
                ("reason", history.Available ? null : history.Reason),
                ("validCount", history.Available ? history.Entries.Count(e => e.Readable) : (int?)null),
                ("invalidCount", history.Available ? history.InvalidCount : (int?)null),
                ("truncated", history.Truncated))));
    }

    /// <summary>Fusion session + registre durable : même identifiant = même reçu (la version de la session, finalisée par
    /// relecture, fait foi) ; aucun autre rapprochement, aucune suppression, aucun fichier effacé. Tri du plus récent au plus ancien.</summary>
    private List<(Receipt Receipt, bool Acknowledged)> MergedReceipts(GpHistoryResult history)
    {
        var merged = new List<(Receipt Receipt, bool Acknowledged)>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var receipt in receipts)
            if (seen.Add(receipt.Id)) merged.Add((receipt, history.Entries.Any(e => e.Readable && e.Acknowledged && e.Receipt.Id == receipt.Id
                && SameAcknowledgementReceipt(ReceiptNode(receipt), ReceiptNode(e.Receipt)))));
        foreach (var entry in history.Entries)
            if (seen.Add(entry.Receipt.Id)) merged.Add((entry.Receipt, entry.Acknowledged));
        return [.. merged.OrderByDescending(m => m.Receipt.Time)];
    }

    private JsonObject SettingsGet()
    {
        var read = ConfigOrNull();
        if (read is null)
            return Resp.Obj(
                ("domain", null), ("dc", null), ("prefix", null), ("production", null),
                ("namingPattern", null), ("randomNames", false),
                ("sites", Resp.Arr()), ("simulation", false), ("liveExecutionEnabled", false));
        return Resp.Obj(
            ("domain", read.Domain), ("dc", DcOrNull()), ("prefix", read.Prefix), ("production", read.Production),
            ("namingPattern", read.NamingPattern), ("randomNames", read.RandomNames),
            ("sites", Resp.Arr(read.DeclaredSites, s => Resp.Obj(("id", s.Tag), ("name", s.Pattern), ("code", s.Tag), ("ou", null)))),
            ("simulation", false), ("liveExecutionEnabled", WritesAvailable));
    }

    // ---- enregistrement de la configuration réelle (modèle d'écriture V1 : Save-Cfg / Write-PestoAtomicText) --------

    /// <summary>
    /// Enregistrement réel du cfg.json de l'installation V1 passée en paramètre, selon le modèle V1 (Save-Cfg) :
    /// validation intégrale AVANT écriture, garde de concurrence sur l'empreinte du fichier (Assert-PestoConfigFileUnchanged),
    /// écriture atomique avec sauvegarde cfg.json.bak (Write-PestoAtomicText -Backup), relecture et revalidation après
    /// écriture avec rétablissement de l'ancienne version si la relecture échoue, puis activation de la convention lue
    /// (Set-PestoActiveNamingConvention) et invalidation des aperçus, plans et file (Invalidate-PestoConfigurationPlans).
    /// Seuls le motif de nommage (NamingConvention V1 : ordre des facettes, largeurs, types) et le tirage au hasard
    /// (POLICY.RandomNameEnabled) sont enregistrés ; domaine, préfixe, environnement et sites appartiennent à
    /// l'installation V1 et doivent revenir inchangés, sinon refus sans aucune écriture. Le contrôleur (dc) est
    /// informatif en mode réel (découvert), jamais enregistré.
    /// </summary>
    private JsonObject SettingsSave(JsonElement args)
    {
        Arguments.Only(args, "domain", "dc", "prefix", "production", "namingPattern", "randomNames", "sites", "simulation", "liveExecutionEnabled");
        if (args.TryGetProperty("simulation", out _) && Arguments.Flag(args, "simulation"))
            throw new PestoException("mode_fixed", "Le mode ne peut pas être modifié depuis les paramètres.");
        if (Arguments.Flag(args, "liveExecutionEnabled") && !WritesAvailable)
            throw new PestoException("live_execution_unavailable", "Les écritures réelles ne peuvent pas être activées par les paramètres.");

        var read = RequireConfig();
        var path = ConfigPathOf()
            ?? throw new PestoException("config.missing", "Aucun dossier d’installation V1 n’a été fourni : la configuration réelle ne peut être ni lue ni enregistrée.");
        // Share the same process lock as profile imports/defaults; API callers cannot race those transactions.
        using var configurationLock = ConfigurationStore.Lock(Path.GetDirectoryName(path)!);

        var domain = Arguments.Text(args, "domain", true, 253).ToLowerInvariant();
        var prefix = Arguments.Text(args, "prefix", true, 12).ToUpperInvariant();
        if (!domain.Equals(read.Domain, StringComparison.OrdinalIgnoreCase) || !prefix.Equals(read.Prefix, StringComparison.Ordinal))
            throw BusinessReadonly("domaine et préfixe");
        if (Arguments.Flag(args, "production") != read.Production) throw BusinessReadonly("environnement de production");
        RequireSitesUnchanged(args, read);

        var pattern = Arguments.Text(args, "namingPattern", true, 150);
        NamingConvention convention;
        try { convention = new NamingConvention(pattern, read.Prefix); }
        catch (PestoException error) { throw new PestoException("invalid_naming", "Convention refusée avant toute écriture : " + error.Message); }
        var randomNames = Arguments.Flag(args, "randomNames");

        string original;
        try { original = File.ReadAllText(path, Encoding.UTF8); }
        catch (IOException) { throw new PestoException("config.changed", "cfg.json illisible sur le disque : rechargez les paramètres. Aucun fichier remplacé."); }
        var info = new FileInfo(path);
        if ((info.Attributes & FileAttributes.ReparsePoint) != 0)
            throw new PestoException("config.invalid", "Le cfg.json fourni est un lien : seule une configuration ordinaire est écrite.");
        if (info.Length > V1Config.MaximumFileBytes)
            throw new PestoException("config.invalid", "Configuration trop volumineuse (plus de 1 Mio) : aucune écriture tentée.");

        JsonNode root;
        try { root = JsonNode.Parse(original) ?? throw new JsonException("racine vide"); }
        catch (JsonException) { throw new PestoException("config.invalid", "cfg.json illisible : aucune écriture n’a été tentée sur un fichier non analysable."); }
        var cfg = root.AsObject();

        string? existingId = null;
        if (cfg.TryGetPropertyValue("NamingConvention", out var existing) && existing is JsonObject existingObject
            && existingObject.TryGetPropertyValue("Id", out var idNode) && idNode?.GetValueKind() == JsonValueKind.String)
            existingId = idNode.GetValue<string>();
        if (convention.IsHistoricalDefault) cfg.Remove("NamingConvention"); // l'absence conserve le format historique (port v1) : rien d'inventé dans le fichier
        else cfg["NamingConvention"] = Resp.Obj(
            ("Schema", 1),
            ("Id", existingId is { Length: > 0 } known && Regex.IsMatch(known, "^[a-z0-9][a-z0-9._-]{0,31}$") ? known : "v2"),
            ("Tokens", Resp.Arr(convention.Tokens, t => (JsonNode?)Resp.Node(t))),
            ("Widths", Resp.Obj(("Prefix", convention.PrefixWidth), ("Site", convention.SiteWidth), ("Service", convention.ServiceWidth), ("Number", convention.NumberWidth))),
            ("Types", convention.Types));

        if (cfg.TryGetPropertyValue("POLICY", out var policyNode) && policyNode is JsonObject policy)
        {
            policy["RandomNameEnabled"] = randomNames;
            if (policy.ContainsKey("RandomNameChoice")) policy["RandomNameChoice"] = randomNames ? 2 : 1; // les deux clés ne doivent jamais se contredire (garde v1)
        }
        else if (!randomNames) cfg["POLICY"] = Resp.Obj(("Schema", 1), ("RandomNameEnabled", false));

        var candidateText = cfg.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        V1Config candidate;
        try { candidate = V1Config.ValidateText(candidateText); }
        catch (PestoException error)
        {
            throw new PestoException("config.invalid", "Convention refusée : incompatible avec les valeurs lues (préfixe, PreprodSite, TAGS, NameCatalogue, POLICY) — rien n’a été écrit. " + error.Message);
        }
        if (!string.Equals(candidate.NamingPattern, convention.ToPattern(), StringComparison.Ordinal) || !candidate.RandomNames.Equals(randomNames))
            throw new PestoException("config.invalid", "La configuration enregistrée ne rendrait pas la convention demandée : rien n’a été écrit.");

        // Garde de concurrence v1 : le fichier ne doit pas avoir changé en dehors de cette session (Assert-PestoConfigFileUnchanged).
        if (configStamp is null)
            throw new PestoException("config.changed", "Version du fichier non mémorisée : rechargez les paramètres avant de les enregistrer. Aucun fichier remplacé.");
        if (!File.Exists(path) || Stamp(path) != configStamp)
            throw new PestoException("config.changed", "cfg.json a été modifié en dehors de cette session : rechargez les paramètres puis recommencez. Aucun fichier remplacé.");

        WriteAtomic(path, candidateText, backup: true);
        V1Config reread;
        string rereadStamp;
        try { reread = V1Config.Load(v1InstallationPath, out rereadStamp); }
        catch (PestoException error)
        {
            WriteAtomic(path, original, backup: false); // l'ancienne version est rétablie ; la sauvegarde .bak reste conservée
            throw new PestoException("config.invalid", "Nouvelle configuration refusée à la relecture : l’ancienne a été rétablie. " + error.Message);
        }
        config = reread;
        configError = null;
        configStamp = rereadStamp;
        InvalidateDerivedState();
        Log($"cfg.json enregistré (sauvegarde cfg.json.bak conservée) : convention « {reread.Convention.Id} » ({reread.NamingPattern}), tirage au hasard {(reread.RandomNames ? "activé" : "désactivé")} ; aperçus, plans et file invalidés, tout écriture devra être re-préparée et re-confirmée.");
        return SettingsGet();
    }

    private static PestoException BusinessReadonly(string field) => new("config.business_readonly",
        $"Seuls le motif de nommage et le tirage au hasard des noms s’enregistrent depuis la v2 : « {field} » se gère dans l’installation V1 (cfg.json). Rechargez les paramètres avant d’enregistrer ; rien n’a été écrit.");

    /// <summary>Les sites rendus par settings.get viennent des TAGS/OUSite de l'installation V1 : ils doivent revenir inchangés (l'OU non observée arrive vide ou « null » depuis l'interface).</summary>
    private static void RequireSitesUnchanged(JsonElement args, V1Config read)
    {
        if (!args.TryGetProperty("sites", out var sites) || sites.ValueKind != JsonValueKind.Array || sites.GetArrayLength() != read.DeclaredSites.Count)
            throw BusinessReadonly("sites");
        var index = 0;
        foreach (var item in sites.EnumerateArray())
        {
            var declared = read.DeclaredSites[index++];
            if (item.ValueKind != JsonValueKind.Object) throw BusinessReadonly("sites");
            var id = Arguments.Text(item, "id", true, 80);
            var name = Arguments.Text(item, "name", true, 200);
            var code = Arguments.Text(item, "code", true, 8);
            var ou = Arguments.Text(item, "ou");
            var ouUnknown = ou.Length == 0 || ou.Equals("null", StringComparison.OrdinalIgnoreCase);
            if (!id.Equals(declared.Tag, StringComparison.OrdinalIgnoreCase) || !name.Equals(declared.Pattern, StringComparison.OrdinalIgnoreCase)
                || !code.Equals(declared.Tag, StringComparison.OrdinalIgnoreCase) || !ouUnknown)
                throw BusinessReadonly("sites");
        }
    }

    /// <summary>Port de Write-PestoAtomicText v1 : fichier temporaire dans le même dossier puis remplacement, avec sauvegarde .bak conservée.</summary>
    private static void WriteAtomic(string path, string text, bool backup)
    {
        var bytes = new UTF8Encoding(false).GetBytes(text);
        var tmp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(tmp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.Write(bytes);
                stream.Flush(flushToDisk: true);
            }
            if (File.Exists(path))
            {
                try { File.Replace(tmp, path, backup ? path + ".bak" : null); }
                catch (PlatformNotSupportedException)
                {
                    if (backup) File.Copy(path, path + ".bak", overwrite: true);
                    File.Move(tmp, path, overwrite: true);
                }
            }
            else File.Move(tmp, path);
        }
        finally
        {
            if (File.Exists(tmp)) try { File.Delete(tmp); } catch (IOException) { }
        }
    }

    /// <summary>Port d'Invalidate-PestoConfigurationPlans + Set-PestoActiveNamingConvention : après un changement de configuration,
    /// aucun aperçu, plan ou ligne de file fondé sur l'ancienne convention ne reste consommable.</summary>
    private void InvalidateDerivedState()
    {
        previews.Clear();
        latestByKey.Clear();
        alternatives.Clear();
        plans.Clear();
        queue.Clear();
        batches.Clear();
        queueVersion++;
    }

    private JsonObject Diagnostics()
    {
        var read = ConfigOrNull();
        var policy = read is null ? null : Policy(read);
        var dc = DcOrNull();
        var checks = new List<Check>
        {
            new("Identité locale", "ok", $"Poste {Environment.MachineName}, compte Windows du processus {ObservedAccount()}."),
            gateway is not null
                ? new("Compte annuaire", "ok", $"Compte sélectionné pour les appels annuaire : {DirectoryAccount()}. Cet affichage ne prouve ni une authentification réussie ni les droits AD.")
                : new("Compte annuaire", "unknown", "Aucun lecteur annuaire actif : aucun compte n’a encore été utilisé pour une lecture AD."),
            new("Mode", "ok", WritesAvailable ? "Annuaire réel : actions disponibles après préparation et confirmation." : "Annuaire réel : lecture seule, aucune écriture activée."),
            read is not null
                ? new("Configuration V1", "ok", $"cfg.json lu : domaine {read.Domain}, préfixe {read.Prefix}, {read.DeclaredSites.Count} sites déclarés, {read.OrganismOus.Count} organisme(s).")
                : new("Configuration V1", "unknown", configError?.Message ?? "Aucun dossier d’installation V1 fourni (--v1-root)."),
            read is not null
                ? new("Convention de nommage", "ok", $"Convention « {read.Convention.Id} » appliquée aux calculs et aux analyses : facettes {string.Join(',', read.Convention.Tokens)} ; largeurs préfixe {read.Convention.PrefixWidth}, site {read.Convention.SiteWidth}, service {read.Convention.ServiceWidth}, numéro {read.Convention.NumberWidth} ; types {read.Convention.Types} ; motif {read.NamingPattern}.")
                : new("Convention de nommage", "unknown", "Convention non lue : configuration V1 indisponible, aucun nom ne sera calculé."),
            gateway is not null
                ? new("Active Directory", "ok", $"Adaptateur transitoire : {gateway.Description}. Lectures bornées : recherche ≤ {SearchHardLimit}, inventaire ≤ {InventoryHardLimit}, tentatives {read?.ReadAttempts ?? 2}.")
                : new("Active Directory", "unknown", "Aucun adaptateur annuaire actif sur ce poste : les lectures AD sont refusées plutôt que simulées."),
            new("Contrôleur", dc is not null ? "ok" : "unknown",
                dc is not null ? $"Contrôleur découvert : {dc}." : "Aucun contrôleur découvert pour l’instant ; la découverte est bornée et ne modifie aucun service."),
            new("Écritures", WritesAvailable ? "ok" : "unknown", WriteBlockReason
                ?? $"Adaptateur de mutation disponible : {mutation!.Description}. Chaque exécution reste soumise aux contrôles et à la confirmation du plan ; la disponibilité ne constitue pas une preuve de qualification AD."),
            GpHistory.Read(gpRoot) is { } history
                ? history.Available
                    ? new("Historique durable", history.InvalidCount > 0 || history.Truncated ? "warn" : "ok",
                        $"Registre GP relu (lecture seule) : {history.Entries.Count(e => e.Readable)} reçu(s) lisible(s), {history.InvalidCount} fichier(s) illisible(s) isolé(s) sous leur nom, aucun verrou levé"
                        + (history.Truncated ? " ; liste tronquée à 5 000 fichiers par dossier (borne v1), les résultats ne sont pas exhaustifs" : "") + ".")
                    : new("Historique durable", "unknown", history.Reason ?? "Registre GP indisponible : les compteurs d’historique restent inconnus, jamais supposés vides.")
                : new("Historique durable", "unknown", "Registre GP indisponible : les compteurs d’historique restent inconnus, jamais supposés vides."),
            read is not null
                ? new("Jonction non accompagnée", read.UnattendedJoinEnabled ? "warn" : "ok",
                    read.UnattendedJoinEnabled
                        ? "UnattendedJoinEnabled lu true : cette autorisation d’automatisation ne désactive pas la jonction interactive, qui conserve aperçu et confirmation. Aucune action automatique au démarrage."
                        : "UnattendedJoinEnabled lu false : le moteur ne l’active jamais.")
                : new("Jonction non accompagnée", "unknown", "Valeur non lue : configuration V1 indisponible."),
            read is not null
                ? new("Politique des mutations", policy!.BlockReason("queue") is null ? "ok" : "warn",
                    policy!.BlockReason("queue") ?? "Exclusions des noms et OU, mode incident et scénario appliqués à la préparation, aux lots et avant chaque envoi. Restrictions HKLM relues par l’adaptateur lorsqu’il les expose.")
                : new("Politique des mutations", "unknown", "Politique non lue : aucune garantie supposée."),
            policy?.BlockReason("join") is { } joinPolicy
                ? new("Politique de jonction", "warn", joinPolicy)
                : new("Politique de jonction", read is null ? "unknown" : "ok", read is null ? "Configuration absente : politique non lue." : "Aucune politique de jonction obligatoire non raccordée n’est activée."),
            AuditDiagnostic(policy),
            ClockDiagnostic(policy),
            GroupDiagnostic(policy),
            CoordinationDiagnostic(policy),
            policy?.ReserveNamesInAd == true
                ? new("Réservation AD", mutation is IMutationJoinReservation ? "ok" : "warn", mutation is IMutationJoinReservation
                    ? "POLICY.ReserveNamesInAD activée : création après confirmation explicite, GUID et marqueur relus, reçus durables et reprise/retrait séparément confirmés. Ce raccordement n’est pas une qualification Windows/AD."
                    : "POLICY.ReserveNamesInAD activée, adaptateur absent : aucune jonction préparée.")
                : new("Réservation AD", policy is null ? "unknown" : "ok", policy is null ? "Politique non lue." : "POLICY.ReserveNamesInAD désactivée : aucun compte réservé par la préparation ou la jonction standard."),
        };
        return Resp.Obj(("mode", "live"), ("checks", Resp.Arr(checks, c => Resp.Obj(("label", c.Label), ("state", c.State), ("detail", c.Detail)))));
    }

    private Check AuditDiagnostic(V1OperationPolicy? policy)
    {
        if (policy is null) return new("Audit Windows", "unknown", "Configuration absente : politique d’audit non lue.");
        if (!policy.AuditEventLogEnabled) return new("Audit Windows", "ok", "Audit EventLog désactivé dans la configuration ; aucun événement demandé.");
        if (mutation is not IReceiptAuditDisclosure disclosure)
            return new("Audit Windows", "warn", "Audit EventLog demandé, mais aucun émetteur ne fournit d’état : aucune écriture d’audit confirmée.");
        var state = disclosure.AuditStatus;
        var detail = state.State switch
        {
            "confirmed" => "Dernière écriture d’audit confirmée après reçu durable à " + state.LastSuccessUtc?.ToString("O") + ".",
            "failed" => "Écriture d’audit non confirmée à " + state.LastFailureUtc?.ToString("O") + " (" + state.FailureCode + "). La source Application/Pesto doit être préprovisionnée par l’administrateur. Le résultat métier et son reçu restent inchangés.",
            _ => "Audit EventLog demandé ; aucune écriture d’audit n’a encore été confirmée. La source Application/Pesto doit être préprovisionnée par l’administrateur."
        };
        if (state.Failures > 0) detail += " Échecs observés dans cette session : " + state.Failures + ".";
        return new("Audit Windows", state.State == "confirmed" ? "ok" : "warn", detail);
    }

    // ---- directory reads (portable guards from v1 readers) -------------------------

    private JsonObject DirectorySites()
    {
        var read = RequireConfig();
        var adapter = RequireGateway();
        return Resp.Obj(("items", Resp.Arr(ResolveSites(read, adapter), s =>
            Resp.Obj(("id", s.Id), ("name", s.Name), ("code", s.Code), ("ou", s.Ou), ("selector", s.Ou)))));
    }

    private JsonObject DirectoryServices(JsonElement args)
    {
        var read = RequireConfig();
        var adapter = RequireGateway();
        var wanted = Arguments.Text(args, "site", true);
        var (resolved, selection) = SiteForInventory(read, adapter, wanted);

        var convention = GetConvention(read);
        var patterns = convention.Types.Select(type => convention.SitePattern(type.ToString(), resolved.Code)).ToArray();
        var names = selection is null
            ? adapter.ReadSiteComputerNames(read.Domain, DcOrNull(), resolved.Ou, patterns, InventoryHardLimit)
            : adapter.ReadSelectedSiteComputerNames(read.Domain, DcOrNull(), selection, patterns, InventoryHardLimit);
        if (!names.InOu.Complete || !names.WithTag.Complete)
            throw new PestoException("directory.incomplete", "La lecture des postes du site est incomplète. Relancez la lecture pour obtenir ses services.");
        var codes = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var name in names.InOu.Names)
            if (convention.TryParse(name) is { } parts) codes.Add(parts.Service);
        foreach (var name in names.WithTag.Names)
            if (convention.TryParse(name) is { } parts && parts.Site.Equals(resolved.Code, StringComparison.OrdinalIgnoreCase))
                codes.Add(parts.Service);
        foreach (var pair in read.NameCatalogue)
            if (pair.Site.Equals(resolved.Code, StringComparison.OrdinalIgnoreCase)) codes.Add(pair.Service);
        return Resp.Obj(("items", Resp.Arr(codes, code => Resp.Obj(("code", code),
            ("name", read.ServiceLabels.GetValueOrDefault(resolved.Code + "|" + code, code))))));
    }

    private JsonObject DirectorySearch(JsonElement args)
    {
        var read = RequireConfig();
        var adapter = RequireGateway();
        var query = Arguments.Text(args, "query", true);
        var limit = Arguments.Number(args, "limit", 50, 1, SearchHardLimit);
        var result = adapter.SearchComputers(read.Domain, DcOrNull(), query, limit);
        var convention = GetConvention(read);
        var items = Resp.Arr(result.Items, c => ComputerNode(c, convention, checks: null));
        return Resp.Obj(("items", items), ("complete", result.Complete), ("collectedAt", clock.GetUtcNow().ToString("O", System.Globalization.CultureInfo.InvariantCulture)));
    }

    private JsonObject ComputerInspect(JsonElement args)
    {
        var read = RequireConfig();
        var adapter = RequireGateway();
        var name = Arguments.Text(args, "computer", true);
        if (!Regex.IsMatch(name, @"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$"))
            throw new PestoException("invalid_arguments", "Nom d’ordinateur invalide (1 à 15 caractères alphanumériques ou tirets, sans tiret en tête ni en fin).");
        var found = adapter.FindComputer(read.Domain, DcOrNull(), name)
            ?? throw new PestoException("computer.missing", "Ce poste n’a pas été trouvé dans l’annuaire du domaine configuré.");
        var convention = GetConvention(read);
        bool? inManagedScope = Split(found.Ou) is null || Split(read.RootOu) is null ? null : WithinScope(found.Ou, read.RootOu);
        var checks = new[]
        {
            new Check("Identité AD", "ok", "Objet ordinateur observé dans l’annuaire."),
            new Check("Périmètre", inManagedScope switch { true => "ok", false => "warn", null => "unknown" },
                inManagedScope switch { true => "DN sous la racine gérée configurée.",
                    false => "DN hors racine gérée : lecture seule, aucune opération ne sera proposée sur ce poste.",
                    null => "Périmètre non confirmé : lecture seule tant que l’OU du poste et la racine ne sont pas connues." }),
            new Check("Canal sécurisé", "unknown", "Non mesuré par la lecture courante."),
        };
        var result = ComputerNode(found, convention, checks);
        result["inManagedScope"] = inManagedScope;
        return result;
    }

    private sealed record ResolvedSite(string Id, string Name, string Code, string Ou);

    private List<ResolvedSite> ResolveSites(V1Config read, IDirectoryGateway adapter)
    {
        var list = new List<ResolvedSite>();
        var seenIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var added = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var parents = read.DeclaredSites.Count == 0 ? Array.Empty<string>() : read.OrganismOus.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var listing = adapter.ReadSiteOus(read.Domain, DcOrNull(), read.ExplicitSites.Select(site => site.Ou).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(), parents);
        foreach (var site in read.ExplicitSites)
        {
            // The batched LDAP read can miss a DN that the exact OU lookup used up to 2.0.9 still confirms.
            if (!listing.Explicit.Contains(site.Ou) && !ConfirmedOu(read, adapter, site.Ou)) continue;
            list.Add(new(site.Id, site.Name, site.Code, site.Ou));
            seenIds.Add(site.Id);
            added.Add(site.Ou);
        }
        var discovered = parents.SelectMany(parent => listing.Children[parent].Select(child => new
        {
            Name = child, Ou = "OU=" + EscapeRdn(child) + "," + parent, Tag = MatchSiteTag(read, child)
        })).Where(site => site.Tag is not null).ToLookup(site => site.Tag!);
        foreach (var declaration in read.DeclaredSites)
            foreach (var site in discovered[declaration])
            {
                if (!added.Add(site.Ou)) continue;
                var id = declaration.Tag;
                for (var suffix = 2; !seenIds.Add(id); suffix++) id = declaration.Tag + "-" + suffix;
                list.Add(new(id, site.Name, declaration.Tag, site.Ou));
            }
        return list;
    }

    private bool ConfirmedOu(V1Config read, IDirectoryGateway adapter, string dn)
    {
        try { return adapter.FindOrganizationalUnit(read.Domain, DcOrNull(), dn)?.DistinguishedName.Equals(dn, StringComparison.OrdinalIgnoreCase) == true; }
        catch (PestoException) { return false; }
    }

    // An exact site wins over wildcards, then the most specific wildcard (most literal characters), then the first
    // declared TAGS entry. Up to 2.0.9 every matching pattern listed the OU; dropping OUs that a broad pattern also
    // matched emptied real site lists in 2.0.10, so an OU matched by any pattern always keeps one code.
    private static V1Config.DeclaredSite? MatchSiteTag(V1Config read, string name)
    {
        var exact = read.DeclaredSites.FirstOrDefault(site => site.Pattern.Equals(name, StringComparison.OrdinalIgnoreCase));
        if (exact is not null) return exact;
        V1Config.DeclaredSite? match = null;
        var best = -1;
        foreach (var site in read.DeclaredSites.Where(site => V1Config.MatchesWildcard(site.Pattern, name)))
        {
            var literals = site.Pattern.Count(c => c is not ('*' or '?'));
            if (literals > best) (match, best) = (site, literals);
        }
        return match;
    }

    private (ResolvedSite Site, SelectedSiteOu? Selection) SiteForInventory(V1Config read, IDirectoryGateway adapter, string wanted)
    {
        static PestoException Invalid() => new("site.invalid", "Choisissez un site configuré et présent dans l’annuaire.");
        if (wanted.StartsWith("OU=", StringComparison.OrdinalIgnoreCase))
        {
            var explicitSite = read.ExplicitSites.FirstOrDefault(site => site.Ou.Equals(wanted, StringComparison.OrdinalIgnoreCase));
            var parts = Split(wanted);
            if (parts is null || !WithinScope(wanted, read.RootOu) || (explicitSite is null &&
                !read.OrganismOus.Contains(string.Join(',', parts.Skip(1)), StringComparer.OrdinalIgnoreCase))) throw Invalid();
            if (explicitSite is not null)
                return (new(explicitSite.Id, explicitSite.Name, explicitSite.Code, wanted), new(wanted, null));

            // DirectorySites emits escaped RDNs. Use that name to prepare the filter, then require the
            // actual OU name, DN and GUID in the same worker before reading any computer.
            var rdn = parts[0][3..];
            var name = Regex.Replace(rdn, @"\\(.)", "$1");
            if (EscapeRdn(name) == rdn && MatchSiteTag(read, name) is { } selectedTag)
                return (new(wanted, name, selectedTag.Tag, wanted), new(wanted, name));

            // Alternative DN encodings retain the legacy lookup by actual directory name.
            var ou = adapter.FindOrganizationalUnit(read.Domain, DcOrNull(), wanted);
            if (ou is null || !ou.DistinguishedName.Equals(wanted, StringComparison.OrdinalIgnoreCase)) throw Invalid();
            var tag = ou.Name is null ? null : MatchSiteTag(read, ou.Name);
            if (tag is null) throw Invalid();
            return (new(ou.DistinguishedName, ou.Name!, tag.Tag, ou.DistinguishedName), null);
        }
        var matches = ResolveSites(read, adapter).Where(site =>
            new[] { site.Id, site.Name, site.Code }.Contains(wanted, StringComparer.OrdinalIgnoreCase)).Take(2).ToArray();
        if (matches.Length != 1 || !WithinScope(matches[0].Ou, read.RootOu)) throw Invalid();
        return (matches[0], null);
    }

    private JsonObject ComputerNode(DirectoryComputer c, NamingConvention convention, Check[]? checks)
    {
        var parts = convention.TryParse(c.Name);
        var node = Resp.Obj(
            ("name", c.Name), ("dnsName", c.DnsName), ("type", parts?.Type), ("site", parts?.Site), ("service", parts?.Service), ("ou", c.Ou),
            ("os", c.Os), ("guid", c.Guid), ("status", "known"), ("domain", c.Domain), ("manufacturer", c.Manufacturer),
            ("model", c.Model), ("serial", c.Serial), ("ip", c.Ip), ("pendingRestart", c.PendingRestart));
        if (checks is not null)
            node["checks"] = Resp.Arr(checks, k => Resp.Obj(("label", k.Label), ("state", k.State), ("detail", k.Detail)));
        return node;
    }

    // ---- name availability (port of Get-PestoJoinNameCandidates / Select-PestoJoinNextName v1) ----

    private sealed class LivePreview
    {
        public required string PreviewId { get; init; }
        public required string Name { get; init; }
        public required string Ou { get; init; }
        public required string Key { get; init; }
        public required DateTimeOffset CollectedAt { get; init; }
        public required DateTimeOffset ExpiresAt { get; init; }
        public required int AvailableCount { get; init; }
        /// <summary>Poste visé par un aperçu de renommage ; null pour une jonction. Lie le plan à ce poste et à lui seul.</summary>
        public string? Computer { get; init; }
        public SharedNameReservationProof? NameReservation { get; init; }
        public PrecreatedJoinAccount? PrecreatedJoin { get; init; }
        /// <summary>Consommation unique : un aperçu ne fonde qu'un seul plan, jamais deux.</summary>
        public bool Consumed;
    }

    private JsonObject NamesPreview(JsonElement args)
    {
        Arguments.Only(args, "type", "site", "service", "computer", "alternative");
        var type = Arguments.Text(args, "type", true);
        var service = Arguments.Text(args, "service", true).ToUpperInvariant();
        var computerName = Arguments.Text(args, "computer");
        var alternative = Arguments.Flag(args, "alternative");

        // Les facettes sont validées par la convention réellement lue/enregistrée, jamais par le motif par défaut.
        var read = RequireConfig();
        var policy = Policy(read);
        var convention = GetConvention(read);
        if (type.Length != 1 || convention.Types.IndexOf(type, StringComparison.Ordinal) < 0)
            throw new PestoException("type.invalid", "Choisissez Portable, Fixe ou Virtuel ; la convention active n’admet que les types " + convention.Types + ".");
        if (!Regex.IsMatch(service, "^[A-Z0-9]{" + convention.ServiceWidth + "}$"))
            throw new PestoException("service.invalid", "Le service est un code de " + convention.ServiceWidth + " caractères alphanumériques (largeur de la convention active).");
        var adapter = gateway ?? throw new PestoException("names.unavailable", NamesUnavailable);
        var wanted = Arguments.Text(args, "site", true);
        var dc = DcOrNull() ?? throw new PestoException("names.unavailable", "Impossible de joindre un contrôleur du domaine pour vérifier les noms.");
        var (resolved, selection) = SiteForInventory(read, adapter, wanted);
        if (!WithinScope(resolved.Ou, read.RootOu))
            throw new PestoException("names.unavailable", "La portée du site est hors de la racine gérée configurée : aucun nom n’est proposé dans une portée non gérée.");

        DirectoryComputer? current = null;
        if (computerName.Length > 0)
        {
            if (!Regex.IsMatch(computerName, @"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$"))
                throw new PestoException("invalid_arguments", "Nom d’ordinateur invalide (1 à 15 caractères alphanumériques ou tirets, sans tiret en tête ni en fin).");
            current = adapter.FindComputer(read.Domain, dc, computerName)
                ?? throw new PestoException("computer.missing", "Ce poste n’a pas été trouvé dans l’annuaire du domaine configuré.");
        }
        policy.AssertExclusions(current?.Name, null, current?.Ou, null);

        if (adapter is not IAutomationNameInventory seriesReader)
            throw new PestoException("names.unavailable", "La lecture des noms de la série dans le domaine est indisponible.");
        var series = convention.SeriesPattern(type, resolved.Code, service);
        var inventory = selection is null
            ? seriesReader.ListAutomationComputerNames(read.Domain, dc, series, InventoryHardLimit)
            : adapter.ReadSelectedSiteSeries(read.Domain, dc, selection, series, InventoryHardLimit);
        if (!inventory.Complete)
            throw new PestoException("names.unavailable", "La lecture AD de la série est incomplète. Recommencez le calcul pour confirmer un nom libre.");
        var held = new HashSet<string>(queue.Select(q => q.NewName), StringComparer.OrdinalIgnoreCase);
        if (current is not null) held.Add(current.Name);
        if (NameReservations(policy) is { } sharedNames) held.UnionWith(sharedNames.OtherReservedNames(read.Domain));

        var key = string.Join('|', type, resolved.Ou, service);
        latestByKey.TryGetValue(key, out var previous);
        alternatives.TryGetValue(key, out var last);
        var lastNumber = alternative ? convention.TryParse(last)?.Number ?? 0 : 0;
        string? chosen; int availableCount;
        using (DirectoryReadEvents.Log.Measure("names.preview", "series.select"))
            (chosen, availableCount) = NameSeriesAvailability.Select(series, convention.NumberWidth, convention.Maximum,
                inventory.Names.Concat(held), policy.ExcludedNames, lastNumber, read.RandomNames ? random : null);
        if (chosen is null)
            throw new PestoException("names.exhausted", "Aucun numéro disponible dans la série " + series + " après lecture du domaine et des réservations.");

        var ou = resolved.Ou;
        if (current is not null)
        {
            var parts = convention.TryParse(current.Name);
            var sameSite = parts is not null && parts.Site.Equals(resolved.Code, StringComparison.OrdinalIgnoreCase);
            if (sameSite && current.Ou is null)
                throw new PestoException("names.unavailable", "L’OU réelle du poste n’a pas été observée : la destination du renommage reste inconnue, aucun OU n’est supposé.");
            if (sameSite) ou = current.Ou!;
        }
        policy.AssertExclusions(current?.Name, chosen, current?.Ou, ou);

        var now = clock.GetUtcNow();
        var previewId = "preview-" + (++serial).ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (previous is { Consumed: false, NameReservation: not null } && !string.Equals(previous.Name, chosen, StringComparison.OrdinalIgnoreCase))
            ReleaseUnusedPreviewName(previous.NameReservation);
        var lease = ReservePreviewName(read, policy, chosen, previewId);
        if (previous is not null) previews.Remove(previous.PreviewId);
        alternatives[key] = chosen;
        var preview = new LivePreview
        {
            PreviewId = previewId,
            Name = chosen, Ou = ou, Key = key, CollectedAt = now, ExpiresAt = ExpiresWithNameLease(now.AddMinutes(PreviewMinutes), lease),
            AvailableCount = availableCount,
            Computer = current?.Name, NameReservation = lease,
        };
        previews[preview.PreviewId] = preview;
        latestByKey[key] = preview;
        return Resp.Obj(
            ("previewId", preview.PreviewId), ("name", preview.Name), ("ou", preview.Ou), ("complete", true),
            ("collectedAt", Iso(preview.CollectedAt)), ("expiresAt", Iso(preview.ExpiresAt)),
            ("reservationExpiresAt", lease is null ? null : Iso(lease.ExpiresAt)),
            ("availableCount", preview.AvailableCount), ("source", "annuaire réel · " + adapter.Description));
    }

    private static string Iso(DateTimeOffset value) => value.ToString("O", System.Globalization.CultureInfo.InvariantCulture);

    // ---- prepare / execute (mode réel : plan lié à l'aperçu, envoi réservé à l'adaptateur qualifié) ----

    private sealed class LivePlan
    {
        public required string PlanId { get; init; }
        public required string Kind { get; init; }
        public required string Computer { get; init; }
        public required string NewName { get; init; }
        public required string TargetOu { get; init; }
        public required DateTimeOffset ExpiresAt { get; init; }
        public required string ConfirmationName { get; init; }
        public required string ConfigurationSha256 { get; init; }
        public string? Guid { get; init; }
        public string? SourceOu { get; init; }
        public string? TargetOuGuid { get; init; }
        public MoveContinuationAuthorization? Continuation { get; init; }
        public bool ReservationRequired { get; init; }
        public SharedNameReservationProof? NameReservation { get; init; }
        public EntraRenameAuthorization? Entra { get; init; }
        public PrecreatedJoinAccount? PrecreatedJoin { get; init; }
        public List<Step> Steps { get; init; } = [];
        public List<string> Warnings { get; init; } = [];
        public bool Used;
    }

    /// <summary>
    /// Préparation sans mutation : elle ne fait qu'une chose de plus qu'une lecture — elle fige un plan lié à l'aperçu live
    /// (consommation unique), au GUID réellement observé du poste et à une OU réellement observée. Collision détectée à la
    /// préparation = refus motivé renvoyant vers un nouvel aperçu et un nouveau clic, jamais un nouvel ajout automatique.
    /// </summary>
    private JsonObject OperationPrepare(JsonElement args)
    {
        var plan = BuildPlan(args);
        Log($"Plan préparé ({plan.Kind}) : {plan.Computer} → {plan.NewName}, lié à l’aperçu et au GUID observés.");
        return PlanNode(plan);
    }

    private static JsonObject PlanNode(LivePlan plan) => Resp.Obj(
        ("planId", plan.PlanId), ("kind", plan.Kind), ("computer", plan.Computer), ("newName", plan.NewName),
        ("targetOU", plan.TargetOu), ("mode", "live"), ("expiresAt", Iso(plan.ExpiresAt)),
        ("confirmationName", plan.ConfirmationName), ("parentReceiptId", plan.Continuation?.ParentReceiptId),
        ("reservationRequired", plan.ReservationRequired),
        ("joinAccountMode", plan.PrecreatedJoin is null ? "new" : "precreated"), ("computerGuid", plan.Guid),
        ("reservationExpiresAt", plan.NameReservation is null ? null : Iso(plan.NameReservation.ExpiresAt)),
        ("entraLeaveRequired", plan.Entra?.LeaveRequired == true),
        ("entraState", plan.Entra?.State), ("entraPolicy", plan.Entra?.Policy),
        ("entraObservedAt", plan.Entra is null ? null : Iso(plan.Entra.ObservedAt)),
        ("entraExpiresAt", plan.Entra is null ? null : Iso(plan.Entra.ExpiresAt)),
        ("steps", Resp.Arr(plan.Steps, s => Resp.Obj(("label", s.Label), ("detail", s.Detail)))),
        ("warnings", Resp.Arr(plan.Warnings, w => (JsonNode?)Resp.Node(w))));

    /// <summary>
    /// Port du « control summary » V1 (Pesto-Core.ps1:4035 pour la confirmation de file, Pesto-Direct.ps1:345 pour la
    /// confirmation unitaire) : avant de confirmer, V1 affichait la politique de repli réellement lue. La note n'existe
    /// QUE si l'adaptateur de mutation injecté la déclare lui-même (<see cref="IMutationFallbackDisclosure"/>) : la
    /// simulation et la production, qui n'injectent aucun adaptateur, restent muettes et n'affichent jamais un état inventé.
    /// Texte V1 reproduit mot pour mot quand la politique est lue vraie avec compte explicitement saisi ; variante fermée
    /// quand elle est lue fausse ou non lue de façon fiable (la politique n'est jamais activée implicitement) ; en session
    /// SSO le repli reste dit indisponible, conformément au garde V1. Réservée aux plans de renommage : le repli V1 n'existe
    /// que pour le renommage (table <see cref="TaskFallback.Decide"/>), l'afficher sur un déplacement seul serait mensonger.
    /// </summary>
    private IEnumerable<string> FallbackNotes(bool batch)
    {
        if (mutation is not IMutationFallbackDisclosure disclosure) return [];
        if (disclosure.FallbackPolicyState == TaskFallbackPolicy.True)
        {
            if (disclosure.FallbackAccountMode != TaskFallbackAccountMode.ExplicitAccount)
                return ["Politique : POLICY.AllowPasswordTaskFallback lu vrai mais la session courante est le compte Windows intégré (SSO) : le repli V1 par tâche sous compte AD reste indisponible — il exige un compte AD explicitement saisi (port V1), jamais un repli implicite."];
            return
            [
                batch
                    ? "Politique : un repli par tâche Windows utilisant le mot de passe du compte AD est autorisé en cas de refus confirmé. Les tâches sont suivies ; aucun repli après résultat incertain."
                    : "Politique : le repli par tâche Windows utilisant le mot de passe du compte AD est autorisé en cas de refus confirmé. Aucun repli sur résultat incertain.",
                "Compte de repli : compte AD explicitement saisi au moment de l’opération, mot de passe en mémoire seule de l’adaptateur ; le repli reste soumis aux gardes V1 (distant seulement, refus confirmé 5 ou 1314, jamais après un résultat incertain).",
            ];
        }
        var read = disclosure.FallbackPolicyState == TaskFallbackPolicy.Unknown
            ? "POLICY.AllowPasswordTaskFallback non lu de façon fiable dans le cfg.json"
            : "POLICY.AllowPasswordTaskFallback lu « false » (défaut V1)";
        return ["Politique : " + read + " — aucun repli par tâche Windows avec mot de passe du compte AD n’est autorisé ; un refus confirmé reste un refus. La politique n’est jamais activée implicitement."];
    }

    /// <summary>
    /// Chemin de validation partagé entre la préparation unitaire et l'ajout en file : mêmes gardes exactement
    /// (aperçu obligatoire, frais, latest, lié au poste, consommé une fois ; GUID et OU réellement observés ; nom
    /// re-vérifié ; destination observée sous la racine gérée). Retourne le plan enregistré, sans rien écrire.
    /// </summary>
    private LivePlan BuildPlan(JsonElement args, bool automationReadOnlyPreparation = false)
    {
        Arguments.Only(args, "kind", "computer", "previewId", "newName", "targetOU");
        var kind = Arguments.Text(args, "kind", true);
        if (!Kinds.Contains(kind, StringComparer.Ordinal)) throw new PestoException("operation.kind", "Action non prise en charge.");
        var computerName = Optional(args, "computer");
        var previewId = Optional(args, "previewId");
        var newNameArg = Optional(args, "newName");
        var targetArg = Optional(args, "targetOU");

        var read = RequireConfig();
        var adapter = RequireGateway();

        var policy = Policy(read);
        policy.RequireSupported(kind);
        if (kind == "join")
        {
            var precreatedCandidate = previewId is not null ? previews.GetValueOrDefault(previewId)?.PrecreatedJoin : null;
            if (policy.ReserveNamesInAd && mutation is not IMutationJoinReservation && precreatedCandidate is null)
                throw new PestoException("reservation.unavailable", "POLICY.ReserveNamesInAD exige un adaptateur de réservation AD ; aucune jonction préparée sans ce parcours.");
            // Garde-fou mission : jonction locale uniquement — ce poste, jamais un autre.
            if (computerName is not null && !computerName.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("join.localOnly", "La jonction concerne uniquement ce poste.");
            computerName = Environment.MachineName;
            var current = adapter.FindComputer(read.Domain, DcOrNull(), computerName);
            if (current is not null && (precreatedCandidate is null || !string.Equals(current.Guid, precreatedCandidate.ComputerGuid, StringComparison.OrdinalIgnoreCase)
                || !string.Equals(current.Name, precreatedCandidate.Name, StringComparison.OrdinalIgnoreCase)))
                throw new PestoException("join.alreadyJoined", "Le poste local est déjà présent dans l’annuaire du domaine configuré : la jonction n’a pas de sens.");
        }
        else if (computerName is null)
            throw new PestoException("invalid_arguments", "Le nom du poste est requis pour cette action.");
        if (kind == "move" && targetArg is null)
            throw new PestoException("invalid_arguments", "L’OU de destination est requise pour un déplacement.");
        if (kind != "join") ValidateComputerName(computerName!);

        // Le nom ne peut venir que d'un aperçu live : inconnu, expiré, remplacé ou déjà consommé → plan.stale. Jamais de nom libre calculé à la volée.
        LivePreview? preview = null;
        if (kind != "move")
        {
            if (previewId is null)
                throw new PestoException("preview.missing", "Calculez d’abord un aperçu du nom : le nom réellement libre est vérifié dans l’annuaire avant toute préparation.");
            preview = previews.GetValueOrDefault(previewId)
                ?? throw new PestoException("plan.stale", "L’aperçu du nom n’existe plus ou a été remplacé : calculez un nouvel aperçu, puis cliquez de nouveau.");
            if (preview.PrecreatedJoin is not null && kind != "join")
                throw new PestoException("join.precreated_scope", "L’aperçu d’un compte précréé ne peut servir qu’à la jonction locale explicite.");
            if (preview.Consumed)
                throw new PestoException("plan.stale", "Cet aperçu a déjà fondé un plan : un aperçu ne se consomme qu’une fois. Calculez un nouvel aperçu, puis cliquez de nouveau.");
            if (preview.ExpiresAt <= clock.GetUtcNow())
                throw new PestoException("plan.stale", "L’aperçu du nom a expiré : calculez un nouvel aperçu, puis cliquez de nouveau.");
            if (latestByKey.TryGetValue(preview.Key, out var latest) && !ReferenceEquals(latest, preview))
                throw new PestoException("plan.stale", "L’aperçu du nom a été remplacé par un calcul plus récent : reprenez le dernier aperçu.");
            if (kind != "join" && !string.Equals(preview.Computer, computerName, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("preview.identity", "Cet aperçu appartient à un autre poste.");
            if (kind == "join" && preview.Computer is not null)
                throw new PestoException("preview.identity", "Cet aperçu a été calculé pour un renommage, pas pour la jonction de ce poste.");
        }

        if (preview is not null) ValidatePrecreatedJoinPreview(preview, read, policy);
        string? computerGuid = preview?.PrecreatedJoin?.ComputerGuid;
        string? sourceOu = preview?.PrecreatedJoin?.TargetOu;
        if (kind != "join")
        {
            var found = adapter.FindComputer(read.Domain, DcOrNull(), computerName!)
                ?? throw new PestoException("computer.missing", "Ce poste n’a pas été trouvé dans l’annuaire du domaine configuré.");
            computerGuid = found.Guid;
            sourceOu = found.Ou;
            if (!Guid.TryParse(computerGuid, out var observedGuid) || observedGuid == Guid.Empty)
                throw new PestoException("identity.missing", "L’identité GUID du poste source n’est pas confirmée : aucune préparation.");
            if (!WithinScope(sourceOu, read.RootOu))
                throw new PestoException("source.out_of_scope", "Le poste source est hors de la racine gérée ou son OU n’est pas connue : aucune préparation.");
        }

        var newName = kind == "move" ? computerName! : preview!.Name;
        if (newNameArg is not null && !newNameArg.Equals(newName, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("preview.changed", "Le nom demandé ne correspond plus à l’aperçu.");
        if (kind != "move")
        {
            // Le nom est re-vérifié à la préparation : collision = nouvel aperçu + nouveau clic, jamais d'ajout automatique.
            var takenNow = adapter.FindComputer(read.Domain, DcOrNull(), newName);
            if (takenNow is not null && !string.Equals(takenNow.Guid, computerGuid, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("name.taken", "Le nom de l’aperçu vient d’être pris dans l’annuaire. Aucun ajout automatique : calculez un nouvel aperçu, puis cliquez de nouveau.");
        }

        if (kind == "renameMove")
        {
            var naming = GetConvention(read);
            var oldParts = naming.TryParse(computerName!);
            var newParts = naming.TryParse(newName);
            var sameSite = oldParts is not null && newParts is not null
                && oldParts.Site.Equals(newParts.Site, StringComparison.OrdinalIgnoreCase);
            if (sameSite || string.Equals(sourceOu, preview!.Ou, StringComparison.OrdinalIgnoreCase))
            {
                // The business rule belongs to the engine as well as the form. Keep any deeper source OU intact.
                if (targetArg is not null && !string.Equals(targetArg, sourceOu, StringComparison.OrdinalIgnoreCase))
                    throw new PestoException("rename.no_move", "Le site ne change pas : seule l’action de renommage est admise, avec conservation de l’OU actuelle.");
                kind = "rename";
            }
        }

        string targetOu;
        if (kind == "rename")
        {
            // A rename never moves the AD object, even when a direct API caller chose a different site for the name.
            // Keep the plan, native request and durable receipt honest about the OU that will actually remain.
            targetOu = sourceOu!;
            if (targetArg is not null && !string.Equals(targetArg, targetOu, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("rename.no_move", "Un renommage seul conserve l’OU actuelle. Préparez explicitement un renommage avec déplacement pour changer de site.");
        }
        else if (kind is "move" or "renameMove" && targetArg is not null)
        {
            targetOu = ResolveObservedOu(read, adapter, targetArg);
            if (kind == "renameMove" && !string.Equals(targetOu, preview!.Ou, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("preview.changed", "La destination demandée ne correspond pas à l’OU observée de l’aperçu.");
        }
        else
        {
            targetOu = preview!.Ou;
            if (preview.PrecreatedJoin is not null && targetArg is not null && !string.Equals(targetArg, targetOu, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("join.precreated_ou", "La jonction ne déplace pas le compte précréé : l’OU doit rester celle de l’aperçu.");
            if (!WithinScope(targetOu, read.RootOu))
                throw new PestoException("names.unavailable", "L’OU de destination n’est pas sous la racine gérée configurée : aucune préparation dans une portée non gérée.");
        }

        policy.AssertPlan(kind, computerName!, newName, sourceOu, targetOu, GetConvention(read));
        if (preview?.PrecreatedJoin is null && !automationReadOnlyPreparation) VerifyPreviewName(read, policy, kind, newName, preview?.NameReservation, configStamp!);
        RequireGroupExclusions(read, policy, computerGuid, preview?.PrecreatedJoin?.Name ?? computerName!, sourceOu);
        var targetOuGuid = kind is "join" or "move" or "renameMove" ? ResolveTargetGuid(read, adapter, targetOu) : null;
        var joinClock = CheckJoinClock(policy, kind);
        var entra = PrepareEntraPlan(kind, computerName!, computerGuid, newName, read.Domain, sourceOu, configStamp!);
        var steps = new List<Step>();
        steps.Add(new("Vérifier l’identité", computerName!));
        steps.Add(new(kind == "move" ? "Déplacer le compte" : "Appliquer le nom confirmé", kind == "move" ? targetOu : newName));
        if (kind is "renameMove" or "join") steps.Add(new("Vérifier le placement", targetOu));
        if (kind == "join" && policy.ReserveNamesInAd && preview?.PrecreatedJoin is null)
            steps.Insert(1, new("Réserver le compte AD après confirmation", newName + " · " + targetOu));

        var warnings = new List<string>
        {
            "Réel : cette préparation n’écrit rien. L’exécution exige une confirmation exacte ; identité, nom libre et barrières sont revérifiés avant l’envoi.",
            "Aucun redémarrage implicite. Un éventuel retrait Entra doit être affiché dans ce plan et confirmé séparément.",
        };
        if (kind == "join") warnings.Add("Jonction locale uniquement : ce poste, sous la racine gérée configurée.");
        if (joinClock is not null) warnings.Add(joinClock.Message);
        if (kind == "join" && policy.ReserveNamesInAd && preview?.PrecreatedJoin is null)
            warnings.Add("La confirmation autorise la création du compte AD réservé à ce nom, puis la jonction sur son GUID vérifié. Si la jonction n’aboutit pas, la réservation reste consignée ; aucune suppression automatique. Sa reprise ou sa libération exigera une nouvelle préparation et confirmation.");
        // Port du control summary V1 : la note de politique de repli n'est rendue que par un adaptateur qui la déclare
        // lui-même, et seulement là où le repli existe en V1 — le renommage.
        if (kind is "rename" or "renameMove") warnings.AddRange(FallbackNotes(batch: false));
        if (mutation is IMutationPreparationDisclosure disclosure) warnings.AddRange(disclosure.PreparationNotes(kind, computerName!));
        if (entra?.LeaveRequired == true) { steps.Insert(1, new("Retrait Entra explicitement confirmé", computerName!)); warnings.Add("Ce poste est hybride : le retrait Entra précède le renommage. La réinscription hybride devra être vérifiée séparément."); }
        if (preview?.PrecreatedJoin is { } precreated)
        {
            steps.Insert(1, new("Reprendre uniquement le compte AD confirmé", precreated.Name + " · GUID " + precreated.ComputerGuid));
            warnings.Add("Compte AD précréé : aucune création ni recréation, aucun changement de propriétaire ou de droits. Windows reste l’autorité pour accepter la réutilisation de ce compte.");
        }

        var plan = new LivePlan
        {
            PlanId = "plan-" + (++serial).ToString(System.Globalization.CultureInfo.InvariantCulture),
            Kind = kind,
            Computer = computerName!,
            NewName = newName,
            TargetOu = targetOu,
            ExpiresAt = ExpiresWithEntra(ExpiresWithNameLease(clock.GetUtcNow().AddMinutes(PlanMinutes), preview?.NameReservation), entra),
            ConfirmationName = newName.Length > 0 ? newName : computerName!,
            ConfigurationSha256 = configStamp ?? throw new PestoException("config.changed", "Empreinte de configuration absente : préparez à nouveau."),
            Guid = computerGuid,
            SourceOu = sourceOu,
            TargetOuGuid = targetOuGuid,
            ReservationRequired = kind == "join" && policy.ReserveNamesInAd && preview?.PrecreatedJoin is null,
            NameReservation = preview?.NameReservation,
            Entra = entra,
            PrecreatedJoin = preview?.PrecreatedJoin,
            Steps = steps,
            Warnings = warnings,
        };
        if (preview is not null) preview.Consumed = true;
        plans[plan.PlanId] = plan;
        return plan;
    }

    /// <summary>
    /// Exécution réelle avec l’adaptateur disponible de l’hôte ou du harnais de qualification.
    /// Sans adaptateur, refus avant toute consommation : aucun reçu fictif n’est produit.
    /// Avec un adaptateur disponible : consommation du plan AVANT
    /// envoi, reçu écrit avant l'envoi et relu après, relecture annuaire pour toute confirmation, résultat incertain
    /// conservé et jamais rejoué (port des phases v1 Running/PendingRestart/Uncertain).
    /// </summary>
    private JsonObject OperationExecute(JsonElement args)
    {
        Arguments.Only(args, "planId", "confirmationName", "entraLeaveConfirmed");
        var plan = plans.GetValueOrDefault(Arguments.Text(args, "planId", true))
            ?? throw new PestoException("plan.stale", "Le plan n’existe plus ou a expiré : préparez un nouvel aperçu.");
        return ExecutePlan(plan, Arguments.Text(args, "confirmationName", true), Arguments.Flag(args, "entraLeaveConfirmed"));
    }

    /// <summary>
    /// Pipeline d'envoi unique, partagé entre l'exécution unitaire et chaque ligne du lot : identité et disponibilité
    /// relues juste avant envoi, plan consommé avant envoi, reçu écrit avant l'envoi puis complété après relecture,
    /// résultat incertain jamais rejoué. Utilisé par la file : une ligne du lot suit exactement le même chemin qu'une
    /// opération unitaire confirmée, jamais un chemin d'écriture parallèle.
    /// </summary>
    private JsonObject ExecutePlan(LivePlan plan, string confirmationName, bool entraLeaveConfirmed = false, AutomationExecutionAuthorization? automation = null)
    {
        if (plan.ExpiresAt <= clock.GetUtcNow())
            throw new PestoException("plan.stale", "Le plan a expiré : préparez un nouvel aperçu, puis cliquez de nouveau.");
        if (plan.Used) throw new PestoException("plan.consumed", "Ce plan a déjà été envoyé. Consultez son reçu ; rien n’est rejoué automatiquement.");
        if (!confirmationName.Equals(plan.ConfirmationName, StringComparison.Ordinal))
            throw new PestoException("confirmation.invalid", "Le nom confirmé ne correspond pas au plan. Préparez de nouveau l’opération.");
        if (plan.Entra?.LeaveRequired == true && !entraLeaveConfirmed)
            throw new PestoException("entra.confirmation", "Confirmez explicitement le retrait Entra affiché par ce plan avant le renommage.");
        if (plan.Kind is "rename" or "renameMove" && (plan.Entra is null || plan.Entra.ExpiresAt <= clock.GetUtcNow()))
            throw new PestoException("entra.stale", "L’observation Entra de ce plan a expiré : préparez et confirmez un nouveau plan.");

        if (mutation is null) throw new PestoException("write.unavailable", WriteUnavailable);

        var read = RequireConfig();
        RequireUnchangedConfiguration();
        if (!string.Equals(configStamp, plan.ConfigurationSha256, StringComparison.Ordinal))
            throw new PestoException("plan.stale", "La configuration du plan n’est plus celle de la session : préparez un nouvel aperçu.");
        var policy = Policy(read);
        ValidatePrecreatedJoinPlan(plan, read, policy);
        policy.AssertPlan(plan.Kind, plan.Computer, plan.NewName, plan.SourceOu, plan.TargetOu, GetConvention(read));
        if (plan.PrecreatedJoin is null) VerifyPreviewName(read, policy, plan.Kind, plan.NewName, plan.NameReservation, plan.ConfigurationSha256);
        var adapter = RequireGateway();

        // Juste avant envoi : identité et disponibilité sont relues (port v1 « l'état a changé pendant le contrôle → aucun envoi »).
        if (plan.Kind != "join")
        {
            var found = adapter.FindComputer(read.Domain, DcOrNull(), plan.Computer)
                ?? throw new PestoException("identity.changed", "Le poste n’a plus été relu avant l’envoi. Rien n’a été appliqué.");
            if (!string.Equals(found.Guid, plan.Guid, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("identity.changed", "L’identité du poste a changé depuis la préparation. Rien n’a été appliqué.");
            if (!WithinScope(found.Ou, read.RootOu) || !string.Equals(found.Ou, plan.SourceOu, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("source.changed", "L’OU source a changé depuis la préparation ou sort du périmètre : rien n’a été appliqué.");
        }
        if (plan.Kind is "join" or "move" or "renameMove"
            && !string.Equals(ResolveTargetGuid(read, adapter, plan.TargetOu), plan.TargetOuGuid, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("destination.changed", "Le GUID de l’OU cible a changé depuis la confirmation : aucune commande envoyée.");
        if (plan.Kind != "move")
        {
            var taken = adapter.FindComputer(read.Domain, DcOrNull(), plan.NewName);
            if (taken is not null && !string.Equals(taken.Guid, plan.Guid, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("name.taken", "Le nom vient d’être pris. Aucun ajout automatique : nouvel aperçu, nouveau clic.");
        }

        RequireGroupExclusions(read, policy, plan.Guid, plan.PrecreatedJoin?.Name ?? plan.Computer, plan.SourceOu);
        var joinClock = CheckJoinClock(policy, plan.Kind);
        if (joinClock is { State: "warning" }) Log(joinClock.Message);

        // Directory/group/clock reads can take longer than the authorization's remaining lifetime.
        // Recheck immediately before consumption; a slow read never extends a confirmed plan.
        if (plan.ExpiresAt <= clock.GetUtcNow())
            throw new PestoException("plan.stale", "Le plan a expiré pendant les dernières vérifications : aucune commande envoyée. Préparez et confirmez un nouveau plan.");
        RequireUnchangedConfiguration();

        // Consommation avant envoi : un plan admis ne peut plus être rejoué, même si le résultat reste incertain.
        plan.Used = true;

        // Reçu écrit AVANT l'envoi, relu et complété après (port de Write-PestoJoinReceipt Phase='Running' avant Add-Computer).
        var receipt = new Receipt(automation?.ReceiptId ?? "receipt-" + Guid.NewGuid().ToString("N"),
            clock.GetUtcNow(), plan.Kind, plan.Computer, plan.NewName, plan.TargetOu, "live · " + mutation.Description,
            "sent", 0, "Demande préparée, reçu écrit avant l’envoi, résultat non encore relu.", false, plan.Continuation?.ParentReceiptId);
        receipts.Insert(0, receipt);
        Log($"Envoi de la mutation {plan.Kind} : {plan.Computer} → {plan.NewName} (plan {plan.PlanId}, adaptateur {mutation.Description}).");

        var request = new MutationRequest(plan.Kind, plan.Computer, plan.Guid,
            plan.Kind == "move" ? null : plan.NewName, plan.TargetOu.Length > 0 ? plan.TargetOu : null,
            read.Domain, DcOrNull(), plan.PlanId, receipt.Id, plan.SourceOu, plan.TargetOuGuid, plan.Continuation,
            ReservationRequired: plan.ReservationRequired, ConfigurationSha256: plan.ConfigurationSha256, NameReservation: plan.NameReservation,
            Entra: plan.Entra, EntraLeaveConfirmed: plan.Entra?.LeaveRequired == true && entraLeaveConfirmed, PrecreatedJoin: plan.PrecreatedJoin, Automation: automation);
        MutationOutcome outcome;
        try
        {
            outcome = mutation.Execute(request);
        }
        catch (PestoException)
        {
            return Finalize(receipt, request, MutationStatus.Uncertain, 0,
                "L’adaptateur de mutation a échoué sans confirmer le résultat : à vérifier avant toute reprise, jamais rejoué automatiquement.");
        }
        catch (Exception)
        {
            return Finalize(receipt, request, MutationStatus.Uncertain, 0,
                "Résultat de l’adaptateur de mutation illisible : à vérifier avant toute reprise, jamais rejoué automatiquement.");
        }

        // Relecture après envoi : le moteur ne confirme que ce que l'annuaire montre réellement.
        bool confirmed;
        var reservationIdentityChanged = false;
        DirectoryComputer? observed = null;
        try
        {
            confirmed = ReReadConfirms(adapter, read, plan, out observed);
            // A confirmed reservation binds the join to one AD object, never a same-name replacement.
            if (plan.Kind == "join" && outcome.ObservedGuid is { } reservedGuid
                && (observed is null || !string.Equals(reservedGuid, observed.Guid, StringComparison.OrdinalIgnoreCase)))
            { confirmed = false; reservationIdentityChanged = true; }
            if (plan.Kind == "join" && plan.ReservationRequired && outcome.Status == MutationStatus.Failed && outcome.ObservedGuid is null)
                confirmed = false; // Taken/pre-creation refusal never adopts a same-name account owned by somebody else.
            if (plan.PrecreatedJoin is { } precreated)
            {
                if (outcome.Status == MutationStatus.Failed) confirmed = false; // The account existed before the attempted action.
                else if (observed is null || !string.Equals(precreated.ComputerGuid, observed.Guid, StringComparison.OrdinalIgnoreCase)
                    || !string.Equals(precreated.Name, observed.Name, StringComparison.OrdinalIgnoreCase)
                    || !string.Equals(precreated.TargetOu, observed.Ou, StringComparison.OrdinalIgnoreCase)
                    || !string.Equals(precreated.Domain, observed.Domain, StringComparison.OrdinalIgnoreCase))
                { confirmed = false; reservationIdentityChanged = true; }
            }
        }
        catch (Exception)
        {
            return Finalize(receipt, request, MutationStatus.Uncertain, 97,
                "Relecture annuaire impossible après l’envoi : conserver ce reçu et vérifier le poste avant toute reprise, jamais rejoué automatiquement. " + Safe(outcome.Message),
                outcome.RestartRequired);
        }
        if (reservationIdentityChanged)
            return Finalize(receipt, request, MutationStatus.Uncertain, 97,
                "Le GUID réservé n’est plus confirmé par la relecture finale : aucun succès ni simple attente de redémarrage supposés. Conserver le reçu et inspecter la réservation.", outcome.RestartRequired);
        return outcome.Status switch
        {
            MutationStatus.Failed when !confirmed => Finalize(receipt, request, MutationStatus.Failed, outcome.Code,
                "Refus confirmé ; le changement demandé n’est pas observé dans l’annuaire. " + Safe(outcome.Message)),
            MutationStatus.Failed => Finalize(receipt, request, MutationStatus.Uncertain, outcome.Code,
                "L’adaptateur annonce un refus mais la relecture montre un changement : à vérifier avant toute reprise, jamais rejoué automatiquement."),
            MutationStatus.PendingRestart => Finalize(receipt, request, MutationStatus.PendingRestart, outcome.Code,
                "Acceptée ; effet attendu après un redémarrage que l’opérateur planifie lui-même. " + Safe(outcome.Message), true, confirmed ? observed?.Guid : null),
            MutationStatus.Succeeded when confirmed => Finalize(receipt, request, MutationStatus.Succeeded, outcome.Code,
                "Appliquée et confirmée par relecture annuaire. " + Safe(outcome.Message), outcome.RestartRequired, observed?.Guid),
            MutationStatus.Succeeded => Finalize(receipt, request, MutationStatus.Uncertain, outcome.Code,
                "L’adaptateur a confirmé mais la relecture annuaire ne confirme pas : à vérifier avant toute reprise, jamais rejoué automatiquement.", outcome.RestartRequired),
            _ => Finalize(receipt, request, MutationStatus.Uncertain, outcome.Code,
                "Résultat signalé incertain par l’adaptateur : à vérifier avant toute reprise, jamais rejoué automatiquement. " + Safe(outcome.Message), outcome.RestartRequired),
        };
    }

    private bool ReReadConfirms(IDirectoryGateway adapter, V1Config read, LivePlan plan, out DirectoryComputer? observed)
    {
        var expectedName = plan.Kind == "move" ? plan.Computer : plan.NewName;
        observed = adapter.FindComputer(read.Domain, DcOrNull(), expectedName);
        // The native search can also resolve a CN/sAM alias. Finding the GUID alone does not prove
        // the requested final name or placement, especially after another administrator's change.
        if (observed is null || !string.Equals(observed.Name, expectedName, StringComparison.OrdinalIgnoreCase)
            || !Guid.TryParse(observed.Guid, out var observedGuid) || observedGuid == Guid.Empty) return false;
        if (plan.Kind != "join" && (plan.Guid is null || !string.Equals(observed.Guid, plan.Guid, StringComparison.OrdinalIgnoreCase))) return false;
        var expectedOu = plan.Kind == "rename" ? plan.SourceOu : plan.TargetOu;
        return !string.IsNullOrWhiteSpace(expectedOu) && string.Equals(observed.Ou, expectedOu, StringComparison.OrdinalIgnoreCase);
    }

    private JsonObject Finalize(Receipt receipt, MutationRequest request, MutationStatus status, int code, string message, bool restartRequired = false, string? observedGuid = null)
    {
        if (status == MutationStatus.Succeeded && restartRequired) status = MutationStatus.PendingRestart;
        if (mutation is IMutationReceiptFinalizer finalizer)
        {
            try { finalizer.PersistFinalReceipt(request, new MutationOutcome(status, code, message, restartRequired || status == MutationStatus.PendingRestart, observedGuid)); }
            catch (Exception)
            {
                status = MutationStatus.Uncertain;
                code = 97;
                message = "Le résultat final du moteur n’a pas pu être enregistré durablement : à vérifier avant toute reprise, jamais rejoué automatiquement. " + Safe(message);
            }
        }
        var mapped = status switch
        {
            MutationStatus.Succeeded => "succeeded",
            MutationStatus.PendingRestart => "pendingRestart",
            MutationStatus.Failed => "refused",
            _ => "uncertain",
        };
        var final = receipt with
        {
            Status = mapped,
            Code = code,
            Message = message,
            RestartRequired = restartRequired || status == MutationStatus.PendingRestart,
        };
        receipts[receipts.FindIndex(r => r.Id == receipt.Id)] = final;
        if (mapped == "succeeded" && request.Continuation is { } continuation && mutation is IMutationReceiptFinalizer)
        {
            var parentIndex = receipts.FindIndex(r => r.Id == continuation.ParentReceiptId);
            if (parentIndex >= 0) receipts[parentIndex] = receipts[parentIndex] with
                { Status = "uncertain", RestartRequired = false, ResolutionChildReceiptId = receipt.Id };
        }
        Log($"Reçu {final.Id} ({final.Kind}) : statut {mapped}.", mapped == "uncertain" ? "warn" : "info");
        return ReceiptNode(final);
    }

    // ---- file live (Plusieurs postes, mode réel) --------------------------------------

    private sealed record LiveQueueItem(string Id, string Kind, string Computer, string NewName, string TargetOu, string? Guid, string? PreviewId, string? SourceOu, string? TargetOuGuid, SharedNameReservationProof? NameReservation)
    {
        public string Status { get; set; } = "ready";
    }

    private sealed class LiveBatch
    {
        public required string BatchId { get; init; }
        public required DateTimeOffset ExpiresAt { get; set; }
        public required int QueueVersion { get; init; }
        public bool Pilot { get; init; }
        public List<(string ItemId, string PlanId)> Entries { get; } = [];
        public bool Used;
    }

    /// <summary>
    /// Ajout en file, sans aucune écriture : la ligne est validée par le même chemin qu'une opération unitaire
    /// (aperçu obligatoire, frais, lié au poste, consommé à l'ajout — une ligne = un aperçu ; GUID et OU réellement
    /// observés ; nom re-vérifié). Doublons de poste ou de nom refusés ; borne = POLICY.MaxBatch lu dans la
    /// configuration V1, jamais une valeur codée en dur. Toute modification de la file invalide les lots préparés.
    /// </summary>
    private JsonObject QueueAdd(JsonElement args)
    {
        Arguments.Only(args, "kind", "computer", "newName", "targetOU", "previewId");
        if (Optional(args, "previewId") is { } precreatedId && previews.GetValueOrDefault(precreatedId)?.PrecreatedJoin is not null)
            throw new PestoException("join.precreated_scope", "La jonction sur compte précréé ne peut pas être placée en file.");
        var kind = Arguments.Text(args, "kind", true);
        if (kind == "join") throw new PestoException("queue.local", "La jonction locale ne peut pas être placée en file.");
        if (!Kinds.Contains(kind, StringComparer.Ordinal)) throw new PestoException("operation.kind", "Action non prise en charge.");
        var read = RequireConfig();
        var maxBatch = MaximumBatch(read);
        if (queue.Count >= maxBatch)
            throw new PestoException("queue.limit", "La file est limitée à " + maxBatch + " postes (minimum des bornes POLICY.MaxBatch et HKLM) : retirez des lignes ou traitez le lot.");
        var computerArg = Optional(args, "computer");
        if (computerArg is not null && queue.Any(q => q.Computer.Equals(computerArg, StringComparison.OrdinalIgnoreCase)))
            throw new PestoException("queue.duplicate", "Ce poste est déjà dans la file : aucune ligne dupliquée.");
        if (Optional(args, "previewId") is { } probeId && previews.TryGetValue(probeId, out var probe)
            && queue.Any(q => q.NewName.Equals(probe.Name, StringComparison.OrdinalIgnoreCase)))
            throw new PestoException("queue.duplicate", "Ce nom est déjà visé par une ligne de la file : aucune ligne dupliquée.");

        var plan = BuildPlan(args);
        plans.Remove(plan.PlanId); // la file n'exécute rien ici : le plan du lot sera reforgé et re-vérifié à queue.prepare
        if (queue.Any(q => q.NewName.Equals(plan.NewName, StringComparison.OrdinalIgnoreCase)))
            throw new PestoException("queue.duplicate", "Ce nom est déjà visé par une ligne de la file : aucune ligne dupliquée.");
        queue.Add(new LiveQueueItem("queue-" + (++serial).ToString(System.Globalization.CultureInfo.InvariantCulture),
            plan.Kind, plan.Computer, plan.NewName, plan.TargetOu, plan.Guid, Optional(args, "previewId"), plan.SourceOu, plan.TargetOuGuid, plan.NameReservation));
        queueVersion++;
        batches.Clear();
        Log($"File live : {plan.Computer} → {plan.NewName} ({plan.Kind}) ajouté ; ligne liée à l’aperçu et au GUID observés, aucune écriture.");
        return QueueList();
    }

    private JsonObject QueueList() => Resp.Obj(
        ("items", Resp.Arr(queue, q => Resp.Obj(
            ("id", q.Id), ("kind", q.Kind), ("computer", q.Computer), ("newName", q.NewName), ("targetOU", q.TargetOu), ("status", q.Status)))),
        ("count", queue.Count));

    private JsonObject QueueRemove(JsonElement args)
    {
        var id = Arguments.Text(args, "id", true);
        var index = queue.FindIndex(q => q.Id == id);
        if (index < 0) throw new PestoException("queue.missing", "Cette ligne ne figure plus dans la file.");
        ReleaseUnusedPreviewName(queue[index].NameReservation);
        queue.RemoveAt(index);
        queueVersion++;
        batches.Clear();
        return QueueList();
    }

    /// <summary>
    /// Préparation du lot, sans écriture : chaque ligne est relue contre l'annuaire (GUID revérifié, nom toujours
    /// libre, destination toujours un OU observé) puis un plan live est reforgé pour elle (expiration, confirmation
    /// exacte). Le lot enregistre la version de la file : toute modification après préparation rend le lot refusé.
    /// </summary>
    private JsonObject QueuePrepare(JsonElement args)
    {
        Arguments.Only(args, "pilot");
        var pilot = Arguments.Flag(args, "pilot");
        if (queue.Count == 0) throw new PestoException("queue.empty", "Ajoutez au moins un poste à la file.");
        var sources = queue.Select(q => q.Computer).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (queue.Any(q => q.Kind != "move" && !q.NewName.Equals(q.Computer, StringComparison.OrdinalIgnoreCase) && sources.Contains(q.NewName)))
            throw new PestoException("queue.dependent", "Les chaînes et cycles de renommage ne sont pas admis : un nom cible est aussi la source d’une autre ligne. Séparez les interventions et contrôlez leurs reçus.");
        var read = RequireConfig();
        var adapter = RequireGateway();
        var policy = Policy(read);
        if (queue.Count > Math.Min(read.MaxBatch, policy.ManagedMaxBatch ?? read.MaxBatch))
            throw new PestoException("queue.limit", "La limite de lot a été réduite par la politique : retirez des lignes avant de préparer.");
        var now = clock.GetUtcNow();
        var batch = new LiveBatch
        {
            BatchId = "batch-" + (++serial).ToString(System.Globalization.CultureInfo.InvariantCulture),
            ExpiresAt = now.AddMinutes(PlanMinutes),
            QueueVersion = queueVersion,
            Pilot = pilot,
        };
        foreach (var item in pilot ? queue.Take(1) : queue)
        {
            policy.AssertPlan(item.Kind, item.Computer, item.NewName, item.SourceOu, item.TargetOu, GetConvention(read));
            VerifyPreviewName(read, policy, item.Kind, item.NewName, item.NameReservation, configStamp!);
            var found = adapter.FindComputer(read.Domain, DcOrNull(), item.Computer)
                ?? throw new PestoException("computer.missing", $"La ligne « {item.Computer} » n’a plus été relue dans l’annuaire : retirez la ligne, puis re-préparez le lot.");
            if (!string.Equals(found.Guid, item.Guid, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("identity.changed", $"L’identité du poste « {item.Computer} » a changé depuis son ajout : retirez la ligne, reprenez par un nouvel aperçu, puis re-préparez.");
            if (!WithinScope(found.Ou, read.RootOu) || !string.Equals(found.Ou, item.SourceOu, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("source.changed", "L’OU source d’une ligne a changé ou sort du périmètre : re-préparez la ligne après inspection.");
            RequireGroupExclusions(read, policy, item.Guid, item.Computer, item.SourceOu);
            if (item.Kind != "move")
            {
                var taken = adapter.FindComputer(read.Domain, DcOrNull(), item.NewName);
                if (taken is not null && !string.Equals(taken.Guid, item.Guid, StringComparison.OrdinalIgnoreCase))
                    throw new PestoException("name.taken", $"Le nom « {item.NewName} » de la ligne « {item.Computer} » vient d’être pris : aucun ajout automatique. Retirez la ligne, calculez un nouvel aperçu, puis re-préparez.");
            }
            var preservesObservedOu = item.Kind == "rename" && string.Equals(found.Ou, item.TargetOu, StringComparison.OrdinalIgnoreCase)
                && WithinScope(item.TargetOu, read.RootOu);
            if (!preservesObservedOu && !ResolveSites(read, adapter).Any(s => string.Equals(s.Ou, item.TargetOu, StringComparison.OrdinalIgnoreCase)))
                throw new PestoException("site.invalid", $"La destination « {item.TargetOu} » de la ligne « {item.Computer} » n’est plus un OU observé dans l’annuaire : re-préparez après vérification.");
            if (item.Kind is "move" or "renameMove"
                && !string.Equals(ResolveTargetGuid(read, adapter, item.TargetOu), item.TargetOuGuid, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("destination.changed", "Le GUID de l’OU cible d’une ligne a changé : aucune exécution préparée.");
            var steps = new List<Step>
            {
                new("Vérifier l’identité", item.Computer),
                new(item.Kind == "move" ? "Déplacer le compte" : "Appliquer le nom confirmé", item.Kind == "move" ? item.TargetOu : item.NewName),
            };
            if (item.Kind == "renameMove") steps.Add(new("Vérifier le placement", item.TargetOu));
            var entra = PrepareEntraPlan(item.Kind, item.Computer, item.Guid, item.NewName, read.Domain, item.SourceOu, configStamp!);
            if (entra?.LeaveRequired == true) steps.Insert(1, new("Retrait Entra explicitement confirmé", item.Computer));
            var plan = new LivePlan
            {
                PlanId = "plan-" + (++serial).ToString(System.Globalization.CultureInfo.InvariantCulture),
                Kind = item.Kind,
                Computer = item.Computer,
                NewName = item.NewName,
                TargetOu = item.TargetOu,
                ExpiresAt = ExpiresWithEntra(ExpiresWithNameLease(now.AddMinutes(PlanMinutes), item.NameReservation), entra),
                ConfirmationName = item.NewName.Length > 0 ? item.NewName : item.Computer,
                ConfigurationSha256 = configStamp ?? throw new PestoException("config.changed", "Empreinte de configuration absente : préparez à nouveau."),
                Guid = item.Guid,
                SourceOu = item.SourceOu,
                TargetOuGuid = item.TargetOuGuid,
                NameReservation = item.NameReservation,
                Entra = entra,
                Steps = steps,
                Warnings =
                [
                    "Réel : ce plan n’a encore rien écrit. L’exécution du lot exige une confirmation et revérifie chaque ligne avant son envoi.",
                    "Aucun redémarrage implicite. Un retrait Entra exige la confirmation séparée des postes hybrides de ce lot.",
                ],
            };
            if (mutation is IMutationPreparationDisclosure disclosure) plan.Warnings.AddRange(disclosure.PreparationNotes(item.Kind, item.Computer));
            plans[plan.PlanId] = plan;
            if (plan.ExpiresAt < batch.ExpiresAt) batch.ExpiresAt = plan.ExpiresAt;
            batch.Entries.Add((item.Id, plan.PlanId));
        }
        if (batch.ExpiresAt <= clock.GetUtcNow())
        {
            foreach (var entry in batch.Entries) plans.Remove(entry.PlanId);
            throw new PestoException("batch.stale", "Les premières preuves ont expiré pendant les diagnostics du lot. Préparez un lot plus petit ; aucun plan périmé n’est proposé à l’exécution.");
        }
        batches[batch.BatchId] = batch;
        Log($"Lot préparé : {batch.Entries.Count} plan(s) relus contre l’annuaire, séquentiels, exécution unique.");
        var batchWarnings = new List<string>
        {
            "Le lot s’exécute une seule fois, dans l’ordre affiché, et s’arrête à la première ligne refusée ou incertaine. Une acceptation en attente de redémarrage conserve son reçu et permet la cible indépendante suivante ; aucun redémarrage implicite.",
            "Chaque envoi passe par le même pipeline qu’une opération unitaire : identité et disponibilité relues juste avant envoi, reçu écrit avant l’envoi, relecture annuaire après.",
            "La préparation n’écrit rien. Le lot confirmé est exécuté séquentiellement ; un refus ou résultat incertain arrête les lignes suivantes.",
        };
        if (batch.Pilot) batchWarnings.Insert(0, "Mode pilote : seule la première ligne est préparée et pourra être envoyée. Les autres lignes restent dans la file ; leur exécution exigera une nouvelle préparation et confirmation.");
        // Port du control summary V1 de la confirmation de file (Pesto-Core.ps1:4035) : note rendue seulement si
        // l'adaptateur injecté la déclare, et seulement si le lot contient au moins un renommage (seul chemin du repli V1).
        if (batch.Entries.Any(e => plans[e.PlanId].Kind is "rename" or "renameMove")) batchWarnings.AddRange(FallbackNotes(batch: true));
        if (mutation is IMutationPreparationDisclosure batchDisclosure)
            batchWarnings.AddRange(batch.Entries.SelectMany(e => batchDisclosure.PreparationNotes(plans[e.PlanId].Kind, plans[e.PlanId].Computer)).Distinct(StringComparer.Ordinal));
        return Resp.Obj(
            ("batchId", batch.BatchId),
            ("pilot", batch.Pilot),
            ("remainingCount", queue.Count - batch.Entries.Count),
            ("items", Resp.Arr(batch.Entries, e => PlanNode(plans[e.PlanId]))),
            ("expiresAt", Iso(batch.ExpiresAt)),
            ("warnings", Resp.Arr(batchWarnings, w => (JsonNode?)Resp.Node(w))));
    }

    /// <summary>
    /// Exécution du lot : séquentielle, une seule fois, sous le verrou du moteur (mutations sérialisées, une ligne à la
    /// fois). Chaque ligne part par le pipeline d'envoi unitaire ; la première ligne refusée ou incertaine
    /// arrête le lot ; une cible indépendante acceptée en attente de redémarrage ne bloque pas la suivante. Sans adaptateur injecté, refus
    /// <c>write.unavailable</c> avant toute consommation : rien ne quitte le processus, le lot reste intact pour la
    /// qualification. Un lot envoyé ne rejoue jamais.
    /// </summary>
    private JsonObject QueueExecute(JsonElement args, CancellationToken cancellationToken)
    {
        Arguments.Only(args, "batchId", "confirmed", "entraLeaveConfirmed");
        var batch = batches.GetValueOrDefault(Arguments.Text(args, "batchId", true))
            ?? throw new PestoException("batch.stale", "Ce lot n’existe plus : re-préparez un aperçu du lot.");
        if (!Arguments.Flag(args, "confirmed")) throw new PestoException("confirmation.invalid", "Le lot doit être confirmé explicitement.");
        if (batch.Used || batch.QueueVersion != queueVersion || batch.ExpiresAt <= clock.GetUtcNow())
            throw new PestoException("batch.stale", "Le lot a changé, a expiré ou a déjà été envoyé : re-préparez un aperçu ; rien n’est rejoué automatiquement.");
        if (mutation is null) throw new PestoException("write.unavailable", WriteUnavailable);

        var entraLeaveConfirmed = Arguments.Flag(args, "entraLeaveConfirmed");
        if (batch.Entries.Any(e => plans[e.PlanId].Entra?.LeaveRequired == true) && !entraLeaveConfirmed)
            throw new PestoException("entra.confirmation", "Confirmez explicitement les retraits Entra affichés dans le lot ; aucune ligne envoyée.");

        var read = RequireConfig();
        RequireUnchangedConfiguration();
        Policy(read).RequireSupported("queue");
        if (batch.Entries.Count > MaximumBatch(read))
            throw new PestoException("queue.limit", "La limite de lot a changé depuis la préparation : aucune ligne envoyée.");
        batch.Used = true;
        var applied = new List<JsonObject>();
        var reason = "";
        foreach (var (itemId, planId) in batch.Entries)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                reason = "Arrêt demandé : la ligne engagée a terminé et son reçu est conservé. Les lignes non engagées restent dans la file ; aucune reprise automatique.";
                break;
            }
            var plan = plans[planId];
            JsonObject receipt;
            try
            {
                receipt = ExecutePlan(plan, plan.ConfirmationName, entraLeaveConfirmed);
            }
            catch (PestoException refusal)
            {
                reason = refusal.Message + " La ligne reste dans la file : retirez-la ou reprenez-la par un nouvel aperçu.";
                break;
            }
            applied.Add(receipt);
            var index = queue.FindIndex(q => q.Id == itemId);
            if (index >= 0) queue.RemoveAt(index);
            queueVersion++;
            var status = receipt["status"]!.GetValue<string>();
            if (status is not ("succeeded" or "pendingRestart"))
            {
                reason = $"Arrêt à la ligne « {plan.Computer} » : statut « {status} ». Les lignes non tentées restent dans la file ; rien n’est rejoué automatiquement.";
                break;
            }
        }
        var pilotCompleted = batch.Pilot && applied.Count == 1 && reason.Length == 0;
        if (pilotCompleted && queue.Count > 0)
            reason = "Mode pilote terminé : une seule ligne a été envoyée. Les autres restent dans la file ; vérifiez le reçu puis préparez et confirmez un nouveau lot. Aucun redémarrage ni reprise automatique.";
        Log($"Lot {batch.BatchId} : {applied.Count} reçu(s), {(reason.Length > 0 ? "arrêté avant la fin" : "terminé")}.", reason.Length > 0 ? "warn" : "info");
        return Resp.Obj(
            ("receipts", Resp.Arr(applied, r => (JsonNode?)r)),
            ("pilot", batch.Pilot), ("pilotCompleted", pilotCompleted), ("remainingCount", queue.Count),
            ("stopped", reason.Length > 0),
            ("reason", reason.Length > 0 ? reason : null));
    }

    /// <summary>
    /// Historique des reçus (constat 4 de la revue) : la liste relit à chaque appel le registre durable GP (Interventions V1
    /// et reçus durables de l'adaptateur, ports de Get-PestoInterventionCatalogue/Read-PestoIntervention) et le fusionne avec
    /// les reçus de la session, sans effacement ni fusion arbitraire. Un fichier illisible est isolé sous son nom de fichier,
    /// « Aucun verrou levé », jamais ignoré ni présenté comme un reçu ; la borne d'affichage v1 (5 000 fichiers) est annoncée.
    /// </summary>
    private JsonObject ReceiptsList(JsonElement args)
    {
        var query = Arguments.Text(args, "query").ToLowerInvariant();
        var history = GpHistory.Read(gpRoot);
        var items = MergedReceipts(history).Where(m => $"{m.Receipt.Computer} {m.Receipt.NewName} {m.Receipt.Status} {m.Receipt.Id} {m.Receipt.Message}".ToLowerInvariant().Contains(query));
        return Resp.Obj(
            ("items", Resp.Arr(items, m => ReceiptWithRestartInfo(m.Receipt, m.Acknowledged))),
            ("invalidCount", history.InvalidCount),
            ("truncated", history.Truncated),
            ("persistent", history.Available ? GpHistory.Source : history.Reason));
    }

    private JsonObject ReceiptsGet(JsonElement args)
    {
        var id = Arguments.Text(args, "id", true);
        if (receipts.FirstOrDefault(r => r.Id.Equals(id, StringComparison.OrdinalIgnoreCase)) is { } session)
            return ReceiptWithRestartInfo(session);
        // Reçu durable relu sur disque (après redémarrage, le reçu de l'adaptateur reste consultable sans être rejoué).
        var history = GpHistory.Read(gpRoot);
        var entry = history.Entries.FirstOrDefault(e => e.Readable && e.Receipt.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
        return entry is not null ? ReceiptWithRestartInfo(entry.Receipt, entry.Acknowledged)
            : throw new PestoException("receipt.missing", "Ce reçu n’existe ni dans cette session ni dans le registre durable relu.");
    }

    private JsonObject ReceiptsPrepareMove(JsonElement args)
    {
        MutationSessionGuard.RequireWritableSession();
        Arguments.Only(args, "id");
        var id = Arguments.Text(args, "id", true, 128);
        if (CapabilityBlockReason("move") is { } unavailable)
            throw new PestoException("write.unavailable", unavailable);
        if (mutation is not IMutationMoveContinuation continuation)
            throw new PestoException("receipt.prepareMove_unavailable", "L’adaptateur ne permet pas de préparer le déplacement restant de ce reçu.");
        var read = RequireConfig();
        RequireUnchangedConfiguration();
        var adapter = RequireGateway();
        var planId = "plan-" + (++serial).ToString(System.Globalization.CultureInfo.InvariantCulture);
        var prepared = continuation.PrepareMoveContinuation(id, planId);
        var e = prepared.Observation;
        var a = prepared.Authorization;
        if (e.Receipt.Id != id || e.Receipt.Kind != "renameMove" || e.Receipt.Code != 89
            || e.Receipt.Status is not ("pendingRestart" or "uncertain") || e.Receipt.ResolutionChildReceiptId is not null)
            throw new PestoException("receipt.prepareMove_ineligible", "Seul un renommage-déplacement partiel de code 89 sans résolution peut préparer son déplacement restant.");
        // The rename must be fully observed after reboot while the object is still in the original OU.
        var proof = e with { Receipt = e.Receipt with { TargetOU = e.InitialOu ?? "" } };
        if (ReconciliationBlockReason(proof, allowPartialRenameProof: true) is { } reason)
            throw new PestoException("receipt.prepareMove_evidence", reason);
        if (!string.Equals(e.Domain, read.Domain, StringComparison.OrdinalIgnoreCase)
            || !WithinScope(e.InitialOu, read.RootOu) || !WithinScope(e.Receipt.TargetOU, read.RootOu)
            || string.Equals(e.InitialOu, e.Receipt.TargetOU, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("receipt.prepareMove_scope", "Le déplacement restant n’est pas lié à deux OU distinctes de la racine gérée configurée.");
        if (a.ParentReceiptId != id || a.PlanId != planId || string.IsNullOrWhiteSpace(a.Token)
            || !Regex.IsMatch(a.ParentReceiptSha256, "^[A-Fa-f0-9]{64}$") || a.ParentReceiptSha256 != e.ReceiptSha256
            || a.ExpiresAt <= clock.GetUtcNow() || a.ExpiresAt > clock.GetUtcNow().AddMinutes(PlanMinutes)
            || !string.Equals(a.Computer, e.Receipt.NewName, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(a.ComputerGuid, e.ExpectedGuid, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(a.SourceOu, e.InitialOu, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(a.TargetOu, e.Receipt.TargetOU, StringComparison.OrdinalIgnoreCase)
            || !Guid.TryParse(a.TargetOuGuid, out var targetGuid) || targetGuid == Guid.Empty
            || !string.Equals(a.TargetOuGuid, prepared.ObservedTargetOuGuid, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("receipt.prepareMove_authorization", "L’autorisation bornée ne correspond pas au reçu, aux identités ou à son empreinte actuelle.");
        ValidateComputerName(a.Computer);
        var source = adapter.FindComputer(read.Domain, DcOrNull(), a.Computer);
        if (source is null || !string.Equals(source.Name, a.Computer, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(source.Guid, a.ComputerGuid, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(source.Ou, a.SourceOu, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("source.changed", "L’identité source a changé pendant la préparation du déplacement restant.");
        var target = ResolveObservedOu(read, adapter, a.TargetOu);
        Policy(read).AssertPlan("move", a.Computer, a.Computer, a.SourceOu, a.TargetOu, GetConvention(read));
        _ = NameReservations(Policy(read)); // A configured mutation coordinator must exist even for a remaining move.
        RequireGroupExclusions(read, Policy(read), a.ComputerGuid, a.Computer, a.SourceOu);
        if (!string.Equals(ResolveTargetGuid(read, adapter, target), a.TargetOuGuid, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("destination.changed", "L’identité de l’OU de destination a changé : aucun plan de reprise créé.");
        var plan = new LivePlan
        {
            PlanId = planId, Kind = "move", Computer = a.Computer, NewName = a.Computer, Guid = a.ComputerGuid,
            SourceOu = a.SourceOu, TargetOu = a.TargetOu, TargetOuGuid = a.TargetOuGuid,
            ExpiresAt = a.ExpiresAt, ConfirmationName = a.Computer, Continuation = a,
            ConfigurationSha256 = configStamp ?? throw new PestoException("config.changed", "Empreinte de configuration absente : préparez à nouveau."),
            Steps = [new("Vérifier le renommage après redémarrage", a.Computer), new("Déplacer seulement le compte existant", a.TargetOu)],
            Warnings = ["Déplacement restant lié au reçu " + id + ". Aucun renommage ni redémarrage n’est rejoué.",
                "Confirmation distincte requise ; identité, OU, empreinte du reçu et autres barrières sont revérifiées avant l’envoi."],
        };
        plans[plan.PlanId] = plan;
        var parentIndex = receipts.FindIndex(r => r.Id == id);
        if (parentIndex >= 0) receipts[parentIndex] = e.Receipt;
        else receipts.Insert(0, e.Receipt);
        Log($"Déplacement restant préparé pour le reçu {id} : {a.Computer} vers {a.TargetOu}, sans nouvelle commande de renommage.");
        return PlanNode(plan);
    }

    private JsonObject ReceiptsReconcile(JsonElement args)
    {
        Arguments.Only(args, "id");
        MutationSessionGuard.RequireWritableSession();
        var id = Arguments.Text(args, "id", true, 128);
        if (mutation is not IMutationReceiptReconciler reconciler)
            throw new PestoException("receipt.reconcile_unavailable", "L’adaptateur de ce poste ne permet pas la vérification d’un reçu réel.");
        var evidence = reconciler.ReadReconciliation(id);
        if (!evidence.Receipt.Id.Equals(id, StringComparison.Ordinal))
            throw new PestoException("receipt.identity", "Le reçu observé ne correspond pas à la demande : aucune modification.");
        if (evidence.Receipt.Status is not ("pendingRestart" or "uncertain"))
            throw new PestoException("receipt.not_reconcilable", "Seuls les reçus en attente de redémarrage ou à vérifier peuvent être vérifiés par cette action.");
        var reason = ReconciliationBlockReason(evidence);
        if (reason is not null)
        {
            var blocked = ReceiptNode(evidence.Receipt);
            blocked["verified"] = false;
            blocked["reason"] = reason;
            Log($"Vérification explicite du reçu {id} : preuves insuffisantes, statut conservé.", "warn");
            return blocked;
        }
        MutationSessionGuard.RequireWritableSession();
        try { reconciler.PersistReconciliation(evidence); }
        catch (Exception)
        {
            throw new PestoException("receipt.reconcile_persistence", "La vérification n’a pas pu être enregistrée ou le reçu a changé : statut conservé, aucune relance de l’opération.");
        }
        var verified = evidence.Receipt with { Status = "succeeded", RestartRequired = false,
            Message = "État final confirmé par vérification explicite : identité AD, nom, placement et état Windows requis relus ; aucune commande de modification ni redémarrage exécutés." };
        var index = receipts.FindIndex(r => r.Id == id);
        if (index >= 0) receipts[index] = verified;
        else receipts.Insert(0, verified);
        if (verified.Kind == "move" && verified.ParentReceiptId is { } parentId)
        {
            var parentIndex = receipts.FindIndex(r => r.Id == parentId);
            if (parentIndex >= 0) receipts[parentIndex] = receipts[parentIndex] with
                { Status = "uncertain", RestartRequired = false, ResolutionChildReceiptId = verified.Id };
        }
        Log($"Reçu {id} vérifié explicitement ; aucune mutation rejouée.");
        var result = ReceiptNode(verified);
        result["verified"] = true;
        result["reason"] = null;
        return result;
    }

    private static string? ReconciliationBlockReason(ReceiptReconciliationObservation e, bool allowPartialRenameProof = false)
    {
        if (!allowPartialRenameProof && e.Receipt.Kind == "renameMove" && e.Receipt.Code == 89)
            return e.Receipt.ResolutionChildReceiptId is null
                ? "Ce reçu conserve son résultat partiel de code 89. Préparez explicitement le déplacement restant après vérification du redémarrage."
                : "Ce reçu conserve son résultat partiel de code 89 ; consultez le reçu du déplacement qui le résout.";
        if (!string.IsNullOrWhiteSpace(e.Error)) return "Observation incomplète : " + Safe(e.Error) + " Le reçu et sa barrière sont conservés.";
        if (e.Receipt.Kind is not ("join" or "rename" or "move" or "renameMove")) return "Type de reçu non pris en charge : vérification manuelle nécessaire.";
        if (!Guid.TryParse(e.ExpectedGuid, out var expected) || expected == Guid.Empty || !Guid.TryParse(e.AdGuid, out var actual) || actual != expected)
            return "Le GUID AD attendu n’est pas confirmé : le reçu reste bloquant.";
        var desiredName = e.Receipt.Kind == "move" ? e.Receipt.Computer : e.Receipt.NewName;
        if (string.IsNullOrWhiteSpace(desiredName) || !string.Equals(e.AdName, desiredName, StringComparison.OrdinalIgnoreCase))
            return "Le nom AD final n’est pas confirmé : le reçu reste bloquant.";
        var desiredOu = e.Receipt.Kind == "rename" ? e.InitialOu : e.Receipt.TargetOU;
        if (string.IsNullOrWhiteSpace(desiredOu) || !string.Equals(e.AdOu, desiredOu, StringComparison.OrdinalIgnoreCase))
            return "Le placement AD final n’est pas confirmé : le reçu reste bloquant.";
        if (e.Receipt.Kind is "move" or "renameMove" && (e.InitialProtected is null || e.AdProtected is null || e.InitialProtected != e.AdProtected))
            return "La protection AD d’origine n’est pas confirmée : le reçu reste bloquant.";
        if (e.Receipt.Kind != "move")
        {
            if (ReceiptWindowsEvidence.IdentityRefusal(e) is { } identityRefusal) return identityRefusal;
            if (e.InitialBootUtc is null || e.CurrentBootUtc is null || e.CurrentBootUtc <= e.InitialBootUtc)
                return "Aucun démarrage postérieur à l’opération n’est prouvé : le reçu reste en attente.";
            if (!string.Equals(e.WindowsActiveName, desiredName, StringComparison.OrdinalIgnoreCase)
                || !string.Equals(e.WindowsConfiguredName, desiredName, StringComparison.OrdinalIgnoreCase))
                return "Le nom actif et le nom configuré Windows ne concordent pas avec le nom demandé.";
            if (string.IsNullOrWhiteSpace(e.Domain) || e.WindowsPartOfDomain != true
                || !string.Equals(e.WindowsDomain, e.Domain, StringComparison.OrdinalIgnoreCase) || e.SecureChannel != true)
                return "Le domaine Windows et son canal sécurisé ne sont pas tous deux confirmés : le reçu reste bloquant.";
        }
        return null;
    }

    private JsonObject LogsList(JsonElement args)
    {
        var query = Arguments.Text(args, "query").ToLowerInvariant();
        var level = Arguments.Text(args, "level");
        var items = logs.Where(l => (level.Length == 0 || l.Level == level) && l.Message.ToLowerInvariant().Contains(query));
        return Resp.Obj(("items", Resp.Arr(items, l => Resp.Obj(("id", l.Id), ("time", Iso(l.Time)), ("level", l.Level), ("message", l.Message)))));
    }

    private static JsonObject ReceiptNode(Receipt r, bool acknowledged = false) => Resp.Obj(
        ("id", r.Id),
        ("time", r.Status == "unreadable" ? null : Iso(r.Time)), // un fichier illisible n'a pas de date lue : null, jamais 1970
        ("kind", r.Kind), ("computer", r.Computer), ("newName", r.NewName),
        ("targetOU", r.TargetOU), ("mode", r.Mode), ("status", r.Status), ("code", r.Code.ToString(System.Globalization.CultureInfo.InvariantCulture)),
        ("message", r.Message), ("restartRequired", r.RestartRequired),
        ("readable", r.Status != "unreadable"), ("acknowledged", acknowledged),
        ("parentReceiptId", r.ParentReceiptId), ("resolutionChildReceiptId", r.ResolutionChildReceiptId));

    private void Log(string message, string level = "info") => logs.Insert(0, new LogEntry("log-" + (++serial).ToString(System.Globalization.CultureInfo.InvariantCulture), clock.GetUtcNow(), level, message));

    /// <summary>Message de l'adaptateur réduit et sans caractère de contrôle : aucun secret ne remonte tel quel dans les retours.</summary>
    private static string Safe(string? message)
    {
        if (string.IsNullOrWhiteSpace(message)) return "";
        var trimmed = new string(message.Where(c => !char.IsControl(c)).ToArray());
        return trimmed.Length > 300 ? trimmed[..300] + "…" : trimmed;
    }

    private string ResolveTargetGuid(V1Config read, IDirectoryGateway adapter, string targetOu)
    {
        if (!WithinScope(targetOu, read.RootOu)) throw new PestoException("site.invalid", "L’OU cible sort de la racine gérée.");
        var observed = adapter.FindOrganizationalUnit(read.Domain, DcOrNull(), targetOu);
        if (observed is null || !string.Equals(observed.DistinguishedName, targetOu, StringComparison.OrdinalIgnoreCase)
            || !Guid.TryParse(observed.Guid, out var guid) || guid == Guid.Empty)
            throw new PestoException("destination.missing", "L’identité GUID exacte de l’OU cible n’est pas confirmée : aucune préparation ni commande envoyée.");
        return observed.Guid;
    }

    private string ResolveObservedOu(V1Config read, IDirectoryGateway adapter, string target)
    {
        var resolved = ResolveSites(read, adapter).FirstOrDefault(s =>
            new[] { s.Id, s.Name, s.Code, s.Ou }.Contains(target, StringComparer.OrdinalIgnoreCase))
            ?? throw new PestoException("site.invalid", "La destination doit être un site réellement observé dans l’annuaire : aucun OU non observé n’est admis.");
        if (!WithinScope(resolved.Ou, read.RootOu))
            throw new PestoException("site.invalid", "L’OU du site cible est hors de la racine gérée configurée : déplacement refusé dans une portée non gérée.");
        return resolved.Ou;
    }

    private static void ValidateComputerName(string name)
    {
        if (!Regex.IsMatch(name, @"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$"))
            throw new PestoException("invalid_arguments", "Nom d’ordinateur invalide (1 à 15 caractères alphanumériques ou tirets, sans tiret en tête ni en fin).");
    }

    private sealed record Step(string Label, string Detail);

    private static string? Optional(JsonElement args, string name) =>
        args.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? NullIfEmpty(value.GetString()!.Trim()) : null;
    private static string? NullIfEmpty(string value) => value.Length == 0 ? null : value;

    // ---- guards ---------------------------------------------------------------------

    private void RefreshConfigurationIfChanged()
    {
        if (!configLoaded) return;
        string? stamp = null;
        try { if (ConfigPathOf() is { } path && File.Exists(path)) stamp = Stamp(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        // A new profile has no cfg yet; a removed cfg must invalidate a previously loaded one.
        // Keep the missing fingerprint null without hiding other resolver failures or relaxing send guards.
        catch (PestoException error) when (error.Code == "config.missing") { }
        if (stamp == configStamp) return;
        InvalidateDerivedState();
        configLoaded = false;
        config = null;
        configError = null;
        configStamp = null;
        dcDiscovered = false;
        discoveredDc = null;
    }

    private V1Config RequireConfig()
    {
        if (!configLoaded)
        {
            configLoaded = true;
            try
            {
                config = V1Config.Load(v1InstallationPath, out var loadedStamp);
                configStamp = loadedStamp;
            }
            catch (PestoException error) { configError = error; }
        }
        if (config is null) throw configError ?? new PestoException("config.missing", "Configuration V1 indisponible.");
        return config;
    }

    /// <summary>La convention lue commande génération et analyse inverse ; elle est reconstruite dès que la configuration change.</summary>
    private NamingConvention GetConvention(V1Config read)
    {
        if (!ReferenceEquals(conventionCacheOwner, read))
        {
            conventionCache = read.BuildConvention();
            conventionCacheOwner = read;
        }
        return conventionCache!;
    }

    private void RequireUnchangedConfiguration()
    {
        var unchanged = false;
        try { unchanged = ConfigPathOf() is { } path && configStamp is not null && File.Exists(path) && Stamp(path) == configStamp; }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        catch (PestoException) { }
        if (unchanged) return;
        InvalidateDerivedState();
        configLoaded = false;
        config = null;
        configError = null;
        configStamp = null;
        dcDiscovered = false;
        discoveredDc = null;
        throw new PestoException("config.changed", "cfg.json a changé depuis la préparation : aucune commande envoyée. Rechargez la configuration, recalculez le nom et confirmez un nouveau plan.");
    }

    private string? ConfigPathOf() => V1Config.ConfigPathOf(v1InstallationPath);

    /// <summary>Empreinte SHA-256 du cfg.json (port de Get-PestoConfigFileStamp v1) : garde de concurrence avant écriture.</summary>
    private static string Stamp(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(stream)).ToLowerInvariant();
    }

    private V1Config? ConfigOrNull()
    {
        try { return RequireConfig(); }
        catch (PestoException) { return null; }
    }

    private IDirectoryGateway RequireGateway() => gateway
        ?? throw new PestoException("directory.unavailable",
            "Aucun adaptateur annuaire actif sur ce poste : les lectures AD sont refusées plutôt que simulées. L’adaptateur transitoire exige Windows PowerShell 5.1 et le module ActiveDirectory.");

    private string? DcOrNull()
    {
        var read = ConfigOrNull();
        if (read is null || gateway is null) return null;
        if (!dcDiscovered)
        {
            dcDiscovered = true;
            try { discoveredDc = gateway.DiscoverDomainController(read.Domain); }
            catch (PestoException) { discoveredDc = null; }
        }
        return discoveredDc;
    }

    /// <summary>Suffixe de DN comparé composant par composant (port de Test-PestoDNWithinScope v1).</summary>
    private static bool WithinScope(string? distinguishedName, string root)
    {
        var parts = Split(distinguishedName);
        var roots = Split(root);
        if (parts is null || roots is null || parts.Length < roots.Length) return false;
        var offset = parts.Length - roots.Length;
        for (var i = 0; i < roots.Length; i++)
            if (!string.Equals(parts[i + offset], roots[i], StringComparison.OrdinalIgnoreCase)) return false;
        return true;
    }

    private static string[]? Split(string? dn)
    {
        if (string.IsNullOrWhiteSpace(dn)) return null;
        var parts = new List<string>();
        var current = new StringBuilder();
        for (var i = 0; i < dn.Length; i++)
        {
            var c = dn[i];
            if (c == '\\' && i + 1 < dn.Length) { current.Append(c).Append(dn[++i]); continue; }
            if (c == ',') { parts.Add(current.ToString()); current.Clear(); continue; }
            current.Append(c);
        }
        parts.Add(current.ToString());
        return parts.All(p => Regex.IsMatch(p, @"^(?i:OU|CN|DC)=(?:\\.|[^\\])+$")) ? parts.ToArray() : null;
    }

    private static string EscapeRdn(string value)
    {
        var builder = new StringBuilder();
        for (var i = 0; i < value.Length; i++)
        {
            var c = value[i];
            var requiresEscape = c is ',' or '+' or '"' or '\\' or '<' or '>' or ';' or '='
                || ((c == ' ' || c == '#') && (i == 0 || i == value.Length - 1));
            if (requiresEscape) builder.Append('\\');
            builder.Append(c);
        }
        return builder.ToString();
    }

    private string DirectoryAccount() => gateway is IDirectoryAccountDisclosure { SelectedAccount: { } account } && !string.IsNullOrWhiteSpace(account)
        ? account : ObservedAccount();

    private static string ObservedAccount()
    {
        var domain = Environment.UserDomainName;
        var user = Environment.UserName;
        return string.IsNullOrEmpty(domain) || domain.Equals(user, StringComparison.OrdinalIgnoreCase) ? user : domain + "\\" + user;
    }
}
