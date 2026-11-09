using System;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using M4D.Admin.Common.IO;

public static class IOTests
{
    private static int assertions;
    private static void Check(bool ok, string label) { assertions++; if (!ok) throw new Exception(label); }
    private static void Throws<T>(Action action, string label) where T : Exception
    {
        try { action(); } catch (T) { assertions++; return; }
        throw new Exception("Expected " + typeof(T).Name + ": " + label);
    }
    private sealed class CancellingStream : MemoryStream
    {
        private readonly CancellationTokenSource cancellation;
        public CancellingStream(CancellationTokenSource source) : base(new byte[2097152]) { cancellation = source; }
        public override int Read(byte[] buffer, int offset, int count) { int n = base.Read(buffer, offset, count); cancellation.Cancel(); return n; }
    }
    public static int Run()
    {
        assertions = 0;
        string temp = Directory.Exists("/private/tmp") ? "/private/tmp" : Path.GetTempPath();
        string root = Path.Combine(temp, "m4d-io-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            string file = Path.Combine(root, "abc.txt");
            File.WriteAllBytes(file, Encoding.UTF8.GetBytes("abc"));
            Check(ContentHash.Sha256(file, CancellationToken.None) == "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD", "abc hash");
            File.WriteAllBytes(Path.Combine(root, "empty"), new byte[0]);
            Check(ContentHash.Sha256(Path.Combine(root, "empty"), CancellationToken.None) == "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855", "empty hash");
            Throws<FileNotFoundException>(delegate { ContentHash.Sha256(Path.Combine(root, "missing"), CancellationToken.None); }, "missing hash input");
            string child = Path.Combine(root, "child"); Directory.CreateDirectory(child);
            File.WriteAllBytes(Path.Combine(child, "larger"), new byte[19]);
            FootprintResult r = FileFootprint.Scan(root, 100, 30, CancellationToken.None);
            Check(r.Complete && !r.Truncated && r.Unreadable == 0, "complete tree");
            Check(r.Bytes == 22 && r.MaximumFileBytes == 19 && r.Entries == 4, "tree totals");
            Check(r.ElapsedSeconds >= 0 && r.Issues.Length == 0, "timing and issues");
            r = FileFootprint.Scan(root, 1, 30, CancellationToken.None);
            Check(!r.Complete && r.Truncated && r.Entries == 1, "strict entry budget");
            string exact = Path.Combine(root, "exact"); Directory.CreateDirectory(exact); File.WriteAllBytes(Path.Combine(exact, "one"), new byte[0]);
            Check(FileFootprint.Scan(exact, 1, 30, CancellationToken.None).Complete, "exact budget complete");
            Throws<IOException>(delegate { FileFootprint.Scan(Path.Combine(root, "missing"), 100, 1, CancellationToken.None); }, "missing root");
            Throws<IOException>(delegate { FileFootprint.Scan(file, 100, 1, CancellationToken.None); }, "file root");
            Throws<ArgumentException>(delegate { FileFootprint.Scan("relative", 100, 1, CancellationToken.None); }, "absolute path");
            Throws<ArgumentOutOfRangeException>(delegate { FileFootprint.Scan(root, 0, 1, CancellationToken.None); }, "entry bounds");
            Throws<ArgumentOutOfRangeException>(delegate { FileFootprint.Scan(root, 1, 301, CancellationToken.None); }, "time bounds");
            using (CancellationTokenSource cts = new CancellationTokenSource())
            {
                cts.Cancel();
                Throws<OperationCanceledException>(delegate { ContentHash.Sha256(file, cts.Token); }, "hash cancellation");
                Throws<OperationCanceledException>(delegate { FileFootprint.Scan(root, 100, 30, cts.Token); }, "scan cancellation");
            }
            using (CancellationTokenSource cts = new CancellationTokenSource())
            using (CancellingStream stream = new CancellingStream(cts))
            {
                Throws<OperationCanceledException>(delegate { ContentHash.Sha256(stream, cts.Token); }, "cancel between blocks");
                Check(stream.CanRead, "caller owns stream");
            }
            string atomic = Path.Combine(root, "atomic.txt");
            Check(AtomicFile.WriteWithBackup(atomic, Encoding.UTF8.GetBytes("first")) == null, "new atomic target");
            string backup = AtomicFile.WriteWithBackup(atomic, Encoding.UTF8.GetBytes("second"));
            Check(File.ReadAllText(atomic) == "second" && File.ReadAllText(backup) == "first", "replacement and preserved backup");
            Throws<ArgumentNullException>(delegate { AtomicFile.WriteWithBackup(atomic, null); }, "null payload");
            Check(File.ReadAllText(atomic) == "second", "failure preserves old content");
            File.Delete(atomic); File.Delete(backup);
            string marker = Path.Combine(root, "cancel.request"); File.WriteAllText(marker, "cancel");
            Throws<OperationCanceledException>(delegate { FileFootprint.Scan(root, 100, 30, CancellationToken.None, marker); }, "file cancellation marker");
            File.Delete(marker);
            MethodInfo link = typeof(Directory).GetMethod("CreateSymbolicLink", new Type[] { typeof(string), typeof(string) });
            if (link == null) Console.WriteLine("SKIP symbolic links: creation API unavailable (not a Windows validation).");
            else
            {
                string alias = Path.Combine(root, "alias");
                try { link.Invoke(null, new object[] { alias, child }); }
                catch (TargetInvocationException ex) { if (ex.InnerException is UnauthorizedAccessException || ex.InnerException is PlatformNotSupportedException) { Console.WriteLine("SKIP symbolic links: permission/platform unavailable."); return assertions; } throw; }
                r = FileFootprint.Scan(root, 100, 30, CancellationToken.None);
                Check(!r.Complete && r.OtherLinks == 1 && r.Bytes == 22, "directory symlink skipped");
                Throws<IOException>(delegate { FileFootprint.Scan(alias, 100, 30, CancellationToken.None); }, "reparse root refused");
                string nested = Path.Combine(child, "nested"); Directory.CreateDirectory(nested);
                Throws<IOException>(delegate { FileFootprint.Scan(Path.Combine(alias, "nested"), 100, 30, CancellationToken.None); }, "reparse ancestor refused");
                Directory.Delete(alias);
            }
            return assertions;
        }
        finally { Directory.Delete(root, true); }
    }
}
