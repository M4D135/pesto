using System.Globalization;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;

namespace Pesto.Engine;

/// <summary>V1 campaign approval: HKLM-pinned RSA signer, different operator SID, exact reviewed intent, bounded validity.
/// This is an operator campaign authorization, not application signing or trust supplied by a portable plan.</summary>
public static class AutomationCampaignApproval
{
    /// <summary>V2 approvals cover the complete portable intent, including original profile and Entra effects.</summary>
    public static string PlanHash(AutomationPlan plan) { AutomationPlanRules.Validate(plan); return plan.Integrity; }

    public static void Require(string? policyJson, string? approvalJson, AutomationPlan plan, string operatorSid, DateTimeOffset now)
    {
        if (policyJson is null)
        {
            if (approvalJson is not null) throw Denied("Un accord fourni sans politique HKLM de confiance ne peut pas être utilisé.");
            return;
        }
        try
        {
            if (policyJson.Length > 65536) throw Denied("Politique de campagne trop volumineuse.");
            using var policyDoc = AutomationPlanRules.ParseObject(Encoding.UTF8.GetBytes(policyJson));
            var policy = policyDoc.RootElement;
            AutomationPlanRules.RequireFields(policy, ["Schema", "Campaigns", "Signers"]);
            if (policy.GetProperty("Schema").GetInt32() != 1 || policy.GetProperty("Campaigns").ValueKind != JsonValueKind.Array
                || policy.GetProperty("Campaigns").GetArrayLength() > 200 || policy.GetProperty("Signers").ValueKind != JsonValueKind.Array
                || policy.GetProperty("Signers").GetArrayLength() > 50) throw Denied("Politique de campagne invalide.");
            var campaigns = policy.GetProperty("Campaigns").EnumerateArray().Select(item => Text(item, 120)).ToArray();
            var signers = policy.GetProperty("Signers").EnumerateArray().Select(item =>
            {
                AutomationPlanRules.RequireFields(item, ["CertificateSHA256", "Sid"]);
                var pin = Text(item.GetProperty("CertificateSHA256"), 64); var sid = Text(item.GetProperty("Sid"), 184);
                if (!RemoteWindowsEvidenceProtocol.IsHash(pin) || pin != pin.ToLowerInvariant() || !AutomationPlanRules.Sid(sid))
                    throw Denied("Signataire HKLM invalide.");
                return (Pin: pin, Sid: sid);
            }).ToArray();
            var campaign = plan.Metadata.GetValueOrDefault("Campaign") ?? "";
            var required = campaigns.Contains("*", StringComparer.Ordinal) || campaigns.Contains(campaign, StringComparer.Ordinal);
            if (!required)
            {
                if (approvalJson is not null) throw Denied("Cette campagne ne demande pas d'accord dans la politique HKLM ; aucun accord non vérifié n'est accepté.");
                return;
            }
            if (campaign.Length == 0 || approvalJson is null || approvalJson.Length > 65536)
                throw Denied("Cette campagne exige un accord séparé signé par un approbateur HKLM autorisé.");
            using var approvalDoc = AutomationPlanRules.ParseObject(Encoding.UTF8.GetBytes(approvalJson));
            var approval = approvalDoc.RootElement;
            AutomationPlanRules.RequireFields(approval, ["Schema", "Payload", "Certificate", "Signature"]);
            if (approval.GetProperty("Schema").GetInt32() != 1) throw Denied("Schéma d'accord incompatible.");
            var payload = Convert.FromBase64String(Text(approval.GetProperty("Payload"), 65536));
            var raw = Convert.FromBase64String(Text(approval.GetProperty("Certificate"), 65536));
            var signature = Convert.FromBase64String(Text(approval.GetProperty("Signature"), 65536));
            var pin = AutomationPlanRules.Digest(raw);
            var trusted = signers.Where(signer => signer.Pin == pin).ToArray();
            if (trusted.Length != 1) throw Denied("Le certificat n'a pas exactement un signataire approuvé dans HKLM.");
            using var certificate = X509CertificateLoader.LoadCertificate(raw);
            if (now.UtcDateTime < certificate.NotBefore.ToUniversalTime() || now.UtcDateTime >= certificate.NotAfter.ToUniversalTime())
                throw Denied("Le certificat de l'approbateur n'est pas valide à cet instant.");
            using var key = certificate.GetRSAPublicKey();
            if (key is null || key.KeySize < 2048 || !key.VerifyData(payload, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
                throw Denied("La signature de campagne n'est pas confirmée.");
            _ = new UTF8Encoding(false, true).GetString(payload);
            using var payloadDoc = AutomationPlanRules.ParseObject(payload);
            var value = payloadDoc.RootElement;
            AutomationPlanRules.RequireFields(value, ["Schema", "Purpose", "Campaign", "ApproverSid", "CreatedUtc", "ExpiresUtc", "PlanHashes"]);
            var created = DateTimeOffset.Parse(Text(value.GetProperty("CreatedUtc"), 40), CultureInfo.InvariantCulture);
            var expires = DateTimeOffset.Parse(Text(value.GetProperty("ExpiresUtc"), 40), CultureInfo.InvariantCulture);
            if (value.GetProperty("Schema").GetInt32() != 1 || Text(value.GetProperty("Purpose"), 40) != "PestoCampaignApproval"
                || Text(value.GetProperty("Campaign"), 120) != campaign || Text(value.GetProperty("ApproverSid"), 184) != trusted[0].Sid
                || AutomationPlanRules.Same(trusted[0].Sid, operatorSid) || created.Offset != TimeSpan.Zero || expires.Offset != TimeSpan.Zero
                || created > now.AddMinutes(1) || expires <= now || expires <= created || expires > created.AddHours(24)
                || value.GetProperty("PlanHashes").ValueKind != JsonValueKind.Array || value.GetProperty("PlanHashes").GetArrayLength() is < 1 or > 200)
                throw Denied("L'identité, la campagne ou la validité de l'accord sont refusées.");
            var hashes = value.GetProperty("PlanHashes").EnumerateArray().Select(item => Text(item, 64)).ToArray();
            if (hashes.Any(hash => !RemoteWindowsEvidenceProtocol.IsHash(hash)) || !hashes.Contains(PlanHash(plan), StringComparer.Ordinal))
                throw Denied("Le plan exact est absent de l'accord signé ; aucune approbation réutilisée sur un effet différent.");
        }
        catch (Pesto.Core.PestoException) { throw; }
        catch (Exception error) when (error is JsonException or FormatException or InvalidOperationException or CryptographicException
            or ArgumentException or KeyNotFoundException or DecoderFallbackException)
        { throw Denied("La politique ou la preuve de campagne ne peut pas être validée ; aucun envoi."); }
    }

    private static string Text(JsonElement value, int maximum)
    {
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { Length: > 0 } text
            || text.Length > maximum || text.Any(char.IsControl)) throw Denied("Texte de campagne invalide.");
        return text;
    }
    private static Pesto.Core.PestoException Denied(string text) => new("automation.approval", text);
}
