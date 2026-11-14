// Paramètres : registre pur des sections, des anciens noms d’adresse et de l’index de la recherche de réglage.
// Aucun DOM, aucun réseau, aucun pont : importable sous Node par tools/tests/web-check.mjs. La coque (shell.js) et la
// page (../parametres.js) lisent ces tables ; le contrat est celui de docs/PARAMETRES.md (adresse #/parametres?section=…).

export const DEFAULT_SECTION = 'annuaire';

// Accent- and case-insensitive form (same rule as ui.js fold, kept here so that this module stays free of the DOM).
export const fold = (text) => String(text ?? '').normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();

// Order of the rail. live: true = shown only with the real directory (the simulation has no operation policies).
// form: true = the panel sits inside the single settings form (one draft for every section).
export const SECTIONS = Object.freeze([
  { id: 'annuaire', label: 'Annuaire', desc: 'Domaine, préfixe, convention et sites', icon: 'shield', tone: 'info', live: false, form: true,
    intro: 'Domaine, contrôleur, préfixe, convention de nommage et sites.' },
  { id: 'politiques', label: 'Politiques', desc: 'Coordination, jonction, CLI et audit', icon: 'lock', tone: 'warn', live: true, form: true,
    intro: 'Ces paramètres sont inclus dans les exports et dans la configuration par défaut de l’installation (wad\\defaults\\configuration.json). Leur enregistrement ne lance aucune opération AD.' },
  { id: 'configuration', label: 'Configuration', desc: 'Export, import, défaut et référentiels', icon: 'settings', tone: 'accent', live: false, form: false,
    intro: 'État de la configuration en vigueur, partage par export et import, configuration par défaut de l’installation et référentiels.' },
  { id: 'mises-a-jour', label: 'Mises à jour', desc: 'ZIP, dossier ou partage UNC', icon: 'refresh', tone: 'info', live: false, form: false,
    intro: 'Inspecter, préparer puis confirmer l’installation d’un pack vérifié.' },
  { id: 'interface', label: 'Interface', desc: 'Animations et démonstration', icon: 'sparkles', tone: 'accent', live: false, form: false,
    intro: 'Préférences d’affichage de ce poste et fenêtre de démonstration.' },
].map((section) => Object.freeze(section)));

// Older or familiar names of a section in an address (?section=…): each canonical id points to itself.
export const SECTION_ALIASES = Object.freeze({
  annuaire: 'annuaire', nommage: 'annuaire', domaine: 'annuaire', sites: 'annuaire',
  politiques: 'politiques', politique: 'politiques', coordination: 'politiques',
  configuration: 'configuration', import: 'configuration', export: 'configuration', defaut: 'configuration', referentiels: 'configuration',
  'mises-a-jour': 'mises-a-jour', 'mise-a-jour': 'mises-a-jour', maj: 'mises-a-jour', updates: 'mises-a-jour',
  interface: 'interface', apparence: 'interface', animations: 'interface', demonstration: 'interface', demo: 'interface',
});

// ouvrir=<nom> names a field ([name]) or a maintenance action ([data-maint]); anything else is ignored.
export const OPEN_RE = /^[A-Za-z][A-Za-z0-9-]{0,63}$/;

