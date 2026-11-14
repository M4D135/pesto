// Journal de confort borné. Les reçus de mutation ne passent jamais par cette file.
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Pesto.Runtime {
    public sealed class AsyncAuditWriter : IDisposable {
        private sealed class Entry { public string Text; public TaskCompletionSource<bool> Barrier; }
        private readonly BlockingCollection<Entry> queue;
        private readonly Thread thread;
        private readonly string path;
        private string error = "";
        private long accepted, written, dropped;
        private int closing;
        public AsyncAuditWriter(string file, int capacity) {
            if (String.IsNullOrWhiteSpace(file) || !Path.IsPathRooted(file)) throw new ArgumentException("Chemin absolu requis.");
            if (capacity < 64 || capacity > 10000) throw new ArgumentOutOfRangeException("capacity");
            path = Path.GetFullPath(file);
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new IOException("Lien de journal refusé.");
            queue = new BlockingCollection<Entry>(new ConcurrentQueue<Entry>(), capacity);
            thread = new Thread(Run) { IsBackground = true, Name = "Pesto audit writer" };
            thread.Start();
        }
        public string Error { get { return Volatile.Read(ref error); } }
        public int Pending { get { return queue.Count; } }
        public long Written { get { return Interlocked.Read(ref written); } }
        public long Dropped { get { return Interlocked.Read(ref dropped); } }
        public bool TryWrite(string text) {
            if (text == null) return true;
            if (text.Length > 32768) text = text.Substring(0, 32768) + " [trace tronquée]\r\n";
            if (Volatile.Read(ref closing) != 0 || Error.Length != 0) { Interlocked.Increment(ref dropped); return false; }
            try {
                if (!queue.TryAdd(new Entry { Text = text }, 0)) { Interlocked.Increment(ref dropped); return false; }
                Interlocked.Increment(ref accepted); return true;
            } catch (InvalidOperationException) { Interlocked.Increment(ref dropped); return false; }
        }
        public bool Flush(int milliseconds) {
            if (milliseconds < 0 || milliseconds > 10000 || Error.Length != 0 || Volatile.Read(ref closing) != 0) return false;
            var barrier = new TaskCompletionSource<bool>();
            try {
                if (!queue.TryAdd(new Entry { Barrier = barrier }, 0)) return false;
                return barrier.Task.Wait(milliseconds) && barrier.Task.Result && Error.Length == 0;
            } catch (InvalidOperationException) { return false; }
        }
        private void Run() {
            try {
                foreach (var entry in queue.GetConsumingEnumerable()) {
                    if (entry.Barrier != null) { entry.Barrier.TrySetResult(Error.Length == 0); continue; }
                    if (Error.Length != 0) { Interlocked.Increment(ref dropped); continue; }
                    try {
                        // Ouverture limitée à une écriture ; les erreurs restent visibles, jamais ignorées.
                        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new IOException("Lien de journal refusé.");
                        byte[] bytes = new UTF8Encoding(false).GetBytes(entry.Text);
                        using (var stream = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite)) {
                            stream.Write(bytes, 0, bytes.Length); stream.Flush();
                        }
                        Interlocked.Increment(ref written);
                    } catch (Exception ex) { Interlocked.CompareExchange(ref error, ex.GetType().Name + ": " + ex.Message, ""); Interlocked.Increment(ref dropped); }
                }
            } catch (Exception ex) { Interlocked.CompareExchange(ref error, ex.GetType().Name + ": " + ex.Message, ""); }
            finally { Entry entry; while(queue.TryTake(out entry)) { if(entry.Barrier != null) entry.Barrier.TrySetResult(false); else Interlocked.Increment(ref dropped); } }
        }
        public bool Close(int milliseconds) {
            if (Interlocked.Exchange(ref closing, 1) == 0) queue.CompleteAdding();
            bool ended = thread.Join(Math.Max(0, Math.Min(10000, milliseconds)));
            return ended && Error.Length == 0 && Dropped == 0;
        }
        public void Dispose() { Close(2000); }
    }
}
