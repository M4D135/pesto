using System;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Threading;

namespace M4D.Admin.Common.Wpf
{
    // Explicitly separate from Core: only consumers using WPF load this assembly.
    public static class Presentation
    {
        public static double Bound(double value, double minimum, double maximum)
        {
            if (Double.IsNaN(minimum) || Double.IsNaN(maximum) || Double.IsInfinity(minimum) || Double.IsInfinity(maximum) || minimum > maximum) throw new ArgumentException("Invalid bounds.");
            if (Double.IsNaN(value) || Double.IsInfinity(value)) return minimum;
            return Math.Max(minimum, Math.Min(maximum, value));
        }
        public static void RefreshExistingPeer(UIElement element)
        {
            if (element == null) throw new ArgumentNullException("element");
            element.Dispatcher.VerifyAccess();
            var peer = UIElementAutomationPeer.FromElement(element);
            if (peer == null) return;
            peer.ResetChildrenCache(); peer.InvalidatePeer();
        }
    }
    public sealed class DispatcherCoalescer : IDisposable
    {
        private readonly Dispatcher dispatcher;
        private readonly Action action;
        private DispatcherOperation pending;
        private bool disposed;
        public DispatcherCoalescer(Dispatcher dispatcher, Action action)
        {
            if (dispatcher == null || action == null) throw new ArgumentNullException();
            this.dispatcher = dispatcher; this.action = action;
        }
        public void Request()
        {
            dispatcher.VerifyAccess();
            if (disposed || (pending != null && pending.Status == DispatcherOperationStatus.Pending)) return;
            pending = dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(delegate { pending = null; if (!disposed) action(); }));
        }
        public void Dispose() { dispatcher.VerifyAccess(); disposed = true; if (pending != null) pending.Abort(); pending = null; }
    }
}
