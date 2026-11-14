using System.Text.RegularExpressions;
using System.Xml;

namespace Pesto.Engine;

/// <summary>Portable validation of the immutable V1 boot proof. CIM uptime and event TimeCreated are not substitutes.</summary>
public static partial class BootIdentity
{
    public const string Provider = "Microsoft-Windows-Kernel-General";
    public static DateTimeOffset? ReadEventStart(int eventId, string? provider, string? eventXml, DateTimeOffset now)
    {
        if (eventId != 12 || !string.Equals(provider, Provider, StringComparison.OrdinalIgnoreCase)
            || eventXml is not { Length: > 0 and <= 65536 }) return null;
        try
        {
            var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 65536 };
            using var input = new StringReader(eventXml);
            using var reader = XmlReader.Create(input, settings);
            var xml = new XmlDocument { XmlResolver = null }; xml.Load(reader);
            var nodes = xml.SelectNodes("/*[local-name()='Event']/*[local-name()='EventData']/*[local-name()='Data' and @Name='StartTime']");
            if (nodes is null || nodes.Count != 1 || nodes[0] is not { } node
                || !Regex.IsMatch(node.InnerText, @"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking)) return null;
            var started = XmlConvert.ToDateTime(node.InnerText, XmlDateTimeSerializationMode.RoundtripKind);
            if (started.Kind != DateTimeKind.Utc || started > now.UtcDateTime) return null;
            return new DateTimeOffset(started);
        }
        catch (Exception) { return null; }
    }
}
