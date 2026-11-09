using System;
using System.Collections.Generic;
using System.Threading;
using M4D.Admin.Common.Core;

namespace M4D.Admin.Common.Tests
{
    public static class CoreTests
    {
        private sealed class Sequence : IRandomSource
        {
            private readonly uint[] values;
            private int position;
            public Sequence(params uint[] values) { this.values = values; }
            public int Calls { get { return position; } }
            public uint NextUInt32()
            {
                if (position >= values.Length) throw new InvalidOperationException("Test random stream exhausted.");
                return values[position++];
            }
        }

        private static int checks;
        private static void Assert(bool condition, string detail)
        {
            checks++;
            if (!condition) throw new InvalidOperationException(detail);
        }

        private static void Throws<T>(Action action) where T : Exception
        {
            bool caught = false;
            try { action(); } catch (T) { caught = true; }
            Assert(caught, "Expected " + typeof(T).Name);
        }

        private static IEnumerable<int> Broken()
        {
            yield return 1;
            throw new InvalidOperationException("Incomplete input");
        }

        public static int Run()
        {
            checks = 0;
            Throws<ArgumentOutOfRangeException>(() => RandomSelection.NextIndex(0));
            Throws<ArgumentOutOfRangeException>(() => RandomSelection.NextIndex(-1));
            Throws<ArgumentNullException>(() => RandomSelection.NextIndex(2, null));
            var single = new Sequence();
            Assert(RandomSelection.NextIndex(1, single) == 0 && single.Calls == 0, "Single candidate consumes no random value.");
            var rejection = new Sequence(uint.MaxValue, 999);
            Assert(RandomSelection.NextIndex(1000, rejection) == 999 && rejection.Calls == 2, "Reject the biased tail before reduction.");
            Assert(RandomSelection.NextIndex(2, new Sequence(uint.MaxValue)) == 1, "Power-of-two range has no rejection tail.");
            Assert(RandomSelection.NextIndex(int.MaxValue, new Sequence(uint.MaxValue, 2147483646)) == 2147483646, "Large bound and tail rejection.");
            Assert(RandomSelection.Sample(new int[0], 3).Length == 0, "Empty eligible pool.");
            Assert(RandomSelection.Sample(new[] { 1 }, 3)[0] == 1, "Fewer candidates than requested.");
            Throws<ArgumentNullException>(() => RandomSelection.Sample<int>(null, 1));
            Throws<ArgumentOutOfRangeException>(() => RandomSelection.Sample(new[] { 1 }, -1));
            Throws<InvalidOperationException>(() => RandomSelection.Sample(Broken(), 1));
            // Every candidate, including beyond an arbitrary display page, can replace the reservoir.
            var all = new List<int>();
            for (int i = 1; i <= 999; i++) all.Add(i);
            var zeroes = new uint[998];
            Assert(RandomSelection.Sample(all, 1, new Sequence(zeroes))[0] == 999, "No five-item or page-size truncation.");
            var five = RandomSelection.Sample(all, 5);
            Assert(five.Length == 5 && new HashSet<int>(five).Count == 5, "No replacement duplicates.");
            Assert(RandomSelection.Sample(Broken(), 0).Length == 0, "Zero count does not enumerate.");
            using (var stop = new CancellationTokenSource())
            {
                stop.Cancel();
                Throws<OperationCanceledException>(() => RandomSelection.Sample(all, 5, stop.Token));
                Throws<OperationCanceledException>(() => RandomSelection.Sample(new int[0], 0, stop.Token));
            }
            // Fixed inputs exhaust all residues once; this is deterministic, not a flaky frequency threshold.
            for (uint i = 0; i < 999; i++)
                Assert(RandomSelection.NextIndex(999, new Sequence(i)) == (int)i, "Every residue is reachable.");
            for (int i = 0; i < 1000; i++)
            {
                int value = RandomSelection.NextIndex(999);
                Assert(value >= 0 && value < 999, "System source remains inside bounds.");
            }
            Assert(Validation.OptionalText(null, "x", 1) == "", "null optional text");
            Throws<ArgumentException>(() => Validation.RequiredText(" ", "x", 1));
            Throws<ArgumentException>(() => Validation.RequiredText("a\0b", "x", 4));
            Throws<ArgumentException>(() => Validation.OptionalText("abcd", "x", 3));
            Throws<ArgumentOutOfRangeException>(() => new OperationResult("id", (ResultKind)99, 0, ""));
            var record = new OperationResult("operation-1", ResultKind.Uncertain, 97, "échec 日本語");
            var encoded = BoundedJson.Serialize(record, 4096);
            var decoded = BoundedJson.Deserialize<OperationResult>(encoded, 4096);
            Assert(decoded.Kind == ResultKind.Uncertain && decoded.Message == record.Message, "result roundtrip");
            Throws<System.IO.InvalidDataException>(() => BoundedJson.Serialize(record, 2));
            Throws<System.IO.InvalidDataException>(() => BoundedJson.Deserialize<OperationResult>(encoded, 2));
            Throws<System.Text.DecoderFallbackException>(() => BoundedJson.Deserialize<string>(new byte[] { 255 }, 16));
            // Generated Unicode/JSON corpus: valid scalar strings, escapes and size boundaries.
            for (int n = 0; n < 300; n++) {
                var text = "quote\" slash\\ newline\n é 日本語 " + n.ToString();
                var bytes = BoundedJson.Serialize(text, 2048);
                Assert(BoundedJson.Deserialize<string>(bytes, bytes.Length) == text, "generated JSON roundtrip");
                Throws<System.IO.InvalidDataException>(() => BoundedJson.Deserialize<string>(bytes, bytes.Length - 1));
            }
            return checks;
        }
    }
}
