namespace Pesto.Engine;

public static partial class BootIdentity
{
    /// <summary>Shared constant for local, remote SYSTEM and reservation readers. Merely exposing the text performs no IO.</summary>
    public const string ScriptSource = """
function Get-PestoStableBootUtc{
  $events=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-General';Id=12} -MaxEvents 1 -ErrorAction Stop)
  if($events.Count -ne 1 -or $events[0].Id -ne 12 -or $events[0].ProviderName -ine 'Microsoft-Windows-Kernel-General'){throw 'Événement de démarrage Windows non déterminé.'}
  $text=$events[0].ToXml()
  if(-not $text -or $text.Length -gt 65536){throw 'Événement de démarrage Windows invalide.'}
  $settings=New-Object Xml.XmlReaderSettings
  $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=65536
  $input=New-Object IO.StringReader($text)
  $reader=[Xml.XmlReader]::Create($input,$settings)
  try{
    $xml=New-Object Xml.XmlDocument;$xml.XmlResolver=$null;$xml.Load($reader)
    $nodes=$xml.SelectNodes('/*[local-name()="Event"]/*[local-name()="EventData"]/*[local-name()="Data" and @Name="StartTime"]')
    if($nodes.Count -ne 1 -or $nodes[0].InnerText -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$'){throw 'Date de démarrage Windows invalide.'}
    $started=[Xml.XmlConvert]::ToDateTime($nodes[0].InnerText,[Xml.XmlDateTimeSerializationMode]::RoundtripKind).ToUniversalTime()
    if($started -gt [DateTime]::UtcNow){throw 'Chronologie Windows incohérente ; aucune nouvelle opération autorisée.'}
    return $started.ToString('o')
  }finally{$reader.Dispose();$input.Dispose()}
}

""";
}
