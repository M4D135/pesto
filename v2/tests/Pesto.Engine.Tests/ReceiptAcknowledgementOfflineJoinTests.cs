using System.Text;
using Pesto.Engine;

namespace Pesto.Engine.Tests;

/// <summary>A real portable ODJ event chain, only temporary inert fixture bytes; no djoin/native process.</summary>
internal sealed class ReceiptAcknowledgementOfflineJoinTests
{
    [Test]
    public void GenericAcknowledgementCannotConsumeAnOfflineJoinBarrierOrAuthorizeBlobReplay()
    {
        var gp = new GpFixture(); var clock = new FixedClock();
        try
        {
            var protectedFixture = Encoding.UTF8.GetBytes("inert protected fixture, not a domain blob");
            var binding = new OfflineJoinBinding(new('a', 64), "FIXTUREPC", "example.local", AttributeFixture.Guid,
                AttributeFixture.Ou, "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", new('c', 64), OfflineJoinRules.Hash(protectedFixture),
                clock.GetUtcNow(), clock.GetUtcNow().AddHours(1), clock.GetUtcNow().AddHours(-2), "WORKGROUP", 0, false);
            var store = new OfflineJoinStore(gp.Root, ConfigurationAccessMode.Live, clock: clock);
            var importing = store.Begin(binding); store.WriteProtected(importing, protectedFixture);
            var imported = store.Append(importing, "Imported");
            var baseline = new OfflineJoinLocalState(binding.Computer, binding.Computer, binding.Computer, binding.MachineId,
                "WORKGROUP", false, 0, binding.InitialBootUtc, true, null);
            var requested = store.Append(imported, "Requested", "receipt-odj-ack-fixture", "odj-plan-fixture", workerMayRun: true, baseline: baseline);
            var receipt = OfflineJoinReceipt.Create(requested); var path = gp.AdapterRaw(requested.Event.ReceiptId!, receipt.ToJsonString());
            Check.True(GpHistory.Read(gp.Root).Entries.Single().Readable, "The new receipt is valid ODJ evidence, not merely malformed JSON");
            var before = File.ReadAllBytes(path); var eventSha = store.Read(binding.Id)!.Sha256;
            var refusal = Check.Pesto(() => ReceiptAcknowledgementSource.Read(gp.Root, requested.Event.ReceiptId!),
                "receipt.acknowledgement", "General acknowledgement does not cover ODJ worker and blob evidence");
            Check.Contains("--offline-join", refusal.Message, "The operator is directed to the dedicated observation");
            Check.True(before.AsSpan().SequenceEqual(File.ReadAllBytes(path)), "Receipt bytes are unchanged");
            Check.Equal(eventSha, store.Read(binding.Id)!.Sha256, "Requested tombstone and event chain remain intact");
            Check.Pesto(() => store.Begin(binding), "offlineJoin.duplicate", "A general operator decision cannot make the same blob reusable");
        }
        finally { Directory.Delete(gp.Root, true); }
    }
}
