// Pure parsing of operator input for the « Plusieurs postes » screen (mission Pesto v2) : pasted list and local CSV.
// No DOM, no bridge, no side effect. The page shows every returned line as-is (aperçu) BEFORE any queue.add, and the
// engine stays the sole authority : this module only rejects obviously malformed lines and enforces the bounded size.
// It never consults the directory and never invents a name, a site or a service.
export const MAX_ROWS = 50; // engine queue.limit : queue.add refuses beyond this

// Same shape as the engine's final-name check : 15 characters max, letters, digits, inner dashes only.
export const COMPUTER_NAME_RE = /^(?=.{1,15}$)[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?$/;
const TYPE_RE = /^[PSV]$/;
const SERVICE_RE = /^[A-Z0-9]{1,10}$/;
const TOKEN_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const HEADERS = ['name', 'nom', 'poste', 'computer', 'hostname', 'ordinateur'];

const emptyIssue = (reason) => ({ line: 0, value: '', reason });

function dedupeLimit(collected, limit, issues, kind) {
  const names = [];
  const seen = new Set();
  for (const item of collected) {
    const key = item.name.toUpperCase();
    if (seen.has(key)) { issues.push({ line: item.line, value: item.value, reason: 'Doublon ignoré (déjà présent plus haut).' }); continue; }
    seen.add(key);
    names.push(item);
  }
  const truncated = names.length > limit;
  if (truncated) issues.push(emptyIssue(`Trop de ${kind} : seuls les ${limit} premiers sont retenus (limite de la file côté moteur).`));
  return { kept: names.slice(0, limit), truncated };
}

/**
 * Pasted list : one computer name per line. Blank lines and « # » comments are skipped, names are upper-cased,
 * malformed and duplicate lines are reported with their line number, the result is bounded to `limit`.
 * @returns {{ names: string[], issues: Array<{line: number, value: string, reason: string}>, truncated: boolean }}
 */
export function parsePastedList(text, { limit = MAX_ROWS } = {}) {
  const issues = [];
  const collected = [];
  const lines = String(text ?? '').replace(/\uFEFF/, '').split(/\r?\n/);
  lines.forEach((raw, index) => {
    const value = raw.trim();
    if (!value || value.startsWith('#')) return;
    const name = value.toUpperCase();
    if (!COMPUTER_NAME_RE.test(name)) {
      issues.push({ line: index + 1, value, reason: 'Nom de poste invalide : 1 à 15 caractères (lettres, chiffres, tirets intérieurs), sans espace.' });
      return;
    }
    collected.push({ name, value, line: index + 1 });
  });
  const { kept, truncated } = dedupeLimit(collected, limit, issues, 'postes');
  if (!kept.length && !issues.some((i) => i.line > 0)) issues.push(emptyIssue('Aucun poste valide dans cette liste.'));
  return { names: kept.map((k) => k.name), issues, truncated };
}

function splitCells(line, delim) {
  const out = [];
  let cur = '';
  let quoted = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i += 1; } else quoted = false;
      } else cur += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === delim) { out.push(cur); cur = ''; }
    else cur += ch;
  }
  out.push(cur);
  return out;
}

/**
 * Local CSV : columns name;type;site;service (comma or semicolon, optional header, optional quoted cells).
 * type/site/service are optional naming hints validated on shape only — the engine validates them again against the
 * real configuration. A malformed line is reported and skipped (validation ligne à ligne), never guessed.
 * @returns {{ rows: Array<{name: string, type: string|null, site: string|null, service: string|null, line: number}>,
 *   issues: Array<{line: number, value: string, reason: string}>, truncated: boolean }}
 */
export function parseQueueCsv(text, { limit = MAX_ROWS } = {}) {
  const issues = [];
  const collected = [];
  const lines = String(text ?? '').replace(/\uFEFF/, '').split(/\r?\n/);
  const nonEmpty = lines.map((raw, index) => [raw.trim(), index + 1]).filter(([raw]) => raw && !raw.startsWith('#'));
  if (!nonEmpty.length) return { rows: [], issues: [emptyIssue('Fichier CSV vide ou sans donnée exploitable.')], truncated: false };
  const [firstLine] = nonEmpty[0];
  const delim = (firstLine.split(';').length >= firstLine.split(',').length) ? ';' : ',';
  let start = 0;
  if (HEADERS.includes(String(splitCells(firstLine, delim)[0] ?? '').trim().toLowerCase())) start = 1;
  for (let k = start; k < nonEmpty.length; k += 1) {
    const [raw, line] = nonEmpty[k];
    const cells = splitCells(raw, delim).map((c) => c.trim());
    const [rawName = '', rawType = '', rawSite = '', rawService = '', ...extra] = cells;
    const problems = [];
    if (extra.length) problems.push(`${extra.length} colonne(s) en trop : seules name${delim}type${delim}site${delim}service sont admises`);
    const name = rawName.toUpperCase();
    if (!COMPUTER_NAME_RE.test(name)) problems.push('nom de poste invalide (1 à 15 caractères : lettres, chiffres, tirets intérieurs)');
    const type = rawType ? rawType.toUpperCase() : null;
    if (type && !TYPE_RE.test(type)) problems.push('type invalide : P, S ou V attendu');
    if (rawSite && !TOKEN_RE.test(rawSite)) problems.push('site invalide');
    const service = rawService ? rawService.toUpperCase() : null;
    if (service && !SERVICE_RE.test(service)) problems.push('service invalide : 1 à 10 caractères alphanumériques');
    if (problems.length) { issues.push({ line, value: raw, reason: `${problems.join(' ; ')}.` }); continue; }
    collected.push({ name, value: raw, line, type, site: rawSite || null, service });
  }
  const { kept, truncated } = dedupeLimit(collected, limit, issues, 'lignes valides');
  if (!kept.length && !issues.some((i) => i.line > 0)) issues.push(emptyIssue('Aucune ligne valide dans ce CSV.'));
  return { rows: kept.map((k) => ({ name: k.name, type: k.type, site: k.site, service: k.service, line: k.line })), issues, truncated };
}
