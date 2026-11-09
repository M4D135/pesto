// A command acknowledgement is never proof that the recorded process disappeared.
export function watcherPresence(expectedPid, observation) {
  if (!Number.isSafeInteger(expectedPid) || expectedPid <= 0 ||
      !observation || typeof observation !== 'object' || Array.isArray(observation) ||
      observation.Pid !== expectedPid || typeof observation.Present !== 'boolean') return 'UNKNOWN';
  return observation.Present ? 'PRESENT' : 'ABSENT';
}

export function watcherStopResult(ident, observation, acknowledgement) {
  const presence = watcherPresence(ident?.Pid, observation);
  const base = { ident, goneCheck: observation ?? null };
  if (presence === 'UNKNOWN') return { ...base, stop: 'UNKNOWN', reason: 'Preuve native absente, mal formée ou PID différent.' };
  if (presence === 'PRESENT') return { ...base, stop: 'PRESENT', reason: 'Le processus enregistré est encore présent.' };
  if (acknowledgement?.CmdErr) return { ...base, stop: 'UNKNOWN', reason: 'Disparition observée mais erreur de commande contradictoire.', cmdErr: acknowledgement.CmdErr };
  const confirmed = acknowledgement?.CmdDone === true;
  return { ...base, stop: 'STOPPED', cmdDone: confirmed ? true : null,
    ...(confirmed ? {} : { note: 'Disparition prouvée par CIM ; accusé de commande non reçu.' }) };
}
