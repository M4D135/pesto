using System;
using System.IO;
using M4D.Admin.Common.Diagnostics;
public static class DiagnosticsTests
{
 public static int Run() {
  int checks=0;
  var buffer=new BoundedEventBuffer(2);buffer.Add("a");buffer.Add("b");buffer.Add("c");
  if(buffer.Snapshot().Length!=2 || buffer.Snapshot()[0]!="b" || buffer.Discarded!=1) throw new Exception("bounded events");checks++;
  foreach(var key in new[]{"password","token","secret","authorization","pwd"}) {
   if(Redaction.Mask(key+"=CANARY_SECRET").Contains("CANARY_SECRET"))throw new Exception("secret leaked");checks++;
  }
  foreach(var line in new[]{"password=\"CANARY_SECRET value\"", "\"token\":\"CANARY_SECRET\"", "authorization=Bearer CANARY_SECRET"}) {
   if(Redaction.Mask(line).Contains("CANARY_SECRET"))throw new Exception("quoted or bearer leak");checks++;
  }
  string path=Path.Combine(Path.GetTempPath(),"m4d-log-"+Guid.NewGuid().ToString("N"));
  try {
   using(var journal=new AsyncJournal(path,32)) {
    if(!journal.TryWrite("operation=1 token=CANARY_SECRET\\n"))throw new Exception("queue unexpectedly full");checks++;
    if(!journal.Complete(5000))throw new Exception("journal not flushed");checks++;
    if(journal.TryWrite("closed"))throw new Exception("closed queue accepted");checks++;
    if(journal.Rejected!=1)throw new Exception("rejection not counted");checks++;
   }
   if(File.ReadAllText(path).Contains("CANARY_SECRET"))throw new Exception("persisted secret");checks++;
   try{using(var journal=new AsyncJournal(path,1)){}throw new Exception("overwrote existing log");}catch(IOException){checks++;}
  } finally{if(File.Exists(path))File.Delete(path);}
  return checks;
 }
}
