import assert from 'node:assert/strict';
import { watcherPresence, watcherStopResult } from '../qualification/watcher-result.mjs';
const ident = { Pid: 42 };
const acknowledged = { CmdDone: true };
for (const malformed of [null, undefined, {}, [], { Pid: 42 }, { Pid: 42, Present: null },
  { Pid: 42, Present: 'false' }, { Pid: 42, Present: 0 }, { Pid: '42', Present: false }, { Pid: 43, Present: false }]) {
  assert.equal(watcherPresence(42, malformed), 'UNKNOWN');
  assert.equal(watcherStopResult(ident, malformed, acknowledged).stop, 'UNKNOWN');
}
assert.equal(watcherStopResult(ident, { Pid: 42, Present: true }, acknowledged).stop, 'PRESENT');
assert.equal(watcherStopResult(ident, { Pid: 42, Present: false }, { CmdErr: 'failure' }).stop, 'UNKNOWN');
const stopped = watcherStopResult(ident, { Pid: 42, Present: false }, acknowledged);
assert.equal(stopped.stop, 'STOPPED');
assert.equal(stopped.cmdDone, true);
const unacknowledged = watcherStopResult(ident, { Pid: 42, Present: false }, null);
assert.equal(unacknowledged.stop, 'STOPPED');
assert.equal(unacknowledged.cmdDone, null);
assert.match(unacknowledged.note, /non reçu/);
for (const invalidPid of [0, -1, NaN, Infinity, '42']) assert.equal(watcherPresence(invalidPid, { Pid: invalidPid, Present: false }), 'UNKNOWN');
console.log('Watcher stop verdict: malformed evidence, wrong PID, presence, contradiction and verified disappearance passed.');
