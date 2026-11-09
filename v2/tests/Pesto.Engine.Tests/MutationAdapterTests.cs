using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>
/// Lot moteur live 4 : l'adaptateur de mutations transitoire PowerShell 5.1 refuse tout envoi hors Windows avec des
/// raisons motivées (rien n'a jamais quitté le processus : Failed, jamais Uncertain), et le moteur raccordé à cet
/// adaptateur via la seule surcharge de qualification reste honnête : reçu « refused », aucun fait inventé.
/// Aucune mutation réelle, aucune écriture AD/disque, aucun processus lancé depuis ces tests.
/// </summary>
internal sealed class MutationAdapterTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string ParisOu = "OU=Paris-Nord," + Container;
    private const string Computer = "P111301PAINF009";
    private const string ComputerGuid = "11111111-1111-1111-1111-111111111111";

    private static Pesto.Engine.MutationRequest Request(string kind, string computer = Computer, string? newName = "P111301PAINF010",
        string? guid = ComputerGuid, string? targetOu = ParisOu) =>
        new(kind, computer, guid, newName, targetOu, "example.local", "dc01.example.local", "plan-1", "receipt-1",
            kind == "join" ? null : ParisOu, kind is "join" or "move" or "renameMove" ? "33333333-3333-3333-3333-333333333333" : null);

    // ---- refus motivés avant tout envoi (aucun processus, aucune écriture) --------------------

    [Test]
    public void TransientMutationAdapterRefusesEveryKindOffWindowsWithoutAnySend()
    {
        var adapter = new PowerShellMutationGateway();
        Check.False(string.IsNullOrEmpty(adapter.Description), "L’adaptateur déclare son origine réelle");
        Check.Contains("non qualifié", adapter.Description, "Il se déclare non qualifié Windows/AD, jamais une origine cachée");
        if (OperatingSystem.IsWindows()) return; // Sur Windows, la qualification seule décide ; jamais d'envoi depuis un test.
        foreach (var kind in new[] { "join", "rename", "move", "renameMove" })
        {
            var outcome = adapter.Execute(Request(kind, computer: kind == "join" ? Environment.MachineName : Computer, newName: kind == "move" ? null : "P111301PAINF010"));
            Check.Equal(Pesto.Engine.MutationStatus.Failed, outcome.Status, kind + " : hors Windows, refus prouvé avant envoi — un refus qui n'a jamais quitté le processus n'est jamais « incertain »");
            Check.True(outcome.Code is 96 or 11, kind + " : code de refus portés de V1 (96/11 = non lancé)");
            Check.False(string.IsNullOrEmpty(outcome.Message), kind + " : chaque refus porte une raison exploitable");
            Check.False(outcome.RestartRequired, kind + " : aucun redémarrage annoncé sans envoi");
            Check.Contains("refusées plutôt que simulées", outcome.Message, "Le refus dit que rien n'est simulé");
        }
    }

    [Test]
    public void AdapterRefusesInvalidRequestsBeforeEvenProbingTheSystem()
    {
        var adapter = new PowerShellMutationGateway();
        var cases = new (Pesto.Engine.MutationRequest Request, int Code, string Needle, string Why)[]
        {
            (Request("delete"), 11, "non déclaré", "Aucun type de mutation hors de la liste fermée join/rename/move/renameMove"),
            (Request("rename", computer: "TROP-LONG-12345678"), 11, "Nom de poste invalide", "15 caractères maximum, modèle historique"),
            (Request("rename", newName: "nom avec espaces"), 11, "Nouveau nom invalide", "Aucun nom arbitraire ne atteint la commande native"),
            (Request("join", computer: "AUTRE-PC"), 96, "poste local", "La jonction ne concerne jamais un autre poste"),
            (Request("move", targetOu: null, newName: null), 11, "OU de destination", "Un déplacement sans destination observée est refusé"),
            (Request("move", guid: "pas-un-guid", newName: null), 96, "GUID", "Aucun déplacement sans GUID réellement observé"),
            (Request("move", newName: "P111301PAINF010"), 11, "déplacement ne change pas le nom", "Un déplacement avec un nom imposé est refusé avant tout"),
            (Request("renameMove", newName: null), 11, "Nouveau nom invalide", "renameMove exige le nom confirmé de l'aperçu"),
            (Request("rename", newName: "P111301PAINF010", targetOu: "OU=Invalid\re," + Container), 11, "OU", "Caractère de contrôle dans l'OU : refus"),
            (new("join", Environment.MachineName, null, "P111301PAINF010", ParisOu, "exemple local!", null, "plan-1", "receipt-1"), 11, "Domaine invalide", "Domaine malformé : rien n'est lancé"),
            (new("rename", Computer, ComputerGuid, "P111301PAINF010", null, "example.local", null, "plan 1", "receipt-1"), 11, "Identifiants", "Identifiant de plan non opaque : refus"),
        };
        foreach (var (request, code, needle, why) in cases)
        {
            var outcome = adapter.Execute(request);
            Check.Equal(Pesto.Engine.MutationStatus.Failed, outcome.Status, why + " : Failed prouvé avant envoi, jamais Uncertain");
            Check.Equal(code, outcome.Code, why + " : code de refus porté de V1");
            Check.Contains(needle, outcome.Message, why);
            Check.True(outcome.Message.Length <= 300 && !outcome.Message.Any(char.IsControl), why + " : message borné sans caractère de contrôle");
        }
    }

    // ---- moteur + adaptateur transitoire : la porte d'écriture reste fermée ----------------------

    [Test]
    public void EngineWiredToTheTransientAdapterStillWritesNothingOffWindows()
    {
        if (OperatingSystem.IsWindows())
        {
            // This fixture must never enter a native pipeline on a Windows CI worker. An invalid operation is
            // rejected before PowerShell, AD, durable GP receipts or any machine state can be touched.
            var refused = new PowerShellMutationGateway().Execute(Request("delete"));
            Check.Equal(11, refused.Code, "Refus avant système sur Windows ; aucune mutation de fixture n’est envoyée");
            Check.Equal(MutationStatus.Failed, refused.Status, "Aucun résultat incertain sans envoi");
            return;
        }
        var root = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] },
            Find = name => name.Equals(Computer, StringComparison.OrdinalIgnoreCase)
                ? new Pesto.Engine.DirectoryComputer(name, null, ParisOu, null, ComputerGuid, "example.local", null, null, null, null, null)
                : null,
        };
        var gpRoot = Harness.IsolatedGpRoot();
        var adapter = new PowerShellMutationGateway(root, receiptGpRoot: gpRoot);
        var backend = Harness.Live(root, gateway, adapter, new FixedClock(), gpRoot);

        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        Check.Pesto(() => Harness.Call(backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(preview, "previewId") }),
            "entra.platform", "Hors Windows la preuve Entra manque : aucun plan exécutable fabriqué");
        Check.Equal(0, Harness.Arr(Harness.Call(backend, "receipts.list"), "items").Count, "Une préparation refusée n’invente pas un envoi ni un reçu métier");
        Check.Equal(MutationStatus.Failed, adapter.Execute(Request("rename")).Status, "L’adaptateur direct reste également fermé hors Windows");
        Check.Equal(0, Directory.GetFiles(gpRoot, "*", SearchOption.AllDirectories).Length, "Aucun reçu natif ni preuve de tâche créée");
    }

    [Test]
    public void CapabilitiesReflectObservedAdapterAvailability()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var gateway = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord"] } };
        var adapter = new PowerShellMutationGateway(root);
        var backend = Harness.Live(root, gateway, adapter);
        foreach (var item in Harness.Arr(Harness.Call(backend, "session.info"), "capabilities"))
        {
            var expected = adapter.IsAvailable && item!["id"]!.GetValue<string>() != "joinPrecreated";
            Check.Equal(expected, item!["enabled"]!.GetValue<bool>(), "Disponibilité observée et politique de réutilisation commandent les capacités");
            if (!expected) Check.False(string.IsNullOrEmpty(item!["reason"]!.GetValue<string>()), "Chaque refus porte une raison");
        }
        var writes = System.Linq.Enumerable.Single(Harness.Arr(Harness.Call(backend, "diagnostics.read"), "checks"), c => c!["label"]!.GetValue<string>() == "Écritures");
        Check.Equal(adapter.IsAvailable ? "ok" : "unknown", writes!["state"]!.GetValue<string>(), "Diagnostic de disponibilité du runtime");
        if (!adapter.IsAvailable) Check.False(string.IsNullOrEmpty(writes["detail"]!.GetValue<string>()), "La raison d’indisponibilité est visible");
    }

    [Test]
    public void HostEntryPointsCannotReachTheMutationAdapter()
    {
        // Les entrées publiques de l'hôte (celle du pont avec lecteur annuaire, et celle sans lecteur) refusent
        // toute exécution : seule la surcharge de qualification accepte un adaptateur de mutation.
        var root = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var gateway = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord"] } };
        var host = PestoBackend.CreateLive(root, gateway);
        var preview = Harness.Call(host, "names.preview", new { type = "P", site = "PA", service = "INF" });
        var plan = Harness.Call(host, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId") });
        Check.Pesto(() => Harness.Call(host, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") }),
            "write.unavailable", "L’entrée publique utilisée par l’hôte n’injecte jamais l’adaptateur de mutations");
        Check.Equal(0, Harness.Arr(Harness.Call(host, "receipts.list"), "items").Count, "Aucun reçu fictif sur le chemin de l’hôte");
        var bare = PestoBackend.CreateLive(root);
        Check.Pesto(() => Harness.Call(bare, "operation.execute", new { planId = "plan-1", confirmationName = "X" }),
            "plan.stale", "Sans plan préparé, rien n'est envoyé, même par l'entrée sans lecteur annuaire");
        Check.Equal(0, Harness.Arr(Harness.Call(bare, "receipts.list"), "items").Count, "Aucun reçu inventé");
    }
}
