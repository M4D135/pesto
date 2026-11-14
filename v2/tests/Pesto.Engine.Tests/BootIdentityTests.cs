using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class BootIdentityTests
{
    private static string Event(string value, string extra = "") => "<Event xmlns=\"http://schemas.microsoft.com/win/2004/08/events/event\"><EventData><Data Name=\"StartTime\">" + value + "</Data>" + extra + "</EventData></Event>";

    [Test]
    public void BootIdentityComesOnlyFromTheExactImmutableStartupEvent()
    {
        var now = DateTimeOffset.Parse("2026-10-25T12:00:00Z", System.Globalization.CultureInfo.InvariantCulture);
        var start = BootIdentity.ReadEventStart(12, BootIdentity.Provider, Event("2026-10-25T08:00:00.1234567Z"), now);
        Check.NotNull(start, "Preuve Kernel-General12 valide");
        Check.Equal(DateTimeOffset.Parse("2026-10-25T08:00:00.1234567Z", System.Globalization.CultureInfo.InvariantCulture), start!.Value, "StartTime exact, pas une estimation d’uptime");
        foreach (var invalid in new[] { "", "<Event/>", Event("today"), Event("2026-10-25T08:00:00+00:00"), Event("2026-10-26T08:00:00Z"), Event("2026-10-25T08:00:00Z", "<Data Name=\"StartTime\">2026-10-25T09:00:00Z</Data>") })
            Check.Null(BootIdentity.ReadEventStart(12, BootIdentity.Provider, invalid, now), "Preuve absente, non UTC, future ou ambiguë refusée");
        Check.Null(BootIdentity.ReadEventStart(13, BootIdentity.Provider, Event("2026-10-25T08:00:00Z"), now), "Mauvais événement refusé");
        Check.Null(BootIdentity.ReadEventStart(12, "Another-Provider", Event("2026-10-25T08:00:00Z"), now), "Mauvais fournisseur refusé");
    }

    [Test]
    public void ClockCorrectionCannotBecomeARebootProof()
    {
        var eventXml = Event("2026-10-25T08:00:00Z");
        var before = DateTimeOffset.Parse("2026-10-25T09:00:00Z", System.Globalization.CultureInfo.InvariantCulture);
        var first = BootIdentity.ReadEventStart(12, BootIdentity.Provider, eventXml, before);
        var afterCorrection = BootIdentity.ReadEventStart(12, BootIdentity.Provider, eventXml, before.AddHours(5));
        Check.Equal(first, afterCorrection, "La correction de l’heure courante ne déplace pas StartTime");
        Check.False(afterCorrection > first, "Aucun déblocage de reprise/retrait par BootUtc artificiellement plus récent");
        Check.Null(BootIdentity.ReadEventStart(12, BootIdentity.Provider, eventXml, before.AddHours(-2)), "Une horloge antérieure au vrai boot est incohérente, jamais remplacée par CIM");
    }

    [Test]
    public void SharedNativeFragmentRefusesMissingEventsWithoutCimFallback()
    {
        var source = BootIdentityScript.Source;
        Check.Contains("Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-General';Id=12} -MaxEvents 1 -ErrorAction Stop", source, "Lecture native exacte V1");
        Check.Contains("@Name=\"StartTime\"", source, "Donnée stable de démarrage");
        Check.False(source.Contains("LastBootUpTime", StringComparison.Ordinal), "Aucun repli CIM");
        Check.False(source.Contains("TimeCreated", StringComparison.Ordinal), "Aucune date d’enregistrement substituée");
        Check.Contains("[Xml.DtdProcessing]::Prohibit", source, "DTD non résolue");
        var type = typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.PowerShellReceiptEvidence")!;
        var script = (string)type.GetProperty("ConstantScript")!.GetValue(null)!;
        Check.Contains(source, script, "Le lecteur des reçus utilise la même autorité");
        Check.Contains("$r.bootUtc=Get-PestoStableBootUtc", script, "Le résultat est utilisé, pas seulement déclaré");
        Check.False(script.Contains("LastBootUpTime", StringComparison.Ordinal), "Aucun fallback caché du lecteur initial/final");
    }
}