// Index of the search box: label, words, section and the target lit up (a selector of this page only).
const ENTRIES = [
  ['Domaine', 'domaine dns fqdn annuaire', 'annuaire', '[name="domain"]'],
  ['Contrôleur de domaine', 'controleur dc serveur decouvert', 'annuaire', '[name="dc"]'],
  ['Préfixe de nommage', 'prefixe nom poste', 'annuaire', '[name="prefix"]'],
  ['Convention de nommage', 'convention motif pattern type site service numero', 'annuaire', '[name="namingPattern"]'],
  ['OU racine du parc géré', 'ou racine perimetre organisation', 'annuaire', '[name="rootOu"]', true],
  ['OU de préproduction', 'ou preproduction preprod', 'annuaire', '[name="preprodOu"]', true],
  ['Code de service de préproduction', 'service preproduction code', 'annuaire', '[name="preprodSite"]', true],
  ['Environnement de production', 'production prod environnement', 'annuaire', '[name="production"]'],
  ['Tirer un nom au hasard parmi les libres', 'hasard aleatoire tirage noms libres', 'annuaire', '[name="randomNames"]'],
  ['Sites', 'sites ou code ligne', 'annuaire', '[name="sites"]'],
  ['Dossier de coordination partagé', 'coordination dossier partage unc registre', 'politiques', '[name="coordinationRoot"]', true],
  ['Exiger la coordination partagée', 'coordination exiger obligatoire', 'politiques', '[name="coordinationRequired"]', true],
  ['Réserver le nom dans AD lors de la jonction', 'reservation compte nom jonction', 'politiques', '[name="reserveNamesInAd"]', true],
  ['Autoriser un compte ordinateur précréé', 'precree compte ordinateur', 'politiques', '[name="allowPrecreatedJoin"]', true],
  ['Autoriser la jonction hors ligne locale', 'hors ligne odj blob djoin', 'politiques', '[name="allowOfflineJoin"]', true],
  ['Autoriser la jonction par CLI', 'cli ligne de commande sequence silencieuse', 'politiques', '[name="unattendedJoinEnabled"]', true],
  ['Autoriser renommage et déplacement par CLI', 'cli renommage deplacement', 'politiques', '[name="unattendedOperationsEnabled"]', true],
  ['Retrait Entra avant un renommage hybride', 'entra azure hybride retrait', 'politiques', '[name="entraPolicy"]', true],
  ['Exporter l’audit dans le journal Windows', 'audit journal evenements windows', 'politiques', '[name="auditEventLogEnabled"]', true],
  ['Contrôler l’écart d’horloge avant la jonction', 'horloge heure ecart kerberos', 'politiques', '[name="blockJoinOnClockSkew"]', true],
  ['Groupes AD exclus, identifiants GUID', 'groupes exclus guid', 'politiques', '[name="excludedGroupGuids"]', true],
  ['Tester le registre de coordination', 'registre coordination tester verrous', 'politiques', '[data-coordination-action="inspect"]', true],
  ['Préparer le dossier de coordination', 'registre coordination preparer', 'politiques', '[data-coordination-action="prepare"]', true],
  ['Configuration en vigueur', 'etat empreinte valide invalide', 'configuration', '[data-setting="config-summary"]'],
  ['Version de configuration', 'version export nom', 'configuration', '[name="configurationVersion"]'],
  ['Exporter la configuration', 'exporter export partager fichier', 'configuration', '[data-maint="export"]'],
  ['Importer une configuration', 'importer import comparer remplacer', 'configuration', '[data-maint="import"]'],
  ['Définir comme configuration par défaut', 'defaut installation defaults diffuser', 'configuration', '[data-maint="default"]'],
  ['Comparer la configuration distribuée', 'distribuee pack comparer differences', 'configuration', '[data-maint="distribution"]'],
  ['Reconnecter Pesto', 'reconnecter compte session', 'configuration', '[data-maint="reconnect"]'],
  ['Importer une mise à jour des référentiels', 'referentiels sites services conflits', 'configuration', '[data-maint="references"]'],
  ['Choisir un ZIP de mise à jour', 'zip archive mise a jour pack', 'mises-a-jour', '[data-maint="zip"]'],
  ['Choisir un dossier de mise à jour', 'dossier local pack mise a jour', 'mises-a-jour', '[data-maint="folder"]'],
  ['Dossier ou partage UNC', 'unc partage chemin serveur', 'mises-a-jour', '[name="updateSource"]'],
  ['Inspecter ce chemin', 'inspecter verifier source', 'mises-a-jour', '[data-maint="source"]'],
  ['État et reprise', 'etat reprise interrompue', 'mises-a-jour', '[data-maint="status"]'],
  ['Revenir à la version précédente', 'retour arriere rollback version precedente', 'mises-a-jour', '[data-maint="rollback"]'],
  ['Animations', 'animations mouvement reduire windows', 'interface', '[name="interfaceMotion"]'],
  ['Démonstration', 'demonstration simulation fictif scenarios', 'interface', '.demo-trigger'],
  ['Thème clair, sombre ou contraste élevé', 'theme couleurs sombre clair contraste', 'interface', '[data-setting="theme"]'],
];

export const INDEX = Object.freeze(ENTRIES.map(([label, words, section, target, live]) => Object.freeze({
  label, words: fold(`${label} ${words}`), section, target, ...(live ? { live: true } : {}),
})));

/** Sections of the rail for this mode, in order. */
export function sectionsFor({ live }) {
  return SECTIONS.filter((section) => live || !section.live);
}

/** Canonical id of a section name (alias accepted) when it is shown in this mode, otherwise null. */
export function sectionOf(value, { live }) {
  if (typeof value !== 'string') return null;
  const key = fold(value).trim();
  if (!Object.prototype.hasOwnProperty.call(SECTION_ALIASES, key)) return null;
  const id = SECTION_ALIASES[key];
  return sectionsFor({ live }).some((section) => section.id === id) ? id : null;
}

/** Section and open state read from the parameters of an address; unknown names fall back to the default section. */
export function addressOf(params, { live }) {
  const section = sectionOf(params?.section, { live }) ?? DEFAULT_SECTION;
  const ouvrir = typeof params?.ouvrir === 'string' && OPEN_RE.test(params.ouvrir) ? params.ouvrir : null;
  return { section, ouvrir };
}

/** Parameters written in the address for a section: the default section keeps the bare #/parametres. */
export function addressParams(id) {
  return id === DEFAULT_SECTION ? {} : { section: id };
}

/** Entries whose folded words contain every word of the query, at most max (entries: the index kept at mount). */
export function searchSettings(query, { live, max = 8, entries = INDEX }) {
  const q = fold(String(query ?? '').trim());
  if (!q) return [];
  const words = q.split(/\s+/).filter(Boolean);
  const shown = new Set(sectionsFor({ live }).map((section) => section.id));
  return entries.filter((entry) => (live || !entry.live) && shown.has(entry.section)
    && words.every((word) => entry.words.includes(word))).slice(0, max);
}
