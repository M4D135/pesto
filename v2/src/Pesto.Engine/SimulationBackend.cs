using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>
/// Authoritative in-memory engine used by the labelled simulation. It owns every validation, plan, identity and receipt.
/// Nothing here reaches AD, the disk, WMI or the network: the whole world lives in this instance and is clearly announced
/// as a simulation in every receipt and diagnostic.
/// </summary>
internal sealed class SimulationBackend(TimeProvider clock) : IPestoBackend, IDisposable
{
    private static readonly string[] Kinds = ["join", "rename", "move", "renameMove"];
    private static readonly Service[] Services = [new("INF", "Informatique"), new("ADM", "Administration"), new("LOG", "Logistique")];
    private static readonly DemoScenario[] Scenarios =
    [
        new("standard", "Nouveau poste", "Calculez un nom puis joignez le poste fictif au domaine. Le redémarrage reste explicite.", "ajouter"),
        new("joined", "Poste déjà joint", "Renommez un poste, changez de site ou préparez un lot de postes fictifs.", "unposte"),
        new("pendingRestart", "Redémarrage en attente", "Un renommage fictif est accepté. Le bouton Redémarrage fictif termine uniquement la simulation.", "interventions"),
        new("partialMove", "Déplacement restant", "Le renommage fictif a réussi mais le déplacement attend. Redémarrez fictivement puis préparez le déplacement restant.", "interventions"),
        new("denied", "Droits insuffisants", "La prochaine écriture confirmée sera refusée, sans changement du poste fictif.", "unposte"),
        new("uncertain", "Résultat incertain", "La prochaine écriture rendra un reçu incertain et arrêtera le lot. Aucun redémarrage ne transforme cet état en succès.", "plusieurspostes"),
        new("nameCollision", "Nom pris entre deux étapes", "Le nom de l’aperçu devient occupé à la préparation. Un nouvel aperçu et une nouvelle confirmation sont nécessaires.", "ajouter"),
        new("directoryOffline", "Annuaire indisponible", "Les lectures fictives échouent explicitement. Aucun compteur ou nom disponible n’est inventé.", "accueil"),
    ];

    private readonly object gate = new();
    private readonly TimeProvider clock = clock;
    private readonly Random random = new();
    private readonly Dictionary<string, Preview> previews = [];
    private readonly Dictionary<string, Plan> plans = [];
    private readonly Dictionary<string, Batch> batches = [];
    private readonly Dictionary<string, string> alternatives = [];
    private readonly List<Computer> computers = SeedComputers();
    private readonly List<QueueItem> queue = [];
    private readonly List<Receipt> receipts = [];
    private readonly List<LogEntry> logs = [];
    private readonly string instanceId = Guid.NewGuid().ToString("N");

    private PestoSettings settings = PestoSettings.Demo;
    private LocalMachine local = new();
    private long serial;
    private long revision;
    private int queueVersion;
    private int generation;
    private string scenario = "standard";
    private string? nextOutcome;
    private bool disposed;

