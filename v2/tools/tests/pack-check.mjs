// Portable package mechanics (LIGHT only): a real single-file publication, no WebView2 fixture.
// This does not execute Windows binaries or qualify WebView2/AD.
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {appendFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const v2 = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const publish = resolve(process.argv[2] ?? join(v2, 'src/Pesto.App/bin/Release/net10.0-windows/win-x64/publish'));
const tool = join(v2, 'tools/pack/make-pack.mjs');
const spec = JSON.parse(readFileSync(join(v2, 'tools/pack/pack-manifest.json'), 'utf8'));
const ad = spec.activeDirectoryBundle;
const temp = mkdtempSync(join(tmpdir(), 'pesto-v2-pack-check-'));
const fixtureCommit = 'f'.repeat(40); // Explicit provenance fixture, never a published candidate.
let checks = 0, failures = 0;
function check(value, message, detail = '') {checks++; if (!value) {failures++; console.error('FAIL ' + message + ' ' + detail);} else console.log('OK   ' + message);}
const run = args => {
  const result = spawnSync(process.execPath, [tool, ...args], {encoding: 'utf8'});
  // A refused/killed child process must never count as a successful rejection by the pack validator.
  if (result.error) throw result.error;
  if (result.signal || result.status === null) throw new Error('Vérificateur interrompu : ' + (result.signal || 'sortie absente'));
  return result;
};
const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const info = root => JSON.parse(readFileSync(join(root, 'wad/Pesto.package.json'), 'utf8'));
function files(root, prefix = '') {return readdirSync(root, {withFileTypes: true}).flatMap(e => e.isDirectory() ? files(join(root, e.name), prefix + e.name + '/') : [prefix + e.name]).sort();}
function sums(root) {writeFileSync(join(root, 'wad/SHA256SUMS'), files(root).filter(p => p !== 'wad/SHA256SUMS').map(p => hash(join(root,p)) + '  ' + p).join('\n') + '\n');}
try {
  if (!existsSync(join(publish, 'Pesto.exe')) || existsSync(join(publish, 'Pesto.dll'))) throw new Error('Publier d’abord Pesto.App en single-file self-contained ; passer le dossier publish en premier argument.');
  let result;
  const prod = join(temp,'PROD'), dev = join(temp,'DEV');
  for (const [root, channel] of [[prod,'PROD'],[dev,'DEV']]) {
    result = run(['--source', publish, '--dest', root, '--channel', channel, '--source-commit', fixtureCommit]);
    check(result.status === 0, channel + ' assemblé (LIGHT, aucun runtime)', result.stderr);
    if (!existsSync(root)) throw new Error('Pack absent : ' + result.stderr);
    check(run(['--verify',root]).status === 0, 'vérification ' + channel);
    check(info(root).webview2Runtime === 'evergreen' && !('webview2Version' in info(root)), channel + ' manifeste LIGHT evergreen sans version');
    check(!existsSync(join(root, 'wad/runtime/webview2')), channel + ' aucun dossier WebView2');
    check(JSON.stringify(readdirSync(root).sort()) === JSON.stringify(['Pesto.exe', 'wad']), channel + ' racine seulement Pesto.exe et wad');
    check(files(root).every(p => !/\.pdb$|(^|\/)cfg\.json$/.test(p)), channel + ' aucun symbole ni cfg utilisateur');
    check(existsSync(join(root, 'wad/support/DEBLOQUER_TOUT.cmd')), channel + ' déblocage livré dans wad/support');
    check(/\.\.\\\.\./.test(readFileSync(join(root, 'wad/support/DEBLOQUER_TOUT.cmd'), 'utf8')), channel + ' déblocage remonte à la racine application');
    check(existsSync(join(root, 'wad/docs/CONFIGURATION.md')) && existsSync(join(root, 'wad/docs/PARITY.md')), channel + ' documentation configuration et parité livrée');
    check(!existsSync(join(root, 'wad/docs/evidence')), channel + ' archives historiques absentes des documents');
    check(!files(join(root, 'wad/docs')).some(path => ['.json', '.log'].includes(path.slice(path.lastIndexOf('.')))),
      channel + ' les liens réparés n’ajoutent ni JSON ni journaux aux documents');
    check(info(root).distribution === 'candidate' && info(root).qualification === 'unqualified', channel + ' statut candidat honnête');
    check(files(join(root, ad.directory)).length === 6 && Object.entries(ad.sha256).every(([name, expected]) => hash(join(root, ad.directory, name)) === expected), channel + ' six fichiers Microsoft AD prêts et épinglés');
  }
  const brokenLinks = files(join(prod, 'wad/docs')).filter(p => p.endsWith('.md')).flatMap(path => {
    const file = join(prod, 'wad/docs', path);
    return [...readFileSync(file, 'utf8').matchAll(/\]\(([^)]+)\)/g)].map(m => m[1].split('#')[0])
      .filter(target => target && !/^[a-z][a-z0-9+.-]*:/i.test(target) && !existsSync(resolve(dirname(file), target)));
  });
  check(brokenLinks.length === 0, 'liens des documents pack résolus', brokenLinks.join(', '));
  const index = readFileSync(join(prod, 'wad/docs/EVIDENCE.md'), 'utf8');
  check(index.includes('https://github.com/M4D135/pesto/blob/' + fixtureCommit + '/v2/docs/evidence/')
    && !/\]\(evidence\/[^)]+\.json\)/.test(index), 'preuves non livrées liées au commit de fixture, sans faux fichier local');
  check(index.includes('https://github.com/M4D135/pesto/blob/' + fixtureCommit + '/v2/docs/evidence/20261028/windows-2adf60e/README.md'),
    'rapport historique Markdown lié au commit source depuis le guide livré');
  for (const channel of ['PROD', 'DEV']) {
    const official = join(temp, 'official-' + channel);
    try {
      result = run(['--source', publish, '--dest', official, '--channel', channel,
        '--source-commit', fixtureCommit, '--distribution', 'official']);
      check(result.status === 0 && info(official).distribution === 'official' && info(official).official === true
        && info(official).qualification === 'unqualified' && info(official).sourceCommit === fixtureCommit,
        channel + ' officiel explicite garde qualification non réalisée et provenance exacte (fixture)', result.stderr);
      check(run(['--verify', official]).status === 0, channel + ' officiel vérifié sans qualifier Windows ni AD');
    } finally { rmSync(official, {recursive: true, force: true}); }
  }
  for (const opt of ['--webview2', '--webview2-version', '--allow-missing-webview2', '--evergreen']) {
    const dest = join(temp, 'forbidden-' + opt.replace(/[^a-z]/gi, ''));
    result = run(['--source', publish, '--dest', dest, '--channel', 'PROD', opt]);
    check(result.status === 2 && /LIGHT.*Socle/.test(result.stderr), 'option interdite refusée : ' + opt, result.stderr);
  }
  const officialRefused = join(temp, 'official-refused');
  for (const [label, extra] of [
    ['distribution arbitraire', ['--distribution', 'custom']],
    ['sans commit', ['--distribution', 'official']]
  ]) {
    result = run(['--source', publish, '--dest', officialRefused, '--channel', 'PROD', ...extra]);
    check(result.status === 2 && !existsSync(officialRefused), 'publication officielle refusée : ' + label, result.stderr);
  }
  const nativePins = Object.fromEntries([...readFileSync(join(v2, 'src/Pesto.Engine/ActiveDirectoryBundle.cs'), 'utf8')
    .matchAll(/\["([^"]+)"\] = "([a-f0-9]{64})"/g)].map(match => [match[1], match[2]]));
  check(Object.keys(nativePins).length === 6 && JSON.stringify(nativePins) === JSON.stringify(ad.sha256), 'pins Microsoft identiques dans le moteur et la spécification du pack');
  check(existsSync(join(dev,'wad/dev/src/Pesto.App/Pesto.App.csproj')), 'DEV sources incluses');
  const brandPaths = ['src/Pesto.App/Assets/Pesto.ico', 'src/Pesto.App/Assets/pesto-master.png',
    'web/assets/pesto.png', 'web/assets/pesto-favicon.png'];
  check(brandPaths.every(path => existsSync(join(dev, 'wad/dev', path))
    && hash(join(dev, 'wad/dev', path)) === hash(join(v2, path))), 'DEV conserve les quatre sources exactes de marque pour la refabrication');
  check(['tools/check-ui-kit.py', 'tools/m4d-components/components.py'].every(path => existsSync(join(dev, 'wad/dev', path))
    && hash(join(dev, 'wad/dev', path)) === hash(join(v2, path))), 'DEV conserve les deux seuls vérificateurs Python vendored autorisés');
  for (const path of ['src/Pesto.App/Assets/extra.png', 'src/Pesto.App/Assets/extra.ico', 'web/assets/extra.png', 'web/other/pesto-favicon.png',
    'tools/extra.py', 'tools/m4d-components/extra.py']) {
    const extra = join(dev, 'wad/dev', path); mkdirSync(dirname(extra), {recursive: true}); writeFileSync(extra, 'explicit unexpected image fixture'); sums(dev);
    const rejected = run(['--verify', dev]);
    check(rejected.status === 2 && /hors manifeste/.test(rejected.stderr), 'DEV refuse une image ou un script hors des chemins exacts : ' + path, rejected.stderr);
    unlinkSync(extra); sums(dev);
  }
  check(existsSync(join(dev,'wad/dev/vendor/nuget/SHA256SUMS')), 'DEV dépendances vendored incluses');
  const socleIndex = 'vendor/socle/webview2-156.0.4314.42.files.json';
  check(hash(join(dev, 'wad/dev', socleIndex)) === hash(join(v2, socleIndex)) && !existsSync(join(prod, 'wad/dev')),
    'DEV livre l’index exact du Socle pour la refabrication, jamais le runtime');
  check(hash(join(dev, 'wad/dev/README.md')) === hash(join(v2, 'README.md'))
    && hash(join(dev, 'wad/dev/docs/PACKAGING.md')) === hash(join(v2, 'docs/PACKAGING.md')),
    'DEV contient les sources exactes des guides requis pour refabriquer un pack');
  check(!existsSync(join(dev, 'wad/dev/docs/evidence')), 'DEV sans archives historiques dans les sources livrées');
  const guides = files(join(v2, 'docs')).filter(path => !path.startsWith('evidence/') && path.endsWith('.md'));
  check(guides.length > 0 && guides.every(path => existsSync(join(dev, 'wad/dev/docs', path))
    && hash(join(dev, 'wad/dev/docs', path)) === hash(join(v2, 'docs', path))),
    'tous les guides Markdown hors archives sont conservés octet par octet dans les sources DEV');
  check(!existsSync(join(prod,'wad/dev')), 'PROD sans outillage développement');
  check(files(prod).filter(p=>p.startsWith('wad/web/')).length === files(join(v2,'web')).length, 'interface source complète');
  const duplicate = join(temp,'duplicate');
  result = run(['--source',publish,'--dest',duplicate,'--channel','PROD','--source-commit', fixtureCommit]);
  check(result.status === 0 && hash(join(prod,'wad/SHA256SUMS')) === hash(join(duplicate,'wad/SHA256SUMS')), 'assemblage déterministe');
  const rebuilt = join(temp, 'rebuilt-from-DEV');
  result = spawnSync(process.execPath, [join(dev, 'wad/dev/tools/pack/make-pack.mjs'), '--source', publish,
    '--dest', rebuilt, '--channel', 'PROD',
    '--source-commit', fixtureCommit], {encoding: 'utf8', cwd: join(dev, 'wad/dev')});
  check(result.status === 0 && existsSync(join(rebuilt, 'wad/SHA256SUMS'))
    && hash(join(prod, 'wad/SHA256SUMS')) === hash(join(rebuilt, 'wad/SHA256SUMS')),
    'les seules sources livrées dans DEV refabriquent le même PROD, sans accès au dépôt initial', result.stderr);
  function tamper(label, change, rehash = false, expectedError = null) {
    const copy = join(temp,'tamper-' + checks);
    try {
      cpSync(prod, copy, {recursive:true}); change(copy); if (rehash) sums(copy);
      result = run(['--verify',copy]); check(result.status === 2 && (!expectedError || expectedError.test(result.stderr)),label,result.stderr);
    } finally { rmSync(copy, {recursive: true, force: true}); }
  }
  tamper('exécutable modifié refusé',r=>appendFileSync(join(r,'Pesto.exe'),'x'));
  tamper('runtime WebView2 ajouté refusé',r=>{mkdirSync(join(r,'wad/runtime/webview2'),{recursive:true});writeFileSync(join(r,'wad/runtime/webview2/msedgewebview2.exe'),'fake');},true);
  tamper('module AD altéré refusé même après rehash',r=>appendFileSync(join(r,ad.directory,'Microsoft.ActiveDirectory.Management.dll'),'x'),true);
  tamper('ressource AD supprimée refusée même après rehash',r=>unlinkSync(join(r,ad.directory,'fr-FR/ActiveDirectoryPowerShellResources.dll.mui')),true);
  tamper('script inconnu du dossier AD refusé',r=>writeFileSync(join(r,ad.directory,'extra.psm1'),'# unexpected'),true);
  tamper('DLL inconnue du dossier AD refusée',r=>writeFileSync(join(r,ad.directory,'extra.dll'),'unexpected'),true);
  tamper('fichier racine inconnu refusé',r=>writeFileSync(join(r,'private.json'),'{}'),true);
  tamper('cfg privé refusé même après rehash',r=>writeFileSync(join(r,'wad/web/cfg.json'),'{}'),true);
  tamper('fichier DEV en PROD refusé',r=>{mkdirSync(join(r,'wad/dev'));writeFileSync(join(r,'wad/dev/test.cs'),'x');},true);
  tamper('PE invalide refusé même après rehash',r=>writeFileSync(join(r,'Pesto.exe'),'not pe'),true);
  tamper('canal incohérent refusé',r=>{const p=info(r);p.channel='OTHER';writeFileSync(join(r,'wad/Pesto.package.json'),JSON.stringify(p));},true);
  tamper('injection de provenance officielle incohérente refusée',r=>{const p=info(r);p.official=true;writeFileSync(join(r,'wad/Pesto.package.json'),JSON.stringify(p));},true);
  tamper('lien ou jonction refusé avant inventaire', r => symlinkSync(join(r, 'wad'), join(r, 'linked-wad'),
    process.platform === 'win32' ? 'junction' : 'dir'), false, /Lien ou jonction interdit/);
  tamper('sommes amputées refusées',r=>writeFileSync(join(r,'wad/SHA256SUMS'),readFileSync(join(r,'wad/SHA256SUMS'),'utf8').split('\n').slice(1).join('\n')));
  check(run(['--source',publish,'--dest',prod,'--channel','PROD']).status===2,'pack existant jamais écrasé');
  check(run(['--source',publish,'--dest',join(publish,'not-allowed'),'--channel','PROD']).status===2,'destination publication refusée');
  const app = readFileSync(join(v2,'src/Pesto.App/AppPaths.cs'),'utf8');
  check(app.includes('"wad"') && app.includes('"web"') && app.includes('"runtime"') && app.includes('"webview2"'),'chemins hôte alignés wad');
  check(readFileSync(join(v2,'src/Pesto.App/Pesto.App.csproj'),'utf8').includes('<PublishSingleFile>true</PublishSingleFile>'),'publication single-file déclarée');
} catch (error) {failures++; console.error('FAIL ' + error.message);} finally {rmSync(temp,{recursive:true,force:true});}
console.log(`PACK CHECK ${failures ? 'ÉCHEC' : 'OK'} : ${checks - failures}/${checks} contrôles ; aucune exécution Windows.`);
process.exitCode = failures ? 1 : 0;
