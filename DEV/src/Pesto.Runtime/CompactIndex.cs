using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
namespace Pesto.Inventory {
 public sealed class CompactIndex {
  public sealed class Row {
   public int SourceIndex; public string Name; public string Type; public string Prefix; public string Site;
   public string Service; public int Number; public string NumberText; public string Base; public string Series; public string Label;
  }
  public sealed class Built {
   public Dictionary<string,HashSet<int>> ByBase; public Dictionary<string,HashSet<string>> BySite; public Row[] Rows;
  }
  public static Built Build(string[] names,string pattern,int length,int numberOffset,int numberWidth) {
   var byBase=new Dictionary<string,HashSet<int>>(StringComparer.OrdinalIgnoreCase);
   var bySite=new Dictionary<string,HashSet<string>>(StringComparer.OrdinalIgnoreCase);
   var rows=new List<Row>();
   var regex=new Regex(pattern);
   for(int i=0;i<names.Length;i++) {
    string name=names[i];
    if(string.IsNullOrWhiteSpace(name)) continue;
    string value=name.Trim().ToUpperInvariant();
    if(value.Length!=length) continue;
    Match m=regex.Match(value);
    if(!m.Success) continue;
    string numberText=m.Groups["Number"].Value;
    int number=int.Parse(numberText,CultureInfo.InvariantCulture);
    string type=m.Groups["Type"].Value;
    string baseName=value.Remove(numberOffset,numberWidth);
    HashSet<int> numbers; if(!byBase.TryGetValue(baseName,out numbers)) {numbers=new HashSet<int>();byBase[baseName]=numbers;}
    numbers.Add(number);
    string site=m.Groups["Site"].Value;
    string service=m.Groups["Service"].Value;
    HashSet<string> services; if(!bySite.TryGetValue(site,out services)) {services=new HashSet<string>(StringComparer.OrdinalIgnoreCase);bySite[site]=services;}
    services.Add(service);
    Row row=new Row();
    row.SourceIndex=i; row.Name=m.Value; row.Type=type; row.Prefix=m.Groups["Prefix"].Value; row.Site=site;
    row.Service=service; row.Number=number; row.NumberText=numberText; row.Base=baseName;
    row.Series=baseName.Insert(numberOffset,new string('#',numberWidth));
    row.Label=(type=="P")?"Portable":(type=="S")?"Fixe":"Virtuel";
    rows.Add(row);
   }
   Built built=new Built(); built.ByBase=byBase; built.BySite=bySite; built.Rows=rows.ToArray();
   return built;
  }
 }
}
