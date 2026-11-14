using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Threading;

namespace M4D.Admin.Common.Core
{
    /// <summary>Injectable byte source for deterministic tests; products use the system source.</summary>
    public interface IRandomSource
    {
        uint NextUInt32();
    }

    public static class RandomSelection
    {
        private sealed class SystemRandomSource : IRandomSource
        {
            private readonly RandomNumberGenerator generator = RandomNumberGenerator.Create();
            private readonly object gate = new object();
            private readonly byte[] bytes = new byte[4096];
            private int position = 4096;

            public uint NextUInt32()
            {
                lock (gate)
                {
                    if (position == bytes.Length) { generator.GetBytes(bytes); position = 0; }
                    uint value = BitConverter.ToUInt32(bytes, position);
                    position += 4;
                    return value;
                }
            }
        }

        private static readonly IRandomSource systemSource = new SystemRandomSource();

        public static int NextIndex(int count)
        {
            return NextIndex(count, systemSource);
        }

        /// <summary>Uniform index in [0, count). Rejection avoids modulo bias.</summary>
        public static int NextIndex(int count, IRandomSource source)
        {
            if (count <= 0) throw new ArgumentOutOfRangeException("count", "At least one candidate is required.");
            if (source == null) throw new ArgumentNullException("source");
            if (count == 1) return 0;
            const ulong range = 1UL << 32;
            ulong limit = range - range % (uint)count;
            uint value;
            do { value = source.NextUInt32(); } while ((ulong)value >= limit);
            return (int)(value % (uint)count);
        }

        public static T[] Sample<T>(IEnumerable<T> candidates, int count)
        {
            return Sample(candidates, count, systemSource);
        }

        /// <summary>
        /// Uniform sample without replacement of an entire eligible stream, independent of display pages.
        /// Candidates must already be filtered and distinct. Memory is bounded by the requested sample.
        /// An enumeration error propagates; a partial sample is never presented as complete.
        /// </summary>
        public static T[] Sample<T>(IEnumerable<T> candidates, int count, IRandomSource source)
        {
            return Sample(candidates, count, source, CancellationToken.None);
        }

        public static T[] Sample<T>(IEnumerable<T> candidates, int count, CancellationToken cancellation)
        {
            return Sample(candidates, count, systemSource, cancellation);
        }

        public static T[] Sample<T>(IEnumerable<T> candidates, int count, IRandomSource source, CancellationToken cancellation)
        {
            if (candidates == null) throw new ArgumentNullException("candidates");
            if (count < 0) throw new ArgumentOutOfRangeException("count");
            if (source == null) throw new ArgumentNullException("source");
            cancellation.ThrowIfCancellationRequested();
            if (count == 0) return new T[0];
            var selected = new List<T>();
            int seen = 0;
            foreach (T candidate in candidates)
            {
                cancellation.ThrowIfCancellationRequested();
                seen = checked(seen + 1);
                if (selected.Count < count) selected.Add(candidate);
                else
                {
                    int index = NextIndex(seen, source);
                    if (index < count) selected[index] = candidate;
                }
            }
            for (int i = selected.Count - 1; i > 0; i--)
            {
                cancellation.ThrowIfCancellationRequested();
                int j = NextIndex(i + 1, source);
                T swap = selected[i]; selected[i] = selected[j]; selected[j] = swap;
            }
            return selected.ToArray();
        }
    }
}
