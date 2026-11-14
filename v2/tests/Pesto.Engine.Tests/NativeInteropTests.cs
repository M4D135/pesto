using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class NativeInteropTests
{
    [Test]
    public void TaskLifecycleReusesTheOneAuthenticatedConnectionAndCannotChangeTargets()
    {
        var calls = 0;
        var released = 0;
        var service = new object();
        using var session = new TaskSchedulerSession((computer, principal, password) =>
        {
            calls++;
            Check.Equal("LAB-PC", computer, "La connexion vise la cible déclarée");
            Check.Equal("DOMAIN\\operator", principal!, "Le compte explicite sert à la connexion");
            Check.Equal("fixture-only", password!, "Le secret n’est fourni qu’à la connexion en mémoire");
            return service;
        }, obj => { if (ReferenceEquals(service, obj)) released++; });
        session.Bind("LAB-PC", "\\Pesto_Rename_001122334455", "DOMAIN\\operator", "fixture-only");
        foreach (var phase in new[] { "run", "probe", "delete" })
            Check.True(ReferenceEquals(service, session.ForTask("lab-pc", "\\Pesto_Rename_001122334455")), phase + " conserve la même session authentifiée");
        Check.Equal(1, calls, "Aucune reconnexion SSO pour Run, Probe ou Delete");
        foreach (var target in new[] { ("OTHER-PC", "\\Pesto_Rename_001122334455"), ("LAB-PC", "\\Pesto_Rename_ffffffffffff") })
        {
            var rejected = false;
            try { _ = session.ForTask(target.Item1, target.Item2); } catch (InvalidOperationException) { rejected = true; }
            Check.True(rejected, "L’identité de cible/tâche ne peut pas changer pendant le nettoyage");
        }
        session.Dispose(); session.Dispose();
        Check.Equal(1, released, "Connexion libérée exactement une fois, sans conserver de secret");
    }

    [Test]
    public void ComDateTimeIsAcceptedWithoutAnInvalidStringCast()
    {
        var date = new DateTime(2026, 10, 25, 12, 0, 0, DateTimeKind.Utc);
        Check.Equal(new DateTimeOffset(date), TaskSchedulerComValues.LastRunTime(date)!.Value, "VT_DATE marshalled DateTime est reconnu");
        Check.Null(TaskSchedulerComValues.LastRunTime("25/10/2026"), "Aucune date locale ambiguë inventée depuis un texte");
        Check.Null(TaskSchedulerComValues.LastRunTime(null), "Absence de date : aucune exécution confirmée");
        Check.True(TaskSchedulerComValues.LastRunTime(new DateTime(1899, 12, 30))!.Value.Year < 2000, "La date COM zéro reste non exécutée pour le runner");
    }

    [Test]
    public void NativeFailureScriptUsesTheV1Win32SemanticsAndFinalOuGuards()
    {
        var script = PowerShellMutationGateway.ConstantScript;
        Check.Contains("NativeErrorCode", script, "Win32Exception utilise son code natif");
        Check.Contains("4294901760) -eq 2147942400", script, "Seule la facility HRESULT_FROM_WIN32 est décodée");
        Check.Contains("$i -lt 8", script, "Les erreurs internes sont inspectées comme en V1");
        Check.Contains("$srcOU -ine $sourceOu", script, "Le déplacement refuse une OU source modifiée");
        Check.Contains("[Guid]$destination.ObjectGUID -ne $id", script, "Le DN de destination doit conserver le GUID confirmé");
        Check.Contains("Assert-PestoDestination $targetOu $targetOuGuid $adp", script, "La destination est relue avant les appels natifs");
        Check.Contains("if($op -eq 'renameMove' -and $sourceOu -and $targetOu -ieq $sourceOu){$op='rename'}", script,
            "Défense native : même OU implique renommage seul, sans levée de protection ni déplacement");
    }
}
