using System.Text.Json;
var root=Path.Combine(Path.GetTempPath(),"Pesto-atomic-probe-"+Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
var results=new List<object>();
try {
 foreach(var share in new[]{FileShare.ReadWrite|FileShare.Delete,FileShare.Read|FileShare.Delete,FileShare.Delete}) {
  foreach(var replace in new[]{false,true}) {
   var target=Path.Combine(root,Guid.NewGuid().ToString("N")+".json");var source=target+".tmp";
   File.WriteAllText(target,"old");File.WriteAllText(source,"new");
   string error=null;string code=null;
   using(var held=new FileStream(target,FileMode.Open,FileAccess.Read,share)) {
    try{if(replace)File.Replace(source,target,null);else File.Move(source,target,true);}catch(Exception ex){error=ex.GetType().Name;code=ex.HResult.ToString("X8");}
   }
   var after=File.ReadAllText(target);
   if(File.Exists(source))File.Move(source,target,true);
   results.Add(new{share=share.ToString(),operation=replace?"Replace":"MoveOverwrite",error,hResult=code,contentWhileHeld=after,contentAfterClose=File.ReadAllText(target)});
  }
 }
 Console.WriteLine(JsonSerializer.Serialize(new{diagnosticOnly=true,runtime=Environment.Version.ToString(),os=Environment.OSVersion.ToString(),results},new JsonSerializerOptions{WriteIndented=true}));
} finally { Directory.Delete(root,true); }
