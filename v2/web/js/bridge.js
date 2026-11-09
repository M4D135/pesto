// The browser preview never falls back after an error from the native host.
// A UI deadline must not abandon a native mutation, a long pack copy, or a file dialog while it
// can still finish. Those operations settle from the host's own bounded steps and durable receipts.
const nativeCompletion = new Set([
  'operation.prepare', 'operation.execute', 'queue.prepare', 'queue.execute', 'reservations.execute', 'coordination.apply',
  'receipts.reconcile', 'receipts.prepareMove', 'receipts.prepareAcknowledgement', 'receipts.acknowledge',
  'receipts.prepareRestart', 'receipts.restart', 'configuration.export', 'configuration.previewImport',
  'configuration.setDefault', 'references.preview', 'updates.inspect', 'updates.prepare',
  'attributes.prepare', 'attributes.apply', 'attributes.observe',
  'offlineJoin.open', 'offlineJoin.import', 'offlineJoin.prepare', 'offlineJoin.apply', 'offlineJoin.observe',
]);
export function createBridge({ channel, mock, timeoutMs = 120_000, clock = globalThis } = {}) {
  const pending = new Map();
  let counter = 0;
  const error = (code, message) => Object.assign(new Error(message), { code });
  const receive = (event) => {
    const message = event.data;
    if (!message || typeof message !== 'object') return;
    const request = pending.get(message.id);
    if (!request) return;
    if (!['result', 'error'].includes(message.kind)) return;
    pending.delete(message.id); clock.clearTimeout(request.timer);
    if (message.kind === 'result') request.resolve(message.data);
    else {
      const refusal = error(message.error?.code || 'bridge.error', message.error?.message || 'Le moteur a refusé la demande.');
      // A named refusal carries what the operator needs: a retryable refusal is not a lost call,
      // and the operation name says which screen action was never started.
      if (typeof message.error?.retryable === 'boolean') refusal.retryable = message.error.retryable;
      if (typeof message.op === 'string') refusal.operation = message.op;
      request.reject(refusal);
    }
  };
  channel?.addEventListener('message', receive);
  return {
    async call(op, args = {}) {
      if (!channel) {
        if (!mock) throw error('bridge.unavailable', 'Le moteur Pesto n’est pas connecté.');
        return mock(op, args);
      }
      const id = `p${++counter}`;
      const message = { id, op, args };
      if (JSON.stringify(message).length > 1_048_576) throw error('message.size', 'Cette demande dépasse la taille autorisée.');
      return new Promise((resolve, reject) => {
        const timer = nativeCompletion.has(op) ? null : clock.setTimeout(() => {
          pending.delete(id);
          reject(error('bridge.timeout', 'Le moteur n’a pas répondu. Le résultat peut être inconnu : consultez les interventions avant toute nouvelle action.'));
        }, timeoutMs);
        pending.set(id, { resolve, reject, timer });
        try { channel.postMessage(message); }
        catch { clock.clearTimeout(timer); pending.delete(id); reject(error('bridge.closed', 'La communication avec le moteur est interrompue.')); }
      });
    },
    close() {
      channel?.removeEventListener?.('message', receive);
      for (const item of pending.values()) { clock.clearTimeout(item.timer); item.reject(error('bridge.closed', 'La fenêtre a fermé sa connexion au moteur.')); }
      pending.clear();
    },
  };
}
let transport;
export async function call(op, args = {}) {
  if (!transport) {
    const channel = globalThis.window?.chrome?.webview;
    // A missing host means an explicit, visibly labelled browser simulation only.
    const simulator = channel ? null : (await import('./simulation.js')).browserSimulation;
    transport = createBridge({ channel, mock: simulator ? (name, values) => simulator.invoke(name, values) : null });
  }
  return transport.call(op, args);
}
