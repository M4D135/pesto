// Pesto V2 single-file portable packages (LIGHT only). Assembly validates content; it is not a Windows/AD qualification.
// The fixed WebView2 runtime comes from the Socle (link), never from the pack.
import {createHash} from 'node:crypto';
import {cpSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, lstatSync, writeFileSync} from 'node:fs';
import {basename, dirname, extname, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const v2 = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const spec = JSON.parse(readFileSync(join(v2, 'tools/pack/pack-manifest.json'), 'utf8'));
const manifestPath = spec.appRequiredPaths.packageInfo;
const sumsPath = spec.appRequiredPaths.hashes;
const adBundle = spec.activeDirectoryBundle;
const adPaths = new Set(Object.keys(adBundle.sha256).map(name => adBundle.directory + '/' + name));
class PackError extends Error {}
const fail = text => {throw new PackError(text);};
const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');
function noLinks(path) {
  let current = resolve(path);
  while (true) {
    if (existsSync(current) && lstatSync(current).isSymbolicLink()) fail('Lien ou jonction interdit dans le chemin.');
    const parent = dirname(current); if (parent === current) break; current = parent;
  }
}
function safe(path) {
  if (!path || path.length > 1024 || path.startsWith('/') || /[\\<>:"|?*\x00-\x1f]/.test(path)) fail('Chemin du pack interdit.');
  for (const part of path.split('/')) if (!part || ['.', '..'].includes(part) || /[ .]$/.test(part)
    || /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i.test(part)) fail('Chemin réservé ou ambigu sous Windows.');
  return path;
}
function walk(root) {
  const files = [], keys = new Set(); let bytes = 0;
  noLinks(root);
  function visit(dir) {
    for (const entry of readdirSync(dir, {withFileTypes: true})) {
      const abs = join(dir, entry.name), stat = lstatSync(abs), rel = safe(relative(root, abs).split(sep).join('/'));
      if (stat.isSymbolicLink()) fail('Lien ou jonction interdit : ' + rel);
      if (stat.isDirectory()) visit(abs);
      else if (stat.isFile()) {
        if (keys.has(rel.toLowerCase())) fail('Chemin en double sous Windows : ' + rel);
        keys.add(rel.toLowerCase()); files.push(rel); bytes += stat.size;
        if (files.length > 20000 || bytes > 4 * 1024 ** 3) fail('Pack trop volumineux.');
      } else fail('Entrée spéciale interdite : ' + rel);
    }
  }
  visit(root); return files.sort();
}
const sourceExtensions = new Set(['.cs', '.csproj', '.props', '.targets', '.sln', '.slnx', '.json', '.mjs', '.js', '.css', '.html', '.md', '.txt', '.ps1', '.cmd', '.manifest', '.config']);
// Exact extra sources needed for branding and the vendored checks; no generic image/Python extension is admitted.
const socleIndexPath = 'vendor/socle/webview2-156.0.4314.42.files.json';
const exactDevSourcePaths = new Set([socleIndexPath, 'src/Pesto.App/Assets/Pesto.ico', 'src/Pesto.App/Assets/pesto-master.png',
  'web/assets/pesto.png', 'web/assets/pesto-favicon.png', 'tools/check-ui-kit.py', 'tools/m4d-components/components.py']);
function allowed(path, channel) {
  if (['Pesto.exe', manifestPath, sumsPath, 'wad/defaults/configuration.json', 'wad/support/DEBLOQUER_TOUT.cmd'].includes(path)) return true;
  if (['cfg.json', 'cfg.demo.json'].includes(basename(path).toLowerCase())) return false;
  if (['.pdb', '.log', '.sqlite', '.etl', '.evtx'].includes(extname(path).toLowerCase())) return false;
  if (adPaths.has(path)) return true;
  if (path.startsWith('wad/web/')) return new Set(['.html', '.js', '.css', '.json', '.svg', '.png', '.jpg', '.jpeg', '.ico', '.woff', '.woff2']).has(extname(path).toLowerCase());
  if (path.startsWith('wad/docs/')) return ['.md', '.txt', '.pdf'].includes(extname(path).toLowerCase());
  if (channel === 'DEV' && path.startsWith('wad/dev/vendor/nuget/')) return extname(path).toLowerCase() === '.nupkg' || basename(path) === 'SHA256SUMS';
  if (channel === 'DEV' && path.startsWith('wad/dev/') && exactDevSourcePaths.has(path.slice('wad/dev/'.length))) return true;
  return channel === 'DEV' && path.startsWith('wad/dev/') && sourceExtensions.has(extname(path).toLowerCase());
}
function pe64(path) {
  const b = readFileSync(path);
  if (b.length < 128 || b.readUInt16LE(0) !== 0x5a4d) fail('Exécutable PE absent ou invalide : ' + basename(path));
  const p = b.readInt32LE(0x3c);
  if (p < 0x40 || p + 26 > b.length || b.readUInt32LE(p) !== 0x4550 || b.readUInt16LE(p + 4) !== 0x8664 || b.readUInt16LE(p + 24) !== 0x20b)
    fail('Un PE32+ Windows x64 est requis : ' + basename(path));
}
function writeSums(root) {
  const files = walk(root).filter(p => p !== sumsPath);
  writeFileSync(join(root, sumsPath), files.map(p => `${hash(join(root, p))}  ${p}`).join('\n') + '\n');
}
function verify(root, compareWeb = false) {
  if (!existsSync(root)) fail('Dossier absent.');
  const files = walk(root);
  for (const path of files) {
    if (path.startsWith('wad/runtime/webview2/') || basename(path).toLowerCase() === 'msedgewebview2.exe')
      fail('Runtime WebView2 interdit dans le pack (LIGHT seul, le fixe vient du Socle) : ' + path);
  }
  for (const path of spec.requiredFiles) if (!files.includes(path)) fail('Fichier requis absent : ' + path);
  const info = JSON.parse(readFileSync(join(root, manifestPath), 'utf8'));
  const keys = ['schemaVersion', 'packName', 'version', 'channel', 'entryPoint', 'layout', 'repository', 'webview2Runtime', 'distribution', 'official', 'configurationVersion', 'configurationFingerprint', 'sourceCommit', 'qualification'];
  if (Object.keys(info).some(k => !keys.includes(k)) || info.schemaVersion !== 2 || info.packName !== spec.packName || info.layout !== spec.layout
    || info.entryPoint !== 'Pesto.exe' || info.repository !== 'M4D135/pesto' || !/^2\.\d+\.\d+(?:\.\d+)?$/.test(info.version)
    || !['DEV', 'PROD'].includes(info.channel) || !['candidate', 'official', 'custom'].includes(info.distribution)
    || info.official !== (info.distribution === 'official')) fail('Manifeste Pesto V2 incohérent.');
  if (info.webview2Runtime !== 'evergreen') fail('Le manifeste doit déclarer webview2Runtime: evergreen (LIGHT seul).');
  if ('webview2Version' in info) fail('webview2Version est interdit : le runtime fixe vient du Socle, jamais du pack.');
  for (const path of files) if (!allowed(path, info.channel)) fail('Fichier hors manifeste : ' + path);
  const defaults = 'wad/defaults/configuration.json';
  if (files.includes(defaults)) {
    const bundle = JSON.parse(readFileSync(join(root, defaults), 'utf8'));
    if (info.distribution !== 'custom' || bundle.kind !== 'pesto.configuration' || bundle.schema !== 1
      || !/^[a-f0-9]{64}$/.test(bundle.fingerprint) || bundle.fingerprint !== info.configurationFingerprint
      || bundle.version !== info.configurationVersion || Object.keys(bundle).some(k => !['kind', 'schema', 'version', 'fingerprint', 'configuration'].includes(k)))
      fail('Configuration distribuée incohérente. La validation métier complète est répétée par le moteur C# avant import.');
    const top = ['Configured', 'CONF', 'OUBase', 'OUSite', 'TAGS', 'NameCatalogue', 'NamingConvention', 'POLICY', 'V2DirectorySites', 'ReferenceData'];
    if (!bundle.configuration || Object.keys(bundle.configuration).some(k => !top.includes(k))) fail('Champ non diffusable dans la configuration.');
  } else if (info.configurationFingerprint || info.configurationVersion) fail('Configuration distribuée manquante.');
  if (!files.includes(sumsPath)) fail('SHA256SUMS absent.');
  const sums = new Map();
  for (const line of readFileSync(join(root, sumsPath), 'utf8').split('\n').filter(Boolean)) {
    const match = /^([a-f0-9]{64})  (.+)$/.exec(line);
    if (!match) fail('Ligne de somme invalide.');
    safe(match[2]); const key = match[2].toLowerCase();
    if (sums.has(key) || match[2] === sumsPath) fail('Somme répétée ou interdite.');
    sums.set(key, match[1]);
  }
  if (sums.size !== files.length - 1) fail('L’inventaire ne couvre pas exactement le pack.');
  for (const file of files.filter(p => p !== sumsPath)) if (sums.get(file.toLowerCase()) !== hash(join(root, file))) fail('Empreinte divergente : ' + file);
  for (const [name, expected] of Object.entries(adBundle.sha256))
    if (hash(join(root, adBundle.directory, name)) !== expected) fail('Module ActiveDirectory différent du paquet Microsoft épinglé : ' + name);
  pe64(join(root, 'Pesto.exe'));
  if (compareWeb) {
    const source = walk(join(v2, 'web')), actual = files.filter(p => p.startsWith('wad/web/')).map(p => p.slice(8));
    if (JSON.stringify(source) !== JSON.stringify(actual) || source.some(p => hash(join(v2, 'web', p)) !== hash(join(root, 'wad/web', p)))) fail('L’interface du pack diffère des sources courantes.');
  }
  return {files: files.length, info};
}
function copyFile(source, target) {
  if (lstatSync(source).isSymbolicLink()) fail('Lien source interdit.');
  mkdirSync(dirname(target), {recursive: true}); cpSync(source, target, {dereference: false});
}
function copyDocumentation(stage, sourceCommit) {
  const entries = walk(join(v2, 'docs'))
    // Historical evidence stays in Git; nested transaction paths can exceed Windows PS 5.1 limits.
    .filter(path => !path.startsWith('evidence/'))
    .filter(path => ['.md', '.txt', '.pdf'].includes(extname(path).toLowerCase()))
    .map(path => [join(v2, 'docs', path), join(stage, 'wad/docs', path)]);
  entries.push([join(v2, 'README.md'), join(stage, 'wad/docs/README.md')]);
  const delivered = new Map(entries.map(([source, target]) => [resolve(source), target]));
  const ref = sourceCommit || 'codex/pesto-v2-20261023';
  for (const [source, target] of entries) {
    if (extname(source).toLowerCase() !== '.md') { copyFile(source, target); continue; }
    const text = readFileSync(source, 'utf8').replace(/\]\(([^)]+)\)/g, (match, link) => {
      if (!link || link.startsWith('#') || /^[a-z][a-z0-9+.-]*:/i.test(link)) return match;
      const hashIndex = link.indexOf('#');
      const path = hashIndex < 0 ? link : link.slice(0, hashIndex);
      const fragment = hashIndex < 0 ? '' : link.slice(hashIndex);
      const linkedSource = resolve(dirname(source), path);
      if (delivered.has(linkedSource))
        return '](' + relative(dirname(target), delivered.get(linkedSource)).split(sep).join('/') + fragment + ')';
      // Evidence JSON/logs and development files are intentionally absent from PROD.
      // Point to the corresponding repository source instead of shipping a broken local link.
      if (linkedSource.startsWith(v2 + sep)) {
        const repositoryPath = relative(v2, linkedSource).split(sep).map(encodeURIComponent).join('/');
        return '](https://github.com/M4D135/pesto/blob/' + ref + '/v2/' + repositoryPath + fragment + ')';
      }
      return match;
    });
    mkdirSync(dirname(target), {recursive: true}); writeFileSync(target, text);
  }
}
function assemble(args) {
  if (!['DEV', 'PROD'].includes(args.channel)) fail('Canal DEV ou PROD requis.');
  if (args.sourceCommit && !/^[a-f0-9]{40}$/.test(args.sourceCommit)) fail('Commit source invalide.');
  const distribution = args.distribution ?? 'candidate';
  if (!['candidate', 'official'].includes(distribution)) fail('Distribution candidate ou official requise.');
  if (distribution === 'official' && !args.sourceCommit)
    fail('Un pack officiel exige le commit source.');
  const source = resolve(args.source), destination = resolve(args.dest);
  noLinks(source); noLinks(destination);
  if (existsSync(destination)) fail('La destination existe déjà : un pack publié n’est jamais écrasé.');
  if (source === destination || destination.startsWith(source + sep) || source.startsWith(destination + sep)) fail('La destination doit être hors de la publication.');
  if (!existsSync(join(source, 'Pesto.exe')) || existsSync(join(source, 'Pesto.dll'))) fail('Une publication dotnet publish self-contained single-file est requise ; une sortie dotnet build ne suffit pas.');
  pe64(join(source, 'Pesto.exe'));
  const stage = join(dirname(destination), '.pesto-pack-stage-' + process.pid + '-' + Date.now());
  mkdirSync(stage, {recursive: true});
  try {
    copyFile(join(source, 'Pesto.exe'), join(stage, 'Pesto.exe'));
    // This is the authoritative source tree; stale CopyToOutputDirectory files cannot enter the pack.
    for (const path of walk(join(v2, 'web'))) copyFile(join(v2, 'web', path), join(stage, 'wad/web', path));
    // Copy exactly the pinned Microsoft payload, never the V1 configuration or an arbitrary module folder.
    // The second location supports reassembly from the sources delivered inside a complete DEV pack.
    const adSource = [resolve(v2, '../DEV/wad'), resolve(v2, '../runtime/activedirectory')]
      .find(path => existsSync(join(path, 'ActiveDirectory.psd1')));
    if (!adSource) fail('Les six fichiers Microsoft ActiveDirectory de référence sont absents.');
    for (const [name, expected] of Object.entries(adBundle.sha256)) {
      const from = join(adSource, name); noLinks(from);
      if (!existsSync(from) || !lstatSync(from).isFile() || hash(from) !== expected) fail('Source Microsoft ActiveDirectory absente ou altérée : ' + name);
      copyFile(from, join(stage, adBundle.directory, name));
    }
    mkdirSync(join(stage, 'wad/support'), {recursive: true});
    const unblock = '@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p=[IO.Path]::GetFullPath((Join-Path $env:PESTO_UNBLOCK_ROOT \'..\\..\')); Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction Stop | Unblock-File -ErrorAction Stop"\r\n';
    writeFileSync(join(stage, 'wad/support/DEBLOQUER_TOUT.cmd'), '@echo off\r\nset "PESTO_UNBLOCK_ROOT=%~dp0"\r\n' + unblock.slice(11));
    copyDocumentation(stage, args.sourceCommit);
    if (args.channel === 'DEV') {
      for (const subtree of ['src', 'tests', 'tools', 'docs']) {
        const from = join(v2, subtree);
        function copySources(dir) {
          for (const e of readdirSync(dir, {withFileTypes: true})) {
            if (['bin', 'obj', 'node_modules', 'logs', 'vendor', '.git'].includes(e.name)) continue;
            // Only the archived docs subtree is omitted, never a source/test fixture named evidence.
            if (subtree === 'docs' && dir === from && e.name === 'evidence') continue;
            const abs = join(dir, e.name), st = lstatSync(abs);
            if (st.isSymbolicLink()) fail('Lien interdit dans les sources DEV.');
            if (st.isDirectory()) copySources(abs);
            else if (st.isFile() && (sourceExtensions.has(extname(abs).toLowerCase()) || exactDevSourcePaths.has(relative(v2, abs).split(sep).join('/')))
              && !['cfg.json', 'cfg.demo.json'].includes(e.name.toLowerCase()))
              copyFile(abs, join(stage, 'wad/dev', relative(v2, abs)));
          }
        }
        copySources(from);
      }
      for (const path of walk(join(v2, 'web'))) copyFile(join(v2, 'web', path), join(stage, 'wad/dev/web', path));
      for (const path of ['README.md', 'Directory.Build.props', 'global.json', 'NuGet.config']) copyFile(join(v2, path), join(stage, 'wad/dev', path));
      for (const path of walk(join(v2, 'vendor/nuget'))) if (extname(path).toLowerCase() === '.nupkg' || basename(path) === 'SHA256SUMS')
        copyFile(join(v2, 'vendor/nuget', path), join(stage, 'wad/dev/vendor/nuget', path));
      // The Socle index is embedded by Pesto.Engine: a DEV rebuild needs it, never the runtime itself.
      copyFile(join(v2, socleIndexPath), join(stage, 'wad/dev', socleIndexPath));
    }
    const info = {schemaVersion: 2, packName: spec.packName, version: args.version ?? spec.version, channel: args.channel,
      entryPoint: 'Pesto.exe', layout: spec.layout, repository: 'M4D135/pesto', distribution, official: distribution === 'official',
      qualification: 'unqualified', webview2Runtime: 'evergreen'};
    if (args.sourceCommit) info.sourceCommit = args.sourceCommit;
    writeFileSync(join(stage, manifestPath), JSON.stringify(info, null, 2) + '\n');
    writeSums(stage);
    verify(stage, true);
    if (existsSync(destination)) fail('La destination est apparue pendant l’assemblage.');
    renameSync(stage, destination);
    return {destination};
  } finally {if (existsSync(stage)) rmSync(stage, {recursive: true, force: true});}
}
function parse(argv) {
  const args = {};
  const values = {'--verify': 'verify', '--source': 'source', '--dest': 'dest', '--channel': 'channel', '--source-commit': 'sourceCommit', '--version': 'version', '--distribution': 'distribution'};
  const forbidden = new Set(['--webview2', '--webview2-version', '--allow-missing-webview2', '--evergreen']);
  for (let i = 0; i < argv.length; i++) {
    if (forbidden.has(argv[i])) fail('Les packs Pesto sont LIGHT : le WebView2 fixe vient du Socle (lien), jamais du pack.');
    else if (values[argv[i]]) {if (!argv[i+1] || argv[i+1].startsWith('--')) fail('Valeur manquante : ' + argv[i]); args[values[argv[i]]] = argv[++i];}
    else fail('Option inconnue : ' + argv[i]);
  }
  return args;
}
try {
  const args = parse(process.argv.slice(2));
  if (args.verify) {const result = verify(resolve(args.verify)); console.log(`PACK VÉRIFIÉ — ${result.files} fichiers, ${result.info.channel}, ${result.info.distribution} (qualification Windows distincte).`);}
  else {
    if (!args.source || !args.dest || !args.channel) fail('Usage : --source <publication single-file> --dest <nouveau dossier> --channel PROD|DEV | --verify <dossier>');
    const result = assemble(args); console.log(`PACK VÉRIFIÉ — ${result.destination}`);
  }
} catch (error) {console.error('PACK REFUSÉ — ' + error.message); process.exitCode = 2;}
