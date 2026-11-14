using System.Text;
using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend : IPestoAutomationBackend
{
    private sealed record HeldAutomation(AutomationPreparation Preparation, LivePlan LivePlan,
        AutomationHostContext Context, AutomationExecutionAuthorization? Execution);
    private readonly Dictionary<string, HeldAutomation> automationPreparations = new(StringComparer.Ordinal);

    public AutomationPreparation PrepareAutomation(PestoCliOptions options, AutomationHostContext context,
        IReadOnlyDictionary<string, string> metadata, AutomationPlan? expected = null, AutomationExecutionAuthorization? execution = null)
    {
        lock (gate)
        {
            options.Validate();
            if (options.Action is "inspect" or "diagnose") throw AutomationPlanRules.Refused("Cette lecture ne prépare pas de mutation.");
            RefreshConfigurationIfChanged();
            var read = RequireConfig(); RequireUnchangedConfiguration();
            var configDirectory = V1ConfigDirectory.Resolve(v1InstallationPath)
                ?? throw AutomationPlanRules.Refused("Configuration automatique absente.");
            if (!AutomationPlanRules.Same(Path.GetFullPath(configDirectory), Path.GetFullPath(context.ConfigurationDirectory)))
                throw AutomationPlanRules.Refused("Le moteur ne lit pas le profil demandé par l'hôte.");
            var bytes = PestoCliRunner.ReadConfiguration(Path.Combine(configDirectory, "cfg.json"));
            if (AutomationPlanRules.Digest(bytes) != configStamp) throw AutomationPlanRules.Refused("La configuration de la session a changé.");
            var json = new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF');
            var managed = mutation is IMutationManagedPolicy native ? native.ReadManagedPolicy() : context.ManagedPolicyReader?.Invoke() ?? new();
            AutomationPolicy.Require(json, managed, options, context);
            metadata = AutomationPlanRules.ValidateMetadata(metadata);
            if (expected is not null) AutomationPlanRules.RequireContext(expected, context, configStamp!, clock.GetUtcNow());
            if (execution is not null)
            {
                if (expected is null || execution.Plan.Integrity != expected.Integrity || !options.Execute || gpRoot is null
                    || !AutomationPlanRules.Same(Path.GetFullPath(gpRoot), Path.GetFullPath(context.GpRoot)))
                    throw AutomationPlanRules.Refused("L'exécution doit être liée à une intention durable du même registre local.");
                AutomationJournal.RequireAuthority(context.GpRoot, execution);
                AutomationCampaignApproval.Require(managed.CampaignApprovalJson, execution.ApprovalJson, expected, context.OperatorSid, clock.GetUtcNow());
            }
            else if (options.Execute) throw AutomationPlanRules.Refused("Aucune exécution sans l'intention durable créée par le runner.");
            if (mutation is null || mutation is IMutationAvailability { IsAvailable: false }) throw new PestoException("automation.unavailable", "Adaptateur de mutation réelle indisponible.");
            var adapter = RequireGateway();
            var dc = DcOrNull();
            if (!JoinClockGuard.IsServer(dc) || AutomationPlanRules.Same(dc, read.Domain) || !dc!.EndsWith("." + read.Domain, StringComparison.OrdinalIgnoreCase))
                throw AutomationPlanRules.Refused("Le contrôleur exact du domaine n'est pas observé ; aucun plan automatique.");
            if (expected is not null && (!AutomationPlanRules.Same(expected.Domain, read.Domain) || !AutomationPlanRules.Same(expected.Dc, dc)))
                throw AutomationPlanRules.Refused("Le domaine ou le contrôleur diffère du plan exporté ; aucune bascule silencieuse.");
            var computer = options.Action == "join" ? context.ComputerName : options.Computer
                ?? throw AutomationPlanRules.Refused("--computer est requis pour une opération automatique.");
            ValidateComputerName(computer);
            if (options.Action == "join" && !AutomationPlanRules.Same(computer, Environment.MachineName))
                throw AutomationPlanRules.Refused("L'identité locale du moteur diffère de l'hôte.");

            var policy = Policy(read);
            var naming = GetConvention(read);
            var source = options.Action == "join" ? null : adapter.FindComputer(read.Domain, dc, computer)
                ?? (options.Action == "join" ? null : throw AutomationPlanRules.Refused("La source exacte n'existe plus dans l'annuaire."));
            if (source is not null && (!AutomationPlanRules.Same(source.Name, computer) || !AutomationPlanRules.Same(source.Domain, read.Domain)
                || !RemoteWindowsEvidenceProtocol.IsGuid(source.Guid) || !WithinScope(source.Ou, read.RootOu)))
                throw AutomationPlanRules.Refused("La source AD, son GUID, son nom ou son domaine ne correspondent pas au plan.");
            if (expected is not null && source is not null && (!AutomationPlanRules.Same(source.Guid, expected.ComputerGuid)
                || !AutomationPlanRules.Same(source.Ou, expected.SourceOu)))
                throw AutomationPlanRules.Refused("L'identité ou le placement source ont changé depuis l'export.");

            string newName, targetOu;
            if (options.Action == "join")
            {
                (newName, targetOu) = PrepareAutomationJoin(options, read, policy, adapter, dc!, expected);
            }
            else
            {
                newName = options.Action == "move" ? computer : options.NewName
                    ?? throw AutomationPlanRules.Refused("--new-name exact est requis pour le renommage automatique.");
                targetOu = options.TargetOu ?? source!.Ou!;
                if (options.Action == "move" && options.TargetOu is null) throw AutomationPlanRules.Refused("--target-ou est requis pour le déplacement automatique.");
                if (options.Action == "move" && options.NewName is not null && !AutomationPlanRules.Same(options.NewName, computer))
                    throw AutomationPlanRules.Refused("Le déplacement ne peut pas changer le nom.");
                if (options.Action is "rename" or "renameMove" && naming.TryParse(newName) is null)
                    throw AutomationPlanRules.Refused("Le nom confirmé doit respecter la convention configurée.");
            }
            if (expected is not null && (!AutomationPlanRules.Same(newName, expected.NewName) || !AutomationPlanRules.Same(targetOu, expected.TargetOu)))
                throw AutomationPlanRules.Refused("Le nom ou l'OU préparés diffèrent du document confirmé.");
            ValidateComputerName(newName);
            policy.AssertPlan(options.Action, computer, newName, source?.Ou, targetOu, naming);
            if (options.Action is "join" or "move" or "renameMove" && expected is not null
                && !AutomationPlanRules.Same(ResolveTargetGuid(read, adapter, targetOu), expected.TargetOuGuid))
                throw AutomationPlanRules.Refused("L'OU cible a été remplacée depuis l'export.");

            LivePreview? preview = null;
            try
            {
                if (options.Action != "move")
                {
                    var id = "automation-preview-" + Guid.NewGuid().ToString("N");
                    if (execution is not null)
                    {
                        RequireUnchangedConfiguration();
                        var currentManaged = mutation is IMutationManagedPolicy currentNative ? currentNative.ReadManagedPolicy() : context.ManagedPolicyReader?.Invoke() ?? new();
                        AutomationPolicy.Require(json, currentManaged, options, context);
                        AutomationCampaignApproval.Require(currentManaged.CampaignApprovalJson, execution.ApprovalJson, execution.Plan, context.OperatorSid, clock.GetUtcNow());
                        AutomationJournal.RequireAuthority(context.GpRoot, execution);
                    }
                    var lease = execution is null ? null : ReservePreviewName(read, policy, newName, id);
                    preview = new() { PreviewId = id, Name = newName, Ou = targetOu, Key = id,
                        CollectedAt = clock.GetUtcNow(), ExpiresAt = ExpiresWithNameLease(clock.GetUtcNow().AddMinutes(PreviewMinutes), lease),
                        AvailableCount = 1, Computer = options.Action == "join" ? null : computer, NameReservation = lease };
                    previews.Add(id, preview); latestByKey.Add(id, preview);
                }
                var arguments = new Dictionary<string, string> { ["kind"] = options.Action, ["computer"] = computer, ["targetOU"] = targetOu, ["newName"] = newName };
                if (preview is not null) arguments.Add("previewId", preview.PreviewId);
                var actual = BuildPlan(JsonSerializer.SerializeToElement(arguments), automationReadOnlyPreparation: execution is null);
                if (actual.Kind != options.Action) throw AutomationPlanRules.Refused("Ce RenameMove est incohérent avec la règle de site : préparez explicitement le renommage seul.");
                var now = clock.GetUtcNow();
                var portable = AutomationPlanRules.Seal(new(1, AutomationPlanRules.Purpose, actual.Kind, now, now.AddHours(24),
                    context.ProfileSid, context.OperatorSid, context.MachineId,
                    AutomationPlanRules.ConfigurationIdentity(configDirectory, context.ProfileSid), actual.ConfigurationSha256,
                    read.Domain, dc!, actual.Computer, actual.NewName, actual.Guid, actual.SourceOu, actual.TargetOu, actual.TargetOuGuid,
                    options.Type, options.SiteCode?.ToUpperInvariant(), options.ServiceCode?.ToUpperInvariant(), actual.Entra?.MachineId,
                    actual.Entra?.State, actual.Entra?.Policy, actual.Entra?.LeaveRequired == true, metadata, ""));
                if (expected is not null) AutomationPlanRules.RequireSameIntent(expected, portable);
                if (actual.ExpiresAt <= now) throw AutomationPlanRules.Refused("Les preuves ont expiré pendant la préparation ; aucune exécution annoncée possible.");
                var preparation = new AutomationPreparation(Guid.NewGuid().ToString("N"), portable, actual.ExpiresAt);
                automationPreparations.Add(preparation.Token, new(preparation, actual, context, execution));
                return preparation;
            }
            catch
            {
                ReleaseUnusedPreviewName(preview?.NameReservation);
                throw;
            }
        }
    }

    private (string Name, string Ou) PrepareAutomationJoin(PestoCliOptions options, V1Config read, V1OperationPolicy policy,
        IDirectoryGateway adapter, string dc, AutomationPlan? expected)
    {
        var naming = GetConvention(read);
        if (options.Type is null || options.SiteCode is null || options.ServiceCode is null)
            throw AutomationPlanRules.Refused("La jonction automatique exige --type, --site-code et --service-code explicites.");
        var site = options.SiteCode.ToUpperInvariant(); var service = options.ServiceCode.ToUpperInvariant();
        _ = naming.Format(options.Type, site, service, 1);
        string target;
        if (!read.Production)
        {
            target = read.PreprodOu ?? throw AutomationPlanRules.Refused("L'OU PREPROD n'est pas définie.");
            var tags = read.DeclaredSites.Where(item => V1Config.MatchesWildcard(item.Pattern, "PREPROD")).Select(item => item.Tag).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            if (tags.Length != 1 || !AutomationPlanRules.Same(site, tags[0]) || !AutomationPlanRules.Same(service, read.PreprodSite)
                || options.TargetOu is not null && !AutomationPlanRules.Same(options.TargetOu, target))
                throw AutomationPlanRules.Refused("DirectProd=false impose l'OU PREPROD, son tag et le service PreprodSite configurés.");
        }
        else
        {
            target = options.TargetOu ?? throw AutomationPlanRules.Refused("En production, --target-ou est requis.");
            var parent = Split(target) is { Length: > 1 } parts ? string.Join(',', parts.Skip(1)) : "";
            if (!read.OrganismOus.Contains(parent, StringComparer.OrdinalIgnoreCase)
                || !ResolveSites(read, adapter).Any(item => AutomationPlanRules.Same(item.Ou, target) && AutomationPlanRules.Same(item.Code, site)))
                throw AutomationPlanRules.Refused("En production, la cible doit être une OU de site observée directement sous un organisme configuré, correspondant au code site.");
        }
        if (!WithinScope(target, read.RootOu)) throw AutomationPlanRules.Refused("L'OU de jonction sort de la racine configurée.");
        _ = ResolveTargetGuid(read, adapter, target);
        if (adapter is not IAutomationNameInventory inventoryReader)
            throw AutomationPlanRules.Refused("L'inventaire global CN/sAM/DNS de la série n'est pas disponible ; aucun nom automatique choisi.");
        var pattern = naming.SeriesPattern(options.Type, site, service);
        var inventory = inventoryReader.ListAutomationComputerNames(read.Domain, dc, pattern, InventoryHardLimit);
        if (!inventory.Complete) throw AutomationPlanRules.Refused("L'inventaire global des alias est incomplet ; aucun nom présenté comme libre.");
        var used = new HashSet<string>(inventory.Names, StringComparer.OrdinalIgnoreCase);
        var fixedName = expected?.NewName ?? options.NewName;
        if (fixedName is not null)
        {
            var parts = naming.TryParse(fixedName);
            if (parts is null || parts.Type != options.Type || !AutomationPlanRules.Same(parts.Site, site) || !AutomationPlanRules.Same(parts.Service, service)
                || used.Contains(fixedName) || policy.IsNameExcluded(fixedName) || adapter.FindComputer(read.Domain, dc, fixedName) is not null)
                throw AutomationPlanRules.Refused("Le nom du plan n'est plus disponible dans sa série ; aucun autre nom choisi après confirmation.");
            return (fixedName.ToUpperInvariant(), target);
        }
        var free = Enumerable.Range(1, naming.Maximum).Select(number => naming.Format(options.Type, site, service, number))
            .Where(name => !used.Contains(name) && !policy.IsNameExcluded(name)).ToList();
        if (read.RandomNames) random.Shuffle(System.Runtime.InteropServices.CollectionsMarshal.AsSpan(free));
        foreach (var name in free)
            if (adapter.FindComputer(read.Domain, dc, name) is null) return (name, target);
        throw AutomationPlanRules.Refused("Aucun nom libre n'a été confirmé dans la série ; aucun ajout ni remplacement implicite.");
    }

    public Receipt ExecuteAutomation(AutomationPreparation preparation, AutomationExecutionAuthorization execution)
    {
        lock (gate)
        {
            if (!automationPreparations.Remove(preparation.Token, out var held) || !ReferenceEquals(held.Preparation, preparation)
                || !ReferenceEquals(held.Execution, execution) || preparation.ExpiresAt <= clock.GetUtcNow())
                throw AutomationPlanRules.Refused("Cette préparation automatique est absente, consommée ou expirée.");
            AutomationJournal.RequireAuthority(held.Context.GpRoot, execution);
            var bytes = PestoCliRunner.ReadConfiguration(Path.Combine(held.Context.ConfigurationDirectory, "cfg.json"));
            var json = new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF');
            var managed = mutation is IMutationManagedPolicy native ? native.ReadManagedPolicy() : held.Context.ManagedPolicyReader?.Invoke() ?? new();
            AutomationPlanRules.RequireContext(execution.Plan, held.Context, AutomationPlanRules.Digest(bytes), clock.GetUtcNow());
            AutomationPolicy.Require(json, managed, new(execution.Plan.Action, execution.Plan.Computer), held.Context);
            AutomationCampaignApproval.Require(managed.CampaignApprovalJson, execution.ApprovalJson, execution.Plan, held.Context.OperatorSid, clock.GetUtcNow());
            _ = ExecutePlan(held.LivePlan, held.LivePlan.ConfirmationName, execution.EntraLeaveConfirmed, execution);
            return receipts.FirstOrDefault(receipt => receipt.Id == execution.ReceiptId)
                ?? throw new IOException("Le résultat automatique n'a pas de reçu métier.");
        }
    }
}