    public Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (gate)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (disposed) throw new PestoException("demo.closed", "Cette démonstration est fermée.");
            // This check is part of the engine API, not merely the UI. Never delegate a demo call to an I/O service.
            if (operation.StartsWith("updates.", StringComparison.Ordinal) || operation.StartsWith("configuration.", StringComparison.Ordinal)
                || operation.StartsWith("references.", StringComparison.Ordinal) || operation.StartsWith("coordination.", StringComparison.Ordinal)
                || operation.StartsWith("reservations.", StringComparison.Ordinal) || operation == "host.reconnect"
                || operation.StartsWith("attributes.", StringComparison.Ordinal) || operation.StartsWith("offlineJoin.", StringComparison.Ordinal)
                || operation is "join.precreated.preview" or "receipts.prepareAcknowledgement" or "receipts.acknowledge"
                    or "receipts.prepareRestart" or "receipts.restart")
                throw new PestoException("demo.isolated", "La démonstration ne lit aucun fichier réel, partage, site HTTP ni configuration utilisateur.");
            if (scenario == "directoryOffline" && (operation.StartsWith("directory.", StringComparison.Ordinal)
                || operation is "computer.inspect" or "names.preview" or "operation.prepare"))
                throw new PestoException("directory.unavailable", "Scénario fictif : annuaire indisponible. Aucune connexion réseau n’a été tentée.");
            object? result = operation switch
            {
                "demo.status" => DemoStatus(),
                "demo.reset" => DemoReset(args),
                "demo.scenario" => DemoSelectScenario(args),
                "demo.restart" => DemoRestart(args),
                "demo.prepareMove" => DemoPrepareMove(args),
                "demo.open" => throw new PestoException("demo.alreadyOpen", "Cette fenêtre est déjà une démonstration isolée."),
                "session.info" => SessionInfo(),
                "dashboard.read" => Dashboard(),
                "directory.sites" => Resp.Obj(("items", Resp.Arr(settings.Sites, SiteNode))),
                "directory.services" => DirectoryServices(args),
                "directory.search" => DirectorySearch(args),
                "computer.inspect" => ComputerInspect(args),
                "names.preview" => NamesPreview(args),
                "operation.prepare" => OperationPrepare(args),
                "operation.execute" => OperationExecute(args),
                "queue.add" => QueueAdd(args),
                "queue.list" => QueueList(),
                "queue.remove" => QueueRemove(args),
                "queue.prepare" => QueuePrepare(args),
                "queue.execute" => QueueExecute(args),
                "receipts.list" => ReceiptsList(args),
                "receipts.get" => ReceiptsGet(args),
                "receipts.prepareMove" => throw new PestoException("receipt.prepareMoveSimulation", "La simulation ne peut pas préparer le déplacement restant d’un reçu réel."),
                "receipts.reconcile" => throw new PestoException("receipt.reconcileSimulation", "La simulation ne peut pas vérifier l’état réel d’un poste. Aucun reçu simulé n’est transformé en preuve réelle."),
                "logs.list" => LogsList(args),
                "settings.get" => SettingsNode(settings),
                "settings.save" => SettingsSave(args),
                "diagnostics.read" => Diagnostics(),
                _ => throw new PestoException("operation.unknown", "Cette opération n’est pas déclarée dans le pont Pesto."),
            };
            return Task.FromResult<object?>(result);
        }
    }

    // ---- identity and dashboard -------------------------------------------------

    private JsonObject SessionInfo() => Resp.Obj(
        ("version", EngineVersion.Current),
        ("mode", "simulation"),
        ("domain", settings.Domain),
        ("dc", settings.Dc.Length == 0 ? null : settings.Dc),
        ("account", "SIMULATION\\operateur.demo"),
        ("computer", local.Name),
        ("localJoined", local.Domain is not null),
        ("instanceId", instanceId), ("generation", generation), ("demoScenario", scenario),
        ("readOnly", false),
        ("capabilities", Resp.Arr<string>(["join", "rename", "move", "renameMove", "queue"],
            id => id == "join" && local.Domain is not null
                ? Resp.Obj(("id", id), ("enabled", false), ("reason", "Ce poste simulé a déjà rejoint le domaine."))
                : Resp.Obj(("id", id), ("enabled", true), ("reason", "Disponible dans la simulation en mémoire.")))));

    private JsonObject Dashboard() => Resp.Obj(
        ("computers", scenario == "directoryOffline" ? null : (int?)computers.Count),
        ("availableNames", null),
        ("pendingRestart", computers.Count(c => c.PendingRestart)),
        ("uncertain", receipts.Count(r => r.Status == "uncertain")),
        ("lastActivity", Resp.Arr(receipts.Take(5), ReceiptNode)),
        ("sites", Resp.Arr(settings.Sites, s => Resp.Obj(("name", s.Name), ("count", scenario == "directoryOffline" ? null : (int?)computers.Count(c => c.Site == s.Id))))));

    // ---- explicit demonstration controls (memory only) --------------------------

    private JsonObject DemoStatus() => Resp.Obj(
        ("mode", "simulation"), ("instanceId", instanceId), ("generation", generation), ("scenario", scenario),
        ("localComputer", local.Name), ("pendingRestart", computers.Count(c => c.PendingRestart)),
        ("page", Scenarios.Single(s => s.Id == scenario).Page),
        ("message", "Fenêtre de démonstration isolée. Aucun accès AD, SMB ou HTTP ; aucun changement réel."),
        ("scenarios", Resp.Arr(Scenarios, s => Resp.Obj(("id", s.Id), ("label", s.Label), ("description", s.Description), ("page", s.Page)))),
        ("remainingMoves", Resp.Arr(receipts.Where(r => r.Code == 89 && r.ResolutionChildReceiptId is null), r => Resp.Obj(
            ("id", r.Id), ("newName", r.NewName), ("targetOU", r.TargetOU), ("restartRequired", r.RestartRequired)))));

    private static void ConfirmDemo(JsonElement args, params string[] allowed)
    {
        Arguments.Only(args, allowed);
        if (!Arguments.Flag(args, "confirmed")) throw new PestoException("confirmation.invalid", "Confirmez explicitement cette action de démonstration.");
    }

    private JsonObject DemoReset(JsonElement args)
    {
        ConfirmDemo(args, "confirmed");
        ResetWorld("standard");
        return DemoStatus();
    }

    private JsonObject DemoSelectScenario(JsonElement args)
    {
        ConfirmDemo(args, "id", "confirmed");
        var id = Arguments.Text(args, "id", true, 40);
        if (!Scenarios.Any(s => s.Id == id)) throw new PestoException("demo.scenario", "Ce scénario de démonstration n’existe pas.");
        ResetWorld(id);
        return DemoStatus();
    }

    private void ResetWorld(string selected)
    {
        // No serial reset: old IDs can never designate a new operation, even under a frozen clock.
        revision++;
        generation++;
        queueVersion++;
        previews.Clear(); plans.Clear(); batches.Clear(); alternatives.Clear(); queue.Clear(); receipts.Clear(); logs.Clear();
        settings = PestoSettings.Demo;
        local = new LocalMachine();
        computers.Clear(); computers.AddRange(SeedComputers());
        scenario = selected;
        nextOutcome = selected is "denied" or "uncertain" or "nameCollision" ? selected : null;
        if (selected is "joined" or "pendingRestart" or "partialMove" or "denied" or "uncertain")
            local.Absorb(computers[0]);
        if (selected is "pendingRestart" or "partialMove")
        {
            var computer = computers[0];
            var oldName = computer.Name;
            var partial = selected == "partialMove";
            computer.Name = partial ? "P111301LYINF002" : "P111301PAINF002";
            computer.DnsName = computer.Name.ToLowerInvariant() + "." + settings.Domain;
            computer.PendingRestart = true;
            local.Absorb(computer);
            receipts.Add(new Receipt(NewId("receipt"), Now, partial ? "renameMove" : "rename", oldName, computer.Name,
                partial ? settings.Sites[1].Ou : computer.Ou, "simulation", "pendingRestart", partial ? 89 : 20,
                partial ? "Scénario fictif : renommage accepté, déplacement non tenté. L’OU initiale est conservée."
                    : "Scénario fictif : renommage accepté. Un redémarrage fictif reste à demander.", true));
        }
        Log("Démonstration remise à zéro : " + Scenarios.Single(s => s.Id == selected).Label + ". Aucun effet réel.");
    }

    private JsonObject DemoRestart(JsonElement args)
    {
        ConfirmDemo(args, "confirmed");
        var changed = computers.Where(c => c.PendingRestart).Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var computer in computers) computer.PendingRestart = false;
        local.PendingRestart = false;
        for (var i = 0; i < receipts.Count; i++)
        {
            var receipt = receipts[i];
            if (!receipt.RestartRequired || !changed.Contains(receipt.NewName) || receipt.Status == "uncertain") continue;
            receipts[i] = receipt with
            {
                RestartRequired = false,
                Status = receipt.Code == 89 ? receipt.Status : "simulated",
                Message = receipt.Code == 89
                    ? "Redémarrage fictif effectué ; le déplacement reste à préparer et confirmer. Le résultat partiel est conservé."
                    : "Redémarrage fictif effectué en mémoire. Aucun ordinateur réel n’a été redémarré.",
            };
        }
        // Any proposal from before the fictitious restart is stale, just as an observed machine change would be.
        revision++; previews.Clear(); plans.Clear(); batches.Clear(); queue.Clear(); queueVersion++;
        Log($"Redémarrage fictif de {changed.Count} poste(s) en mémoire. Les reçus incertains restent incertains.");
        return DemoStatus();
    }

    private JsonObject DemoPrepareMove(JsonElement args)
    {
        Arguments.Only(args, "id");
        var id = Arguments.Text(args, "id", true);
        var parent = receipts.FirstOrDefault(r => r.Id == id && r.Code == 89 && r.Mode == "simulation" && r.ResolutionChildReceiptId is null)
            ?? throw new PestoException("demo.receipt", "Choisissez un déplacement restant de cette démonstration.");
        var computer = ComputerOf(parent.NewName);
        if (computer.PendingRestart || parent.RestartRequired) throw new PestoException("demo.restartRequired", "Effectuez d’abord le redémarrage fictif.");
        var plan = PrepareFromArgs(PestoJson.Element(new { kind = "move", computer = parent.NewName, targetOU = parent.TargetOU }));
        plan.ParentReceiptId = parent.Id;
        return PlanNode(plan);
    }

    private JsonObject Diagnostics() => Resp.Obj(
        ("mode", "simulation"),
        ("checks", Resp.Arr<Check>([
            new("Interface", "ok", "Modules locaux chargés."),
            new("Moteur", "ok", "Simulation en mémoire, isolée des données réelles."),
            new("Active Directory", "unknown", "Aucun contact réseau depuis la simulation."),
        ], c => Resp.Obj(("label", c.Label), ("state", c.State), ("detail", c.Detail)))));

    // ---- directory reads --------------------------------------------------------

    private JsonObject DirectoryServices(JsonElement args)
    {
        _ = SiteOf(Arguments.Text(args, "site", true));
        return Resp.Obj(("items", Resp.Arr(Services, s => Resp.Obj(("code", s.Code), ("name", s.Name)))));
    }

    private JsonObject DirectorySearch(JsonElement args)
    {
        var query = Arguments.Text(args, "query", true).ToLowerInvariant();
        var limit = Arguments.Number(args, "limit", 50, 1, 100);
        var matches = computers.Where(c => new[] { c.Name, c.Site, c.Service, c.Os }.Any(v => v.ToLowerInvariant().Contains(query))).ToList();
        return Resp.Obj(
            ("items", Resp.Arr(matches.Take(limit), c => ComputerNode(c, null))),
            ("complete", matches.Count <= limit),
            ("collectedAt", Iso(Now)));
    }

    private JsonObject ComputerInspect(JsonElement args)
    {
        var computer = ComputerOf(Arguments.Text(args, "computer", true));
        var checks = new[]
        {
            new Check("Identité", "ok", "Poste de démonstration identifié en mémoire."),
            new Check("Canal sécurisé", "unknown", "Non mesuré : aucun réseau en simulation."),
        };
        var result = ComputerNode(computer, checks);
        result["inManagedScope"] = true; // The fictitious directory contains only its own managed computers.
        return result;
    }

    // ---- naming preview ---------------------------------------------------------

    private JsonObject NamesPreview(JsonElement args)
    {
        var type = Arguments.Text(args, "type", true);
        if (type is not ("P" or "S" or "V")) throw new PestoException("type.invalid", "Choisissez Portable, Fixe ou Virtuel.");
        var site = SiteOf(Arguments.Text(args, "site", true));
        var service = Arguments.Text(args, "service", true);
        if (!Services.Any(s => s.Code == service)) throw new PestoException("service.invalid", "Choisissez un service configuré.");
        var computerName = Optional(args, "computer");
        var alternative = Arguments.Flag(args, "alternative");

        var convention = new NamingConvention(settings.NamingPattern, settings.Prefix);
        var available = FreeNames(convention, type, site.Code, service);
        if (available.Count == 0) throw new PestoException("names.exhausted", "Aucun nom libre pour cette convention.");

        var key = string.Join('|', type, site.Id, service);
        var name = available[0];
        if (settings.RandomNames) name = available[random.Next(available.Count)];
        if (alternative && alternatives.TryGetValue(key, out var last) && last == name && available.Count > 1)
            name = available[(available.IndexOf(name) + 1) % available.Count];
        alternatives[key] = name;

        // A same-site rename keeps the account's existing (possibly deeper) OU; a change of site uses the site's OU.
        var current = computerName is null ? null : ComputerOf(computerName);
        var oldSite = current is null ? null : convention.TryParse(current.Name)?.Site;
        var ou = current is not null && string.Equals(oldSite, site.Code, StringComparison.OrdinalIgnoreCase) ? current.Ou : site.Ou;

        var now = Now;
        var preview = new Preview(NewId("preview"), name, ou, true, now, now.AddMinutes(5), available.Count, "simulation",
            revision, site.Id, service, current?.Name);
        previews[preview.PreviewId] = preview;
        Log($"Aperçu simulé calculé : {name}.");
        return Resp.Obj(
            ("previewId", preview.PreviewId), ("name", preview.Name), ("ou", preview.Ou), ("complete", preview.Complete),
            ("collectedAt", Iso(preview.CollectedAt)), ("expiresAt", Iso(preview.ExpiresAt)),
            ("availableCount", preview.AvailableCount), ("source", preview.Source));
    }

    private List<string> FreeNames(NamingConvention convention, string type, string siteCode, string service)
    {
        var free = new List<string>();
        for (var number = 1; number <= convention.Maximum; number++)
        {
            var candidate = convention.Format(type, siteCode, service, number);
            if (!Taken(candidate, null) && !queue.Any(q => q.NewName.Equals(candidate, StringComparison.OrdinalIgnoreCase)))
                free.Add(candidate);
        }
        return free;
    }

    // ---- prepare / execute ------------------------------------------------------

    private JsonObject OperationPrepare(JsonElement args)
    {
        if (receipts.Any(r => r.Status == "uncertain"))
            throw new PestoException("demo.uncertain", "Un résultat fictif est incertain. Aucun rejeu automatique : remettez la démonstration à zéro pour changer de scénario.");
        var kind = Arguments.Text(args, "kind", true);
        if (!Kinds.Contains(kind, StringComparer.Ordinal)) throw new PestoException("operation.kind", "Action non prise en charge.");
        var computerName = Optional(args, "computer");
        var newNameArg = Optional(args, "newName");
        var targetArg = Optional(args, "targetOU");

        if (kind == "join")
        {
            if (local.Domain is not null) throw new PestoException("join.alreadyJoined", "Le poste local simulé a déjà rejoint le domaine.");
            if (computerName is not null && !computerName.Equals(local.Name, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("join.localOnly", "La jonction concerne uniquement ce poste.");
        }
        else if (computerName is null)
        {
            throw new PestoException("invalid_arguments", "Le nom du poste est requis pour cette action.");
        }
        if (kind == "move" && targetArg is null)
            throw new PestoException("invalid_arguments", "L’OU de destination est requise pour un déplacement.");

        var computer = kind == "join" ? local.AsComputer() : ComputerOf(computerName!);
        var read = kind == "move" ? null : RequireFresh(PreviewOrNull(Optional(args, "previewId")), "L’aperçu du nom");
        if (read is not null && newNameArg is not null && !newNameArg.Equals(read.Name, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("preview.changed", "Le nom demandé ne correspond plus à l’aperçu.");
        if (read is not null && kind != "join" && !string.Equals(read.Computer, computer.Name, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("preview.identity", "Cet aperçu appartient à un autre poste.");

        if (kind == "renameMove" && read is not null)
        {
            var oldParts = new NamingConvention(settings.NamingPattern, settings.Prefix).TryParse(computer.Name);
            if (oldParts?.Site.Equals(SiteOf(read.Site).Code, StringComparison.OrdinalIgnoreCase) == true
                || string.Equals(computer.Ou, read.Ou, StringComparison.OrdinalIgnoreCase))
            {
                if (targetArg is not null && !string.Equals(targetArg, computer.Ou, StringComparison.OrdinalIgnoreCase))
                    throw new PestoException("rename.no_move", "Le site ne change pas : seule l’action de renommage est admise, avec conservation de l’OU actuelle.");
                kind = "rename";
            }
        }
        if (kind == "rename" && targetArg is not null && !string.Equals(targetArg, computer.Ou, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("rename.no_move", "Un renommage seul conserve l’OU actuelle.");

        var newName = read?.Name ?? computer.Name;
        if (nextOutcome == "nameCollision" && read is not null)
        {
            nextOutcome = null;
            computers.Add(new Computer { Name = newName, Guid = Guid.NewGuid().ToString(), Site = read.Site, Service = read.Service,
                Ou = read.Ou, Domain = settings.Domain, Os = "Windows 11", DnsName = newName.ToLowerInvariant() + "." + settings.Domain });
            previews.Remove(read.PreviewId);
            Log("Collision fictive : le nom de l’aperçu a été pris. Nouvel aperçu et nouvelle confirmation requis.", "warn");
            throw new PestoException("name.taken", "Scénario fictif : ce nom vient d’être pris. Calculez un nouvel aperçu, puis confirmez de nouveau.");
        }
        if (Taken(newName, computer.Name)) throw new PestoException("name.taken", "Le nom affiché vient d’être pris. Calculez et confirmez un nouvel aperçu.");
        var targetOu = kind == "rename" ? computer.Ou : read?.Ou ?? SiteOf(targetArg!).Ou;

        var steps = new List<Step>
        {
            new("Vérifier l’identité", computer.Name),
            new(kind == "move" ? "Déplacer le compte" : "Appliquer le nom confirmé", newName),
        };
        if (kind is "renameMove" or "join") steps.Add(new("Vérifier le placement", targetOu));

        var plan = new Plan
        {
            PlanId = NewId("plan"),
            Kind = kind,
            Computer = computer.Name,
            NewName = newName,
            TargetOU = targetOu,
            Mode = "simulation",
            ExpiresAt = Now.AddMinutes(5),
            ConfirmationName = newName.Length > 0 ? newName : computer.Name,
            Steps = steps,
            Warnings = ["Démonstration : cette action modifie seulement les données en mémoire. Aucun redémarrage réel."],
            Revision = revision,
            Guid = computer.Guid,
            Read = read,
        };
        plans[plan.PlanId] = plan;
        return PlanNode(plan);
    }

    private JsonObject OperationExecute(JsonElement args)
    {
        var plan = RequireFresh(plans.GetValueOrDefault(Arguments.Text(args, "planId", true)), "Le plan");
        if (plan.Used) throw new PestoException("plan.consumed", "Ce plan a déjà été envoyé. Consultez son reçu.");
        if (!Arguments.Text(args, "confirmationName", true).Equals(plan.ConfirmationName, StringComparison.Ordinal))
            throw new PestoException("confirmation.invalid", "Le nom confirmé ne correspond pas au plan. Préparez de nouveau l’opération.");
        if (receipts.Any(r => r.Status == "uncertain"))
            throw new PestoException("demo.uncertain", "Le résultat fictif précédent reste incertain. Aucune nouvelle écriture n’est simulée avant remise à zéro.");

        // Consume before applying: even a refusal after admission can never be replayed automatically.
        plan.Used = true;
        var computer = plan.Kind == "join" ? local.AsComputer() : ComputerOf(plan.Computer);
        if (!string.Equals(computer.Guid, plan.Guid, StringComparison.OrdinalIgnoreCase) || Taken(plan.NewName, plan.Computer))
            throw new PestoException("identity.changed", "La cible ou la disponibilité du nom a changé. Rien n’a été appliqué.");
        if (plan.Kind == "join" && local.Domain is not null) throw new PestoException("join.alreadyJoined", "Le poste est déjà dans le domaine simulé.");
        if (plan.ParentReceiptId is { } parentId && receipts.All(r => r.Id != parentId || r.ResolutionChildReceiptId is not null))
            throw new PestoException("demo.receipt", "Le déplacement restant a déjà été traité dans cette démonstration.");
        if (nextOutcome is "denied" or "uncertain")
        {
            var uncertain = nextOutcome == "uncertain";
            nextOutcome = null;
            var refused = new Receipt(NewId("receipt"), Now, plan.Kind, plan.Computer, plan.NewName, plan.TargetOU, "simulation",
                uncertain ? "uncertain" : "refused", uncertain ? 97 : 5,
                uncertain ? "Scénario fictif : résultat inconnu. Aucun rejeu ; le lot s’arrête et le reçu conserve son incertitude."
                    : "Scénario fictif : accès refusé. Aucun changement appliqué, aucun repli implicite.", false);
            receipts.Insert(0, refused);
            Log(refused.Message, uncertain ? "warn" : "error");
            return ReceiptNode(refused);
        }

        if (plan.Kind == "join")
        {
            computer = new Computer
            {
                Name = local.Name, Guid = local.Guid, DnsName = "", Site = plan.Read!.Site, Service = plan.Read.Service,
                Ou = plan.TargetOU, Os = "Windows 11", Status = "known", Manufacturer = "Démonstration", Model = "Portable",
                Serial = "DEMO-JOIN", Ip = null, PendingRestart = false,
            };
            computers.Add(computer);
        }
        if (plan.Kind != "move") computer.Name = plan.NewName;
        if (plan.Kind != "rename") { computer.Ou = plan.TargetOU; computer.Site = SiteOf(plan.TargetOU).Id; }
        if (plan.Read is not null) computer.Service = plan.Read.Service;
        computer.Domain = settings.Domain;
        computer.DnsName = computer.Name.ToLowerInvariant() + "." + settings.Domain;
        computer.PendingRestart = plan.Kind != "move";
        if (computer.Guid == local.Guid) local.Absorb(computer);

        var receipt = new Receipt(NewId("receipt"), Now, plan.Kind, plan.Computer, computer.Name, computer.Ou, "simulation",
            "simulated", plan.Kind switch { "join" => 10, "rename" => 20, "move" => 30, _ => 77 },
            "Action simulée appliquée en mémoire. Aucun ordinateur ni annuaire réel n’a été modifié.", computer.PendingRestart, plan.ParentReceiptId);
        receipts.Insert(0, receipt);
        if (plan.ParentReceiptId is { } resolved)
        {
            var parentIndex = receipts.FindIndex(r => r.Id == resolved);
            receipts[parentIndex] = receipts[parentIndex] with { ResolutionChildReceiptId = receipt.Id };
        }
        Log($"Simulation terminée : {plan.Kind}, {plan.Computer} → {computer.Name}.");
        return ReceiptNode(receipt);
    }

    // ---- queue ------------------------------------------------------------------

    private JsonObject QueueAdd(JsonElement args)
    {
        var kind = Arguments.Text(args, "kind", true);
        if (kind == "join") throw new PestoException("queue.local", "La jonction locale ne peut pas être placée en file.");
        if (queue.Count >= 50) throw new PestoException("queue.limit", "La file est limitée à 50 postes.");
        var prepared = PrepareFromArgs(args);
        if (queue.Any(q => q.Computer.Equals(prepared.Computer, StringComparison.OrdinalIgnoreCase) || q.NewName.Equals(prepared.NewName, StringComparison.OrdinalIgnoreCase)))
            throw new PestoException("queue.duplicate", "Ce poste ou ce nom est déjà dans la file.");
        queue.Add(new QueueItem(NewId("queue"), prepared.Kind, prepared.Computer, prepared.NewName, prepared.TargetOU, "ready", Optional(args, "previewId")));
        queueVersion++;
        batches.Clear();
        return QueueList();
    }

    private JsonObject QueueList() => Resp.Obj(("items", Resp.Arr(queue, q => Resp.Obj(
        ("id", q.Id), ("kind", q.Kind), ("computer", q.Computer), ("newName", q.NewName), ("targetOU", q.TargetOU), ("status", q.Status)))),
        ("count", queue.Count));

    private JsonObject QueueRemove(JsonElement args)
    {
        var id = Arguments.Text(args, "id", true);
        var index = queue.FindIndex(q => q.Id == id);
        if (index < 0) throw new PestoException("queue.missing", "Cette ligne ne figure plus dans la file.");
        queue.RemoveAt(index);
        queueVersion++;
        batches.Clear();
        return QueueList();
    }

    private JsonObject QueuePrepare(JsonElement args)
    {
        Arguments.Only(args, "pilot");
        var pilot = Arguments.Flag(args, "pilot");
        if (queue.Count == 0) throw new PestoException("queue.empty", "Ajoutez au moins un poste à la file.");
        var items = (pilot ? queue.Take(1) : queue).Select(q => PrepareFromArgs(q.ToArgs())).ToList();
        var batch = new Batch
        {
            BatchId = NewId("batch"),
            Items = items,
            ExpiresAt = Now.AddMinutes(5),
            Warnings = ["Chaque action sera simulée une seule fois, dans l’ordre affiché."],
            Revision = revision,
            QueueVersion = queueVersion,
            Pilot = pilot,
        };
        if (pilot) batch.Warnings.Insert(0, "Mode pilote fictif : seule la première ligne est préparée ; les suivantes restent en file pour une nouvelle confirmation.");
        batches[batch.BatchId] = batch;
        return Resp.Obj(
            ("batchId", batch.BatchId),
            ("pilot", batch.Pilot), ("remainingCount", queue.Count - items.Count),
            ("items", Resp.Arr(batch.Items, PlanNode)),
            ("expiresAt", Iso(batch.ExpiresAt)),
            ("warnings", Resp.Arr(batch.Warnings, w => (JsonNode?)Resp.Node(w))));
    }

    private JsonObject QueueExecute(JsonElement args)
    {
        Arguments.Only(args, "batchId", "confirmed", "entraLeaveConfirmed");
        var batch = RequireFresh(batches.GetValueOrDefault(Arguments.Text(args, "batchId", true)), "Le lot");
        if (!Arguments.Flag(args, "confirmed")) throw new PestoException("confirmation.invalid", "Le lot doit être confirmé explicitement.");
        if (batch.Used || batch.QueueVersion != queueVersion) throw new PestoException("batch.stale", "Le lot a changé ou a déjà été envoyé.");
        batch.Used = true;
        var applied = new List<JsonObject>();
        var reason = "";
        foreach (var plan in batch.Items)
        {
            try
            {
                var receipt = ApplyPlan(plan);
                applied.Add(receipt);
                queue.RemoveAt(0);
                if (receipt["status"]!.GetValue<string>() != "simulated")
                {
                    reason = "Le lot fictif s’arrête sur le premier refus ou résultat incertain. Les lignes suivantes ne sont pas tentées.";
                    break;
                }
            }
            catch (PestoException error) { reason = error.Message; break; }
        }
        queueVersion++;
        var pilotCompleted = batch.Pilot && applied.Count == 1 && reason.Length == 0;
        if (pilotCompleted && queue.Count > 0) reason = "Pilote fictif terminé : une seule ligne simulée. Préparez et confirmez un nouveau lot pour les lignes restantes.";
        return Resp.Obj(
            ("receipts", Resp.Arr(applied, r => (JsonNode?)r)),
            ("pilot", batch.Pilot), ("pilotCompleted", pilotCompleted), ("remainingCount", queue.Count),
            ("stopped", reason.Length > 0),
            ("reason", reason.Length > 0 ? reason : null));
    }

    // ---- receipts and logs ------------------------------------------------------

    private JsonObject ReceiptsList(JsonElement args)
    {
        var query = Arguments.Text(args, "query").ToLowerInvariant();
        var items = receipts.Where(r => $"{r.Computer} {r.NewName} {r.Status} {r.Id}".ToLowerInvariant().Contains(query));
        return Resp.Obj(("items", Resp.Arr(items, ReceiptNode)));
    }

    private JsonObject ReceiptsGet(JsonElement args)
    {
        var id = Arguments.Text(args, "id", true);
        return receipts.FirstOrDefault(r => r.Id == id) is { } receipt ? ReceiptNode(receipt)
            : throw new PestoException("receipt.missing", "Ce reçu n’existe pas dans cette session.");
    }

    private JsonObject LogsList(JsonElement args)
    {
        var query = Arguments.Text(args, "query").ToLowerInvariant();
        var level = Arguments.Text(args, "level");
        var items = logs.Where(l => (level.Length == 0 || l.Level == level) && l.Message.ToLowerInvariant().Contains(query));
        return Resp.Obj(("items", Resp.Arr(items, l => Resp.Obj(("id", l.Id), ("time", Iso(l.Time)), ("level", l.Level), ("message", l.Message)))));
    }

    // ---- settings ---------------------------------------------------------------

    private JsonObject SettingsSave(JsonElement args)
    {
        var next = PestoSettings.Parse(args, simulation: true);
        settings = next;
        revision++;
        previews.Clear();
        plans.Clear();
        batches.Clear();
        queue.Clear();
        queueVersion++;
        Log("Paramètres simulés enregistrés ; aperçus, plans et file invalidés.");
        return SettingsNode(settings);
    }

    // ---- shared helpers ---------------------------------------------------------

    private Plan PrepareFromArgs(JsonElement args)
    {
        // Reuses the exact prepare path so a queued item obeys the same guardrails as a single operation.
        var planElement = OperationPrepare(args);
        var planId = planElement["planId"]!.GetValue<string>();
        return plans[planId];
    }

    private JsonObject ApplyPlan(Plan plan)
    {
        var args = JsonSerializer.SerializeToElement(new { planId = plan.PlanId, confirmationName = plan.ConfirmationName }, PestoJson.Options);
        return OperationExecute(args);
    }

    private bool Taken(string name, string? exceptComputer) =>
        computers.Any(c => c.Name.Equals(name, StringComparison.OrdinalIgnoreCase) && !c.Name.Equals(exceptComputer, StringComparison.OrdinalIgnoreCase));

    private Site SiteOf(string value) =>
        settings.Sites.FirstOrDefault(s => new[] { s.Id, s.Name, s.Code, s.Ou }.Contains(value, StringComparer.OrdinalIgnoreCase))
        ?? throw new PestoException("site.invalid", "Choisissez un site configuré.");

    private Computer ComputerOf(string name) =>
        computers.FirstOrDefault(c => c.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
        ?? throw new PestoException("computer.missing", "Ce poste n’existe pas dans l’annuaire de simulation.");

    private Preview? PreviewOrNull(string? id) => id is not null && previews.TryGetValue(id, out var preview) ? preview : null;

    private T RequireFresh<T>(T? value, string label) where T : class
    {
        if (value is null) throw new PestoException("plan.stale", $"{label} a expiré ou les paramètres ont changé. Préparez un nouvel aperçu.");
        var (stored, expiry) = value switch
        {
            Preview p => (p.Revision, p.ExpiresAt),
            Plan l => (l.Revision, l.ExpiresAt),
            Batch b => (b.Revision, b.ExpiresAt),
            _ => throw new InvalidOperationException(),
        };
        if (stored != revision || expiry <= Now)
            throw new PestoException("plan.stale", $"{label} a expiré ou les paramètres ont changé. Préparez un nouvel aperçu.");
        return value;
    }

    private string NewId(string prefix) => prefix + "-" + instanceId + "-" + (++serial).ToString(System.Globalization.CultureInfo.InvariantCulture);
    private DateTimeOffset Now => clock.GetUtcNow();
    private static string Iso(DateTimeOffset value) => value.ToString("O", System.Globalization.CultureInfo.InvariantCulture);
    private void Log(string message, string level = "info") => logs.Insert(0, new LogEntry(NewId("log"), Now, level, message));

    private static string? Optional(JsonElement args, string name) =>
        args.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? NullIfEmpty(value.GetString()!.Trim()) : null;
    private static string? NullIfEmpty(string value) => value.Length == 0 ? null : value;

    private static List<Computer> SeedComputers()
    {
        const string Paris = "OU=Paris,OU=Postes,DC=example,DC=local";
        const string Lyon = "OU=Lyon,OU=Postes,DC=example,DC=local";
        string[,] rows = { { "P111301PAINF001", "paris", "INF", "Windows 11", "Portable", Paris },
            { "S111301PAADM001", "paris", "ADM", "Windows 11", "Fixe", Paris },
            { "V111301LYINF001", "lyon", "INF", "Windows 11", "Virtuel", Lyon },
            { "P111301LYLOG001", "lyon", "LOG", "Windows 10", "Portable", Lyon } };
        var list = new List<Computer>();
        for (var i = 0; i < rows.GetLength(0); i++)
        {
            var name = rows[i, 0];
            list.Add(new Computer
            {
                Name = name, DnsName = name.ToLowerInvariant() + ".example.local", Site = rows[i, 1], Service = rows[i, 2],
                Ou = rows[i, 5], Os = rows[i, 3], Guid = "00000000-0000-4000-8000-" + (i + 1).ToString("D12", System.Globalization.CultureInfo.InvariantCulture),
                Status = "known", Domain = "example.local", Model = rows[i, 4], Serial = "DEMO-" + (i + 1).ToString(System.Globalization.CultureInfo.InvariantCulture), Ip = null,
            });
        }
        return list;
    }

    // ---- node builders ----------------------------------------------------------

    private static JsonNode SiteNode(Site s) => Resp.Obj(("id", s.Id), ("name", s.Name), ("code", s.Code), ("ou", s.Ou));

    private static JsonObject SettingsNode(PestoSettings s) => Resp.Obj(
        ("domain", s.Domain), ("dc", s.Dc), ("prefix", s.Prefix), ("production", s.Production),
        ("namingPattern", s.NamingPattern), ("randomNames", s.RandomNames),
        ("sites", Resp.Arr(s.Sites, SiteNode)), ("simulation", s.Simulation), ("liveExecutionEnabled", s.LiveExecutionEnabled));

    private static JsonObject ComputerNode(Computer c, Check[]? checks)
    {
        var node = Resp.Obj(
            ("name", c.Name), ("dnsName", c.DnsName), ("site", c.Site), ("service", c.Service), ("ou", c.Ou),
            ("os", c.Os), ("guid", c.Guid), ("status", c.Status), ("domain", c.Domain), ("manufacturer", c.Manufacturer),
            ("model", c.Model), ("serial", c.Serial), ("ip", c.Ip), ("pendingRestart", c.PendingRestart));
        if (checks is not null)
            node["checks"] = Resp.Arr(checks, k => Resp.Obj(("label", k.Label), ("state", k.State), ("detail", k.Detail)));
        return node;
    }

    private static JsonObject PlanNode(Plan plan) => Resp.Obj(
        ("planId", plan.PlanId), ("kind", plan.Kind), ("computer", plan.Computer), ("newName", plan.NewName),
        ("targetOU", plan.TargetOU), ("mode", plan.Mode), ("expiresAt", Iso(plan.ExpiresAt)),
        ("confirmationName", plan.ConfirmationName),
        ("parentReceiptId", plan.ParentReceiptId),
        ("steps", Resp.Arr(plan.Steps, s => Resp.Obj(("label", s.Label), ("detail", s.Detail)))),
        ("warnings", Resp.Arr(plan.Warnings, w => (JsonNode?)Resp.Node(w))));

    private static JsonObject ReceiptNode(Receipt r) => Resp.Obj(
        ("id", r.Id), ("time", Iso(r.Time)), ("kind", r.Kind), ("computer", r.Computer), ("newName", r.NewName),
        ("targetOU", r.TargetOU), ("mode", r.Mode), ("status", r.Status), ("code", r.Code.ToString(System.Globalization.CultureInfo.InvariantCulture)),
        ("message", r.Message), ("restartRequired", r.RestartRequired),
        ("parentReceiptId", r.ParentReceiptId), ("resolutionChildReceiptId", r.ResolutionChildReceiptId));

    public void Dispose()
    {
        lock (gate)
        {
            disposed = true;
            previews.Clear();
            plans.Clear();
            batches.Clear();
            queue.Clear();
        }
    }

    // ---- world model ------------------------------------------------------------

    private sealed class Computer
    {
        public string Name = "";
        public string DnsName = "";
        public string Site = "";
        public string Service = "";
        public string Ou = "";
        public string Os = "";
        public string Guid = "";
        public string Status = "known";
        public string? Domain;
        public string Manufacturer = "Démonstration";
        public string Model = "";
        public string Serial = "";
        public string? Ip;
        public bool PendingRestart;
    }

    private sealed class LocalMachine
    {
        public string Name = "NOUVEAU-PC";
        public string Guid = "00000000-0000-4000-8000-000000000099";
        public string? Domain;
        public bool PendingRestart;

        public Computer AsComputer() => new()
        {
            Name = Name, Guid = Guid, Domain = Domain, PendingRestart = PendingRestart,
            DnsName = Domain is null ? "" : Name.ToLowerInvariant() + "." + Domain,
        };

        public void Absorb(Computer c)
        {
            Name = c.Name;
            Guid = c.Guid;
            Domain = c.Domain;
            PendingRestart = c.PendingRestart;
        }
    }

    private sealed record Preview(string PreviewId, string Name, string Ou, bool Complete, DateTimeOffset CollectedAt,
        DateTimeOffset ExpiresAt, int AvailableCount, string Source, long Revision, string Site, string Service, string? Computer);

    private sealed record Step(string Label, string Detail);

    private sealed class Plan
    {
        public string PlanId = "";
        public string Kind = "";
        public string Computer = "";
        public string NewName = "";
        public string TargetOU = "";
        public string Mode = "";
        public DateTimeOffset ExpiresAt;
        public string ConfirmationName = "";
        public List<Step> Steps = [];
        public List<string> Warnings = [];
        public long Revision;
        public string Guid = "";
        public Preview? Read;
        public bool Used;
        public string? ParentReceiptId;
    }

    private sealed class Batch
    {
        public string BatchId = "";
        public List<Plan> Items = [];
        public DateTimeOffset ExpiresAt;
        public List<string> Warnings = [];
        public long Revision;
        public int QueueVersion;
        public bool Used;
        public bool Pilot;
    }

    private sealed record QueueItem(string Id, string Kind, string Computer, string NewName, string TargetOU, string Status, string? PreviewId)
    {
        public JsonElement ToArgs() => JsonSerializer.SerializeToElement(new
        {
            kind = Kind,
            computer = Computer,
            newName = NewName.Length == 0 ? null : NewName,
            targetOU = TargetOU.Length == 0 ? null : TargetOU,
            previewId = PreviewId,
        }, PestoJson.Options);
    }

    private sealed record DemoScenario(string Id, string Label, string Description, string Page);
}
