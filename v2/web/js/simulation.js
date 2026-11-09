// Browser-only demonstration. No fetch, persistence, native API or real directory operation.
const clone = (value) => structuredClone(value);
const problem = (code, message) => { throw Object.assign(new Error(message), { code }); };
const kinds = ['join', 'rename', 'move', 'renameMove'];
// Labels displayed by the receipt cards (writeflow.js KIND_LABEL, interventions.js STATUS), searchable here.
const KIND_TEXT = { join: 'Jonction', rename: 'Renommage', move: 'Déplacement', renameMove: 'Renommage + déplacement', attributes: 'Attributs AD', offlineJoin: 'Jonction hors ligne' };
const STATUS_TEXT = { simulated: 'Simulé', succeeded: 'Réussi', pendingRestart: 'Redémarrage en attente', refused: 'Refusé', uncertain: 'Incertain' };
const fold = (value) => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const scenarios = [
  { id: 'standard', label: 'Nouveau poste', description: 'Calculez un nom puis joignez le poste fictif au domaine. Le redémarrage reste explicite.', page: 'ajouter' },
  { id: 'joined', label: 'Poste déjà joint', description: 'Renommez un poste, changez de site ou préparez un lot de postes fictifs.', page: 'unposte' },
  { id: 'pendingRestart', label: 'Redémarrage en attente', description: 'Un renommage fictif est accepté. Le redémarrage fictif termine uniquement la simulation.', page: 'interventions' },
  { id: 'partialMove', label: 'Déplacement restant', description: 'Redémarrez fictivement puis préparez le déplacement restant. Le reçu initial conserve son état partiel.', page: 'interventions' },
  { id: 'denied', label: 'Droits insuffisants', description: 'La prochaine écriture confirmée sera refusée sans changement du poste fictif.', page: 'unposte' },
  { id: 'uncertain', label: 'Résultat incertain', description: 'La prochaine écriture rendra un reçu incertain et arrêtera le lot. Il ne deviendra jamais un succès après redémarrage.', page: 'plusieurspostes' },
  { id: 'nameCollision', label: 'Nom pris entre deux étapes', description: 'Le nom devient occupé à la préparation. Un nouvel aperçu et une nouvelle confirmation sont nécessaires.', page: 'ajouter' },
  { id: 'directoryOffline', label: 'Annuaire indisponible', description: 'Les lectures fictives échouent explicitement, sans inventer de compteur ou de nom disponible.', page: 'accueil' },
];
export function createSimulation({ now = () => Date.now() } = {}) {
  let serial = 0, revision = 0, queueVersion = 0, generation = 0, scenario = 'standard', nextOutcome = null;
  const instanceId = globalThis.crypto.randomUUID().replaceAll('-', '');
  const id = (prefix) => `${prefix}-${instanceId}-${++serial}`;
  const iso = () => new Date(now()).toISOString();
  const expiry = () => new Date(now() + 5 * 60_000).toISOString();
  const sites = [
    { id: 'paris', name: 'Paris', code: 'PA', ou: 'OU=Paris,OU=Postes,DC=example,DC=local' },
    { id: 'lyon', name: 'Lyon', code: 'LY', ou: 'OU=Lyon,OU=Postes,DC=example,DC=local' },
  ];
  let settings = { domain: 'example.local', dc: 'dc01.example.local', prefix: '111301', production: false,
    namingPattern: '{type}{prefix}{site}{service}{number:3}', randomNames: false, sites, simulation: true, liveExecutionEnabled: false };
  const services = [{ code: 'INF', name: 'Informatique' }, { code: 'ADM', name: 'Administration' }, { code: 'LOG', name: 'Logistique' }];
  const computers = [
    ['P111301PAINF001', 'paris', 'INF', 'Windows 11', 'Portable'],
    ['S111301PAADM001', 'paris', 'ADM', 'Windows 11', 'Fixe'],
    ['V111301LYINF001', 'lyon', 'INF', 'Windows 11', 'Virtuel'],
    ['P111301LYLOG001', 'lyon', 'LOG', 'Windows 10', 'Portable'],
  ].map(([name, site, service, os, model], index) => ({ name, dnsName: `${name.toLowerCase()}.example.local`, site,
    service, ou: sites.find((s) => s.id === site).ou, os, guid: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
    status: 'known', domain: 'example.local', manufacturer: 'Démonstration', model, serial: `DEMO-${index + 1}`, ip: null, pendingRestart: false }));
  const local = { name: 'NOUVEAU-PC', guid: '00000000-0000-4000-8000-000000000099', domain: null, pendingRestart: false };
  const previews = new Map(), plans = new Map(), batches = new Map(), alternatives = new Map();
  const receipts = [], logs = [], queue = [];
  const seed = clone({ settings, computers, local });
  const log = (message, level = 'info') => logs.unshift({ id: id('log'), time: iso(), level, message });
  const siteOf = (value) => settings.sites.find((s) => [s.id, s.name, s.code, s.ou].includes(value))
    || problem('site.invalid', 'Choisissez un site configuré.');
  const computerOf = (name) => computers.find((c) => c.name.toUpperCase() === String(name).toUpperCase())
    || problem('computer.missing', 'Ce poste n’existe pas dans l’annuaire de simulation.');
  const requireFresh = (value, label) => {
    if (!value || value.revision !== revision || Date.parse(value.expiresAt) <= now()) problem('plan.stale', `${label} a expiré ou les paramètres ont changé. Préparez un nouvel aperçu.`);
    return value;
  };
  const collision = (name, computer) => computers.some((c) => c.name.toUpperCase() === name.toUpperCase() && c.name.toUpperCase() !== String(computer).toUpperCase());
  const status = () => ({ mode: 'simulation', instanceId, generation, scenario, localComputer: local.name,
    pendingRestart: computers.filter((c) => c.pendingRestart).length,
    page: scenarios.find((s) => s.id === scenario).page, scenarios,
    message: 'Fenêtre de démonstration isolée. Aucun accès AD, SMB ou HTTP ; aucun changement réel.',
    remainingMoves: receipts.filter((r) => String(r.code) === '89' && !r.resolutionChildReceiptId)
      .map((r) => ({ id: r.id, newName: r.newName, targetOU: r.targetOU, restartRequired: r.restartRequired })) });
  const only = (args, keys) => {
    if (!args || typeof args !== 'object' || Array.isArray(args) || Object.keys(args).some((key) => !keys.includes(key)))
      problem('invalid_arguments', 'La demande de démonstration contient un champ inconnu.');
  };
  const confirm = (args, keys = ['confirmed']) => {
    only(args, keys);
    if (args.confirmed !== true) problem('confirmation.invalid', 'Confirmez explicitement cette action de démonstration.');
  };
  function reset(selected) {
    // Preserve the serial across resets. An ID from a previous world cannot become valid again.
    revision++; generation++; queueVersion++;
    previews.clear(); plans.clear(); batches.clear(); alternatives.clear(); queue.length = 0; receipts.length = 0; logs.length = 0;
    settings = clone(seed.settings); computers.splice(0, computers.length, ...clone(seed.computers));
    for (const key of Object.keys(local)) delete local[key];
    Object.assign(local, clone(seed.local));
    scenario = selected; nextOutcome = ['denied', 'uncertain', 'nameCollision'].includes(selected) ? selected : null;
    if (['joined', 'pendingRestart', 'partialMove', 'denied', 'uncertain'].includes(selected)) Object.assign(local, computers[0]);
    if (['pendingRestart', 'partialMove'].includes(selected)) {
      const computer = computers[0], oldName = computer.name, partial = selected === 'partialMove';
      computer.name = partial ? 'P111301LYINF002' : 'P111301PAINF002';
      computer.dnsName = `${computer.name.toLowerCase()}.${settings.domain}`;
      computer.pendingRestart = true; Object.assign(local, computer);
      receipts.push({ id: id('receipt'), time: iso(), kind: partial ? 'renameMove' : 'rename', computer: oldName,
        newName: computer.name, targetOU: partial ? settings.sites[1].ou : computer.ou, mode: 'simulation', status: 'pendingRestart',
        code: partial ? '89' : '20', restartRequired: true,
        message: partial ? 'Scénario fictif : renommage accepté, déplacement non tenté. L’OU initiale est conservée.'
          : 'Scénario fictif : renommage accepté. Un redémarrage fictif reste à demander.' });
    }
    log(`Démonstration remise à zéro : ${scenarios.find((s) => s.id === selected).label}. Aucun effet réel.`);
    return status();
  }
  function restart(args) {
    confirm(args);
    const changed = new Set(computers.filter((c) => c.pendingRestart).map((c) => c.name));
    computers.forEach((c) => { c.pendingRestart = false; }); local.pendingRestart = false;
    for (const receipt of receipts) {
      if (!receipt.restartRequired || !changed.has(receipt.newName) || receipt.status === 'uncertain') continue;
      receipt.restartRequired = false;
      if (String(receipt.code) !== '89') receipt.status = 'simulated';
      receipt.message = String(receipt.code) === '89'
        ? 'Redémarrage fictif effectué ; le déplacement reste à préparer et confirmer. Le résultat partiel est conservé.'
        : 'Redémarrage fictif effectué en mémoire. Aucun ordinateur réel n’a été redémarré.';
    }
    revision++; previews.clear(); plans.clear(); batches.clear(); queue.length = 0; queueVersion++;
    log(`Redémarrage fictif de ${changed.size} poste(s) en mémoire. Les reçus incertains restent incertains.`);
    return status();
  }
  function pattern(value, parts) {
    const matches = [...String(value).matchAll(/\{([^}]+)\}/g)].map((m) => m[1]);
    if (['type', 'prefix', 'site', 'service'].some((key) => matches.filter((m) => m === key).length !== 1)
      || matches.filter((key) => /^number:[1-5]$/.test(key)).length !== 1 || matches.length !== 5
      || !/^-*$/.test(String(value).replace(/\{[^}]+\}/g, ''))) problem('naming.pattern', 'La convention doit contenir une fois type, prefix, site, service et number:1 à number:5. Seuls les tirets séparent les parties.');
    const result = value.replace(/\{(type|prefix|site|service)\}/g, (_, key) => parts[key])
      .replace(/\{number:([1-5])\}/, (_, digits) => String(parts.number).padStart(Number(digits), '0'));
    if (!/^(?=.{1,15}$)[A-Z0-9][A-Z0-9-]*[A-Z0-9]$/.test(result)) problem('naming.length', 'La convention doit produire un nom Windows valide de 15 caractères au plus.');
    return result;
  }
  function parsedSite(name) {
    const escape = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    let expression = '', offset = 0;
    for (const token of settings.namingPattern.matchAll(/\{([^}]+)\}/g)) {
      expression += escape(settings.namingPattern.slice(offset, token.index));
      expression += token[1] === 'type' ? '[PSV]' : token[1] === 'prefix' ? escape(settings.prefix)
        : token[1] === 'site' ? '([A-Z0-9]{2})' : token[1] === 'service' ? '[A-Z0-9]{3}'
          : `[0-9]{${Number(token[1].split(':')[1]) || 3}}`;
      offset = token.index + token[0].length;
    }
    expression += escape(settings.namingPattern.slice(offset));
    return new RegExp(`^${expression}$`, 'i').exec(name)?.[1]?.toUpperCase() ?? null;
  }
  function preview(args) {
    const site = siteOf(args.site);
    if (!['P', 'S', 'V'].includes(args.type)) problem('type.invalid', 'Choisissez Portable, Fixe ou Virtuel.');
    if (!services.some((s) => s.code === args.service)) problem('service.invalid', 'Choisissez un service configuré.');
    const digits = Number(/\{number:([1-5])\}/.exec(settings.namingPattern)?.[1] || 3);
    const key = [args.type, site.id, args.service].join('|');
    const last = args.alternative ? alternatives.get(key) : null;
    const available = [];
    for (let number = 1; number < 10 ** digits; number++) {
      const name = pattern(settings.namingPattern, { type: args.type, prefix: settings.prefix, site: site.code, service: args.service, number });
      if (!collision(name) && !queue.some((q) => q.newName === name)) available.push(name);
    }
    if (!available.length) problem('names.exhausted', 'Aucun nom libre pour cette convention.');
    let name = available[0];
    if (settings.randomNames) name = available[Math.floor(Math.random() * available.length)];
    // Deterministic mode walks forward from the last proposal (wrapping), so each « Autre nom » gives a new name.
    // Comparing by order still works when the last proposal was taken meanwhile.
    if (last && !settings.randomNames && available.length > 1) { const next = available.findIndex((n) => n > last); name = available[next === -1 ? 0 : next]; }
    else if (last === name && available.length > 1) name = available[(available.indexOf(last) + 1) % available.length];
    alternatives.set(key, name);
    // A same-site rename keeps the existing OU, including a more specific child OU.
    const current = args.computer ? computerOf(args.computer) : null;
    const ou = current && parsedSite(current.name) === site.code.toUpperCase() ? current.ou : site.ou;
    const value = { previewId: id('preview'), name, ou, complete: true, collectedAt: iso(), expiresAt: expiry(), availableCount: available.length, source: 'simulation' };
    previews.set(value.previewId, { ...value, revision, site: site.id, service: args.service, computer: args.computer || null });
    log(`Aperçu simulé calculé : ${name}.`);
    return value;
  }
  function prepare(args) {
    args = { ...args };
    if (receipts.some((r) => r.status === 'uncertain')) problem('demo.uncertain', 'Un résultat fictif est incertain. Remettez la démonstration à zéro pour changer de scénario.');
    if (!kinds.includes(args.kind)) problem('operation.kind', 'Action non prise en charge.');
    if (args.kind === 'join' && local.domain) problem('join.alreadyJoined', 'Le poste local simulé a déjà rejoint le domaine.');
    if (args.kind === 'join' && args.computer && args.computer !== local.name) problem('join.localOnly', 'La jonction concerne uniquement ce poste.');
    if (args.kind !== 'join' && !args.computer) problem('invalid_arguments', 'Le nom du poste est requis pour cette action.');
    if (args.kind === 'move' && !args.targetOU) problem('invalid_arguments', 'L’OU de destination est requise pour un déplacement.');
    const computer = args.kind === 'join' ? local : computerOf(args.computer);
    const read = args.kind === 'move' ? null : requireFresh(previews.get(args.previewId), 'L’aperçu du nom');
    if (read && args.newName && args.newName !== read.name) problem('preview.changed', 'Le nom demandé ne correspond plus à l’aperçu.');
    if (read && args.kind !== 'join' && read.computer !== computer.name) problem('preview.identity', 'Cet aperçu appartient à un autre poste.');
    if (args.kind === 'renameMove' && read && (parsedSite(computer.name) === siteOf(read.site).code.toUpperCase() || computer.ou === read.ou)) {
      if (args.targetOU && args.targetOU !== computer.ou) problem('rename.no_move', 'Le site ne change pas : seul le renommage est admis, avec conservation de l’OU actuelle.');
      args.kind = 'rename';
    }
    if (args.kind === 'rename' && args.targetOU && args.targetOU !== computer.ou) problem('rename.no_move', 'Un renommage seul conserve l’OU actuelle.');
    const newName = read?.name || computer.name;
    if (nextOutcome === 'nameCollision' && read) {
      nextOutcome = null;
      computers.push({ name: newName, guid: globalThis.crypto.randomUUID(), site: read.site, service: read.service,
        ou: read.ou, domain: settings.domain, os: 'Windows 11', dnsName: `${newName.toLowerCase()}.${settings.domain}`, pendingRestart: false });
      previews.delete(read.previewId);
      log('Collision fictive : le nom de l’aperçu a été pris. Nouvel aperçu et nouvelle confirmation requis.', 'warn');
      problem('name.taken', 'Scénario fictif : ce nom vient d’être pris. Calculez un nouvel aperçu, puis confirmez de nouveau.');
    }
    if (collision(newName, computer.name)) problem('name.taken', 'Le nom affiché vient d’être pris. Calculez et confirmez un nouvel aperçu.');
    const targetOU = args.kind === 'rename' ? computer.ou : read?.ou || siteOf(args.targetOU).ou;
    const result = { planId: id('plan'), kind: args.kind, computer: computer.name, newName, targetOU,
      mode: 'simulation', expiresAt: expiry(), confirmationName: newName || computer.name,
      steps: [{ label: 'Vérifier l’identité', detail: computer.name }, { label: args.kind === 'move' ? 'Déplacer le compte' : 'Appliquer le nom confirmé', detail: newName },
        ...(args.kind === 'renameMove' || args.kind === 'join' ? [{ label: 'Vérifier le placement', detail: targetOU }] : [])],
      warnings: ['Démonstration : cette action modifie seulement les données en mémoire. Aucun redémarrage réel.'] };
    plans.set(result.planId, { ...result, revision, guid: computer.guid, read, used: false });
    return result;
  }
  function execute(args) {
    const plan = requireFresh(plans.get(args.planId), 'Le plan');
    if (plan.used) problem('plan.consumed', 'Ce plan a déjà été envoyé. Consultez son reçu.');
    if (args.confirmationName !== plan.confirmationName) problem('confirmation.invalid', 'Le nom confirmé ne correspond pas au plan. Préparez de nouveau l’opération.');
    if (receipts.some((r) => r.status === 'uncertain')) problem('demo.uncertain', 'Le résultat fictif précédent reste incertain. Aucune nouvelle écriture avant remise à zéro.');
    // Consume before applying: even a refusal after admission cannot be replayed.
    plan.used = true;
    let computer = plan.kind === 'join' ? local : computerOf(plan.computer);
    if (computer.guid !== plan.guid || collision(plan.newName, plan.computer)) problem('identity.changed', 'La cible ou la disponibilité du nom a changé. Rien n’a été appliqué.');
    if (plan.kind === 'join' && local.domain) problem('join.alreadyJoined', 'Le poste est déjà dans le domaine simulé.');
    if (plan.parentReceiptId && !receipts.some((r) => r.id === plan.parentReceiptId && !r.resolutionChildReceiptId))
      problem('demo.receipt', 'Le déplacement restant a déjà été traité dans cette démonstration.');
    if (['denied', 'uncertain'].includes(nextOutcome)) {
      const uncertain = nextOutcome === 'uncertain'; nextOutcome = null;
      const receipt = { id: id('receipt'), time: iso(), kind: plan.kind, computer: plan.computer, newName: plan.newName,
        targetOU: plan.targetOU, mode: 'simulation', status: uncertain ? 'uncertain' : 'refused', code: uncertain ? '97' : '5', restartRequired: false,
        message: uncertain ? 'Scénario fictif : résultat inconnu. Aucun rejeu ; le lot s’arrête et le reçu conserve son incertitude.'
          : 'Scénario fictif : accès refusé. Aucun changement appliqué, aucun repli implicite.' };
      receipts.unshift(receipt); log(receipt.message, uncertain ? 'warn' : 'error'); return receipt;
    }
    if (plan.kind === 'join') {
      computer = { ...local, dnsName: '', site: plan.read.site, service: plan.read.service, ou: plan.targetOU, os: 'Windows 11', status: 'known' };
      computers.push(computer);
    }
    if (plan.kind !== 'move') computer.name = plan.newName;
    if (plan.kind !== 'rename') { computer.ou = plan.targetOU; computer.site = siteOf(plan.targetOU).id; }
    if (plan.read) computer.service = plan.read.service;
    computer.domain = settings.domain; computer.dnsName = `${computer.name.toLowerCase()}.${settings.domain}`;
    computer.pendingRestart = plan.kind !== 'move';
    if (computer.guid === local.guid) Object.assign(local, computer);
    const receipt = { id: id('receipt'), time: iso(), kind: plan.kind, computer: plan.computer, newName: computer.name,
      targetOU: computer.ou, mode: 'simulation', status: 'simulated', code: { join: '10', rename: '20', move: '30', renameMove: '77' }[plan.kind],
      parentReceiptId: plan.parentReceiptId || null,
      message: 'Action simulée appliquée en mémoire. Aucun ordinateur ni annuaire réel n’a été modifié.', restartRequired: computer.pendingRestart };
    receipts.unshift(receipt); log(`Simulation terminée : ${plan.kind}, ${plan.computer} → ${computer.name}.`);
    if (plan.parentReceiptId) receipts.find((r) => r.id === plan.parentReceiptId).resolutionChildReceiptId = receipt.id;
    return receipt;
  }
  function save(args) {
    if (args.simulation === false || args.liveExecutionEnabled === true) problem('simulation.only', 'Le navigateur reste en simulation. La connexion réelle appartient à l’application Windows.');
    const next = { ...settings, ...clone(args), simulation: true, liveExecutionEnabled: false };
    if (!/^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$/i.test(next.domain) || !/^[a-z0-9][a-z0-9.-]+$/i.test(next.dc)) problem('settings.domain', 'Domaine ou contrôleur invalide.');
    if (!/^[A-Z0-9]{1,8}$/i.test(next.prefix)) problem('settings.prefix', 'Le préfixe doit contenir de 1 à 8 caractères alphanumériques.');
    if (!Array.isArray(next.sites) || !next.sites.length) problem('settings.sites', 'Au moins un site est nécessaire.');
    for (const site of next.sites) pattern(next.namingPattern, { type: 'P', prefix: next.prefix, site: site.code, service: 'INF', number: 1 });
    settings = next; revision++; previews.clear(); plans.clear(); batches.clear(); queue.length = 0; queueVersion++;
    log('Paramètres simulés enregistrés ; aperçus, plans et file invalidés.'); return settings;
  }
  const queueList = () => ({ items: queue, count: queue.length });
  async function invoke(op, args = {}) {
    if (/^(updates|configuration|references|coordination|reservations|attributes|offlineJoin)\./.test(op) || op === 'host.reconnect'
      || ['join.precreated.preview', 'receipts.prepareAcknowledgement', 'receipts.acknowledge', 'receipts.prepareRestart', 'receipts.restart'].includes(op))
      problem('demo.isolated', 'La démonstration ne lit aucun fichier réel, partage, site HTTP ni configuration utilisateur.');
    if (scenario === 'directoryOffline' && (op.startsWith('directory.') || ['computer.inspect', 'names.preview', 'operation.prepare'].includes(op)))
      problem('directory.unavailable', 'Scénario fictif : annuaire indisponible. Aucune connexion réseau n’a été tentée.');
    let result;
    switch (op) {
      case 'demo.status': result = status(); break;
      case 'demo.reset': confirm(args); result = reset('standard'); break;
      case 'demo.scenario':
        confirm(args, ['id', 'confirmed']);
        if (!scenarios.some((s) => s.id === args.id)) problem('demo.scenario', 'Ce scénario de démonstration n’existe pas.');
        result = reset(args.id); break;
      case 'demo.restart': result = restart(args); break;
      case 'demo.prepareMove': {
        only(args, ['id']);
        const parent = receipts.find((r) => r.id === args.id && String(r.code) === '89' && r.mode === 'simulation' && !r.resolutionChildReceiptId)
          || problem('demo.receipt', 'Choisissez un déplacement restant de cette démonstration.');
        const computer = computerOf(parent.newName);
        if (computer.pendingRestart || parent.restartRequired) problem('demo.restartRequired', 'Effectuez d’abord le redémarrage fictif.');
        result = prepare({ kind: 'move', computer: parent.newName, targetOU: parent.targetOU });
        result.parentReceiptId = parent.id; plans.get(result.planId).parentReceiptId = parent.id; break;
      }
      case 'demo.open': problem('demo.alreadyOpen', 'Cette fenêtre est déjà une démonstration isolée.'); break;
      case 'session.info': result = { version: 'simulation navigateur', mode: 'simulation', domain: settings.domain, dc: settings.dc,
        account: 'SIMULATION\\operateur.demo', computer: local.name, localJoined: !!local.domain, readOnly: false, instanceId, generation, demoScenario: scenario,
        capabilities: [...kinds, 'queue'].map((key) => key === 'join' && local.domain
          ? { id: key, enabled: false, reason: 'Ce poste simulé a déjà rejoint le domaine.' }
          : { id: key, enabled: true, reason: 'Disponible dans la simulation en mémoire.' }) }; break;
      case 'dashboard.read': result = { computers: scenario === 'directoryOffline' ? null : computers.length, availableNames: null, pendingRestart: computers.filter((c) => c.pendingRestart).length,
        uncertain: receipts.filter((r) => r.status === 'uncertain').length, lastActivity: receipts.slice(0, 5),
        sites: settings.sites.map((site) => ({ name: site.name, count: scenario === 'directoryOffline' ? null : computers.filter((c) => c.site === site.id).length })) }; break;
      case 'directory.sites': result = { items: settings.sites }; break;
      case 'directory.services': siteOf(args.site); result = { items: services }; break;
      case 'directory.search': {
        const query = String(args.query || '').toLowerCase();
        if (!query.trim()) problem('query.empty', 'Saisissez un nom ou un fragment de nom.');
        const matches = computers.filter((c) => [c.name, c.site, c.service, c.os].some((v) => v.toLowerCase().includes(query)));
        const limit = Math.min(100, Math.max(1, Number(args.limit) || 50));
        result = { items: matches.slice(0, limit), complete: matches.length <= limit, collectedAt: iso() }; break;
      }
      case 'computer.inspect': result = { ...computerOf(args.computer), inManagedScope: true, checks: [{ label: 'Identité', state: 'ok', detail: 'Poste de démonstration identifié en mémoire.' }, { label: 'Canal sécurisé', state: 'unknown', detail: 'Non mesuré : aucun réseau en simulation.' }] }; break;
      case 'names.preview': result = preview(args); break;
      case 'operation.prepare': result = prepare(args); break;
      case 'operation.execute': result = execute(args); break;
      case 'queue.list': result = queueList(); break;
      case 'queue.add': {
        if (args.kind === 'join') problem('queue.local', 'La jonction locale ne peut pas être placée en file.');
        if (queue.length >= 50) problem('queue.limit', 'La file est limitée à 50 postes.');
        const prepared = prepare(args);
        if (queue.some((q) => q.computer === prepared.computer || q.newName === prepared.newName)) problem('queue.duplicate', 'Ce poste ou ce nom est déjà dans la file.');
        queue.push({ id: id('queue'), kind: prepared.kind, computer: prepared.computer, newName: prepared.newName, targetOU: prepared.targetOU, status: 'ready', previewId: args.previewId });
        queueVersion++; batches.clear(); result = queueList(); break;
      }
      case 'queue.remove': { const index = queue.findIndex((q) => q.id === args.id); if (index < 0) problem('queue.missing', 'Cette ligne ne figure plus dans la file.'); queue.splice(index, 1); queueVersion++; batches.clear(); result = queueList(); break; }
      case 'queue.prepare': {
        only(args, ['pilot']);
        if ('pilot' in args && typeof args.pilot !== 'boolean') problem('invalid_arguments', 'Booléen pilot attendu.');
        if (!queue.length) problem('queue.empty', 'Ajoutez au moins un poste à la file.');
        const pilot = args.pilot === true;
        const items = (pilot ? queue.slice(0, 1) : queue).map((item) => prepare(item));
        result = { batchId: id('batch'), pilot, remainingCount: queue.length - items.length, items, expiresAt: expiry(), warnings: [pilot
          ? 'Mode pilote fictif : une seule ligne préparée ; les suivantes restent en file pour une nouvelle confirmation.'
          : 'Chaque action sera simulée une seule fois, dans l’ordre affiché.'] };
        batches.set(result.batchId, { ...result, revision, queueVersion, used: false }); break;
      }
      case 'queue.execute': {
        only(args, ['batchId', 'confirmed', 'entraLeaveConfirmed']);
        const batch = requireFresh(batches.get(args.batchId), 'Le lot');
        if (args.confirmed !== true) problem('confirmation.invalid', 'Le lot doit être confirmé explicitement.');
        if (batch.used || batch.queueVersion !== queueVersion) problem('batch.stale', 'Le lot a changé ou a déjà été envoyé.');
        batch.used = true; const applied = []; let reason = '';
        for (const plan of batch.items) {
          try {
            const receipt = execute({ planId: plan.planId, confirmationName: plan.confirmationName });
            applied.push(receipt); queue.shift();
            if (receipt.status !== 'simulated') { reason = 'Le lot fictif s’arrête sur le premier refus ou résultat incertain. Les lignes suivantes ne sont pas tentées.'; break; }
          }
          catch (error) { reason = error.message; break; }
        }
        const pilotCompleted = batch.pilot && applied.length === 1 && !reason;
        if (pilotCompleted && queue.length) reason = 'Pilote fictif terminé : une seule ligne simulée. Préparez et confirmez un nouveau lot pour les lignes restantes.';
        queueVersion++; result = { receipts: applied, pilot: batch.pilot, pilotCompleted, remainingCount: queue.length, stopped: !!reason, reason }; break;
      }
      case 'receipts.list': {
        // The filter also matches the French labels shown on the cards (status, operation), accents optional.
        const query = fold(args.query);
        result = { items: receipts.filter((r) => fold(`${r.computer} ${r.newName} ${r.status} ${STATUS_TEXT[r.status] ?? ''} ${r.kind} ${KIND_TEXT[r.kind] ?? ''} ${r.id}`).includes(query)) }; break;
      }
      case 'receipts.get': result = receipts.find((r) => r.id === args.id) || problem('receipt.missing', 'Ce reçu n’existe pas dans cette session.'); break;
      case 'receipts.reconcile': problem('receipt.reconcileSimulation', 'La simulation ne peut pas vérifier l’état réel d’un poste.'); break;
      case 'receipts.prepareMove': problem('receipt.prepareMoveSimulation', 'La simulation ne peut pas préparer la suite d’une opération réelle.'); break;
      case 'logs.list': result = { items: logs.filter((l) => (!args.level || l.level === args.level) && l.message.toLowerCase().includes(String(args.query || '').toLowerCase())) }; break;
      case 'settings.get': result = settings; break;
      case 'settings.save': result = save(args); break;
      case 'diagnostics.read': result = { mode: 'simulation', checks: [{ label: 'Interface', state: 'ok', detail: 'Modules locaux chargés.' }, { label: 'Moteur', state: 'ok', detail: 'Simulation en mémoire, isolée des données réelles.' }, { label: 'Active Directory', state: 'unknown', detail: 'Aucun contact réseau depuis le navigateur.' }] }; break;
      default: problem('operation.unknown', 'Cette opération n’est pas déclarée dans le pont Pesto.');
    }
    return clone(result);
  }
  return { invoke };
}
export const browserSimulation = createSimulation();
