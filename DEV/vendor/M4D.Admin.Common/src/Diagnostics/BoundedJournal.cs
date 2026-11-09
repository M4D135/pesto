using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace M4D.Admin.Common.Diagnostics
{
    public sealed class BoundedEventBuffer
    {
        private readonly int capacity;
        private readonly Queue<string> items = new Queue<string>();
        private readonly object gate = new object();
        private long discarded;
        public BoundedEventBuffer(int capacity) { if (capacity < 1 || capacity > 100000) throw new ArgumentOutOfRangeException("capacity"); this.capacity = capacity; }
        public long Discarded { get { lock (gate) return discarded; } }
        public void Add(string value) { if (value == null || value.Length > 16384) throw new ArgumentException("Invalid event."); lock (gate) { if (items.Count == capacity) { items.Dequeue(); discarded++; } items.Enqueue(value); } }
        public string[] Snapshot() { lock (gate) return items.ToArray(); }
    }
    public static class Redaction
    {
        // Defence in depth; callers must pass approved fields, never serialize a credential object.
        private static readonly Regex Secrets = new Regex("(?i)(password|passwd|pwd|token|secret|authorization)([\\\"']?\\s*[=:]\\s*)([^\\r\\n;]+)", RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));
        public static string Mask(string value) { if (value == null) return String.Empty; if (value.Length > 16384) throw new ArgumentException("Event too large."); return Secrets.Replace(value, "$1$2[REDACTED]"); }
    }
    public sealed class AsyncJournal : IDisposable
    {
        private readonly BlockingCollection<string> queue;
        private readonly Thread worker;
        private readonly StreamWriter writer;
        private readonly object gate = new object();
        private Exception failure;
        private bool closing;
        private long rejected;
        public AsyncJournal(string path, int capacity)
        {
            if (capacity < 1 || capacity > 100000) throw new ArgumentOutOfRangeException("capacity");
            writer = new StreamWriter(new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read), new UTF8Encoding(false));
            queue = new BlockingCollection<string>(capacity);
            worker = new Thread(Consume); worker.IsBackground = true; worker.Name = "M4D bounded journal"; worker.Start();
        }
        public long Rejected { get { return Interlocked.Read(ref rejected); } }
        public Exception Failure { get { lock (gate) return failure; } }
        public bool TryWrite(string approvedText)
        {
            var safe = Redaction.Mask(approvedText).Replace("\r", "\\r").Replace("\n", "\\n");
            lock (gate) { if (closing || failure != null || !queue.TryAdd(safe)) { Interlocked.Increment(ref rejected); return false; } return true; }
        }
        private void Consume()
        {
            try { foreach (var line in queue.GetConsumingEnumerable()) { writer.WriteLine(line); writer.Flush(); } }
            catch (Exception exception) { lock (gate) failure = exception; }
            finally { try { writer.Dispose(); } catch (Exception exception) { lock (gate) { if (failure == null) failure = exception; } } }
        }
        public bool Complete(int timeoutMilliseconds)
        {
            if (timeoutMilliseconds < 0) throw new ArgumentOutOfRangeException("timeoutMilliseconds");
            lock (gate) { if (!closing) { closing = true; queue.CompleteAdding(); } }
            return worker.Join(timeoutMilliseconds) && Failure == null;
        }
        public void Dispose() { if (!Complete(5000)) throw new IOException("Journal completion is uncertain; inspect Failure and preserve the file.", Failure); }
    }
}
