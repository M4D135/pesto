#!/usr/bin/env python3
"""Reproducible, dependency-free structural checks. NOT a PowerShell parser.
No application execution, no AD access, no WPF rendering, no compilation.
"""
from __future__ import annotations
import argparse, datetime as dt, hashlib, json, re, sys, xml.etree.ElementTree as ET
from pathlib import Path
from ps_lexical import functions, smart_quote_hazards, tokens

# The engine spread its functions over the components the core dot-sources, the main window template left the
# core for wad/Pesto-Shell.xaml, the launcher Pesto.ps1 was replaced by Pesto.cmd + wad/Pesto-Startup.ps1 + a
# native Pesto.exe, and DEBLOQUER_TOUT.cmd moved to wad/support/. Read against Pesto-Core.ps1 and Pesto.ps1
# alone, this file died with KeyError: 'cfg.json' before writing any report: it guarded nothing at all. The
# corpus is now the core plus every dot-sourced component, as in ux_static_checks.py.
COMPONENT=re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")
SHELL_XAML='Pesto-Shell.xaml'
UNBLOCK='wad/support/DEBLOQUER_TOUT.cmd'
UNBLOCK_MARKER=':__PESTO_SUPPORT_POWERSHELL__'

def read_ps(path):return path.read_bytes().decode('utf-8-sig').replace('\r\n','\n')

def main() -> int:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--source',type=Path,help='engine core (default: <wad>/Pesto-Core.ps1)')
    ap.add_argument('--wad',type=Path,help='engine components and templates (default: <root>/wad)')
    ap.add_argument('--report',type=Path)
    args=ap.parse_args();root=args.root.resolve()
    report_path=args.report or root/'tests'/'static-report.json'
    checks=[];metrics={}
    def check(name, fn):
        try:
            detail=fn()
            checks.append(dict(name=name,status='PASS',detail=detail))
        except Exception as ex:
            checks.append(dict(name=name,status='FAIL',detail=str(ex)))
    def require(value, message):
        if not value: raise AssertionError(message)
    source=args.source or (args.wad or root/'wad')/'Pesto-Core.ps1'
    wad=args.wad or root/'wad'
    raw=source.read_bytes();s=raw.decode('utf-8-sig').replace('\r\n','\n')
    texts={'Pesto-Core.ps1':s};missing_components=[]
    for name in COMPONENT.findall(s):
        if name in texts:continue
        component=wad/name
        if component.is_file():texts[name]=read_ps(component)
        else:missing_components.append(name)
    funcs={};duplicates={}
    for file_name,text in texts.items():
        for name,span in functions(text).items():
            if name in funcs:duplicates.setdefault(name,[funcs[name][0]]).append(file_name)
            else:funcs[name]=(file_name,span)
    def block(name):
        # A missing function is a FAIL that names it, never a KeyError whose message is just the function name.
        if name not in funcs:raise AssertionError('Function absent from the corpus (core and components): '+name)
        file_name,(a,b)=funcs[name];return texts[file_name][a:b]
    check('Core and its dot-sourced components are all present, each function defined once',
          lambda:require(not missing_components and not duplicates,
                         'Missing components: '+str(missing_components)+'; duplicates: '+str(duplicates)))
    metrics['root_functions']=len(funcs)
    check('wad/Pesto-Core.ps1 : UTF-8 BOM',lambda:require(raw.startswith(b'\xef\xbb\xbf'),'BOM absent'))
    # The old list read Pesto.ps1, which no longer exists. The two .cmd launchers are deliberately left out of
    # this sweep: the PowerShell lexer has nothing to do on batch files (it would report a delimiter mismatch on
    # every parenthesis). Their own encoding and structure is guarded by the CMD checks below.
    def rel(p):
        # Evaluated outside check(), so it must never raise: --wad may point outside the tree.
        try:return str(p.relative_to(root))
        except ValueError:return str(p)
    for p in [source,wad/'Pesto-Startup.ps1',root/'tests/Run-EngineTests.ps1',root/'tests/Run-RC4Tests.ps1',root/'tests/Run-PackageTests.ps1',root/'tools/Build-Pesto.ps1']:
        def lex_file(p=p):
            t=p.read_text(encoding='utf-8-sig');fs=functions(t)
            return {'root_functions':len(fs),'lexical_tokens':len(tokens(t)),'scope':'Lexical only; here-string contents not PowerShell-parsed'}
        check(rel(p)+' : délimiteurs et fonctions racines',lex_file)
        # Re-anchored on the project's own instrument, disclosed as a scope change. The old clause failed on any
        # U+2018/U+2019/U+201C/U+201D anywhere in the file, including comments and here-strings, where PowerShell
        # reads them as ordinary text. Measured at HEAD: Pesto-Core.ps1 carries typographic quotes that
        # smart_quote_hazards() — which only reports the ones inside ASCII-delimited strings, the ones that
        # really break 5.1 — returns [] for. Demanding their absence would have forced either a red guard on a
        # healthy tree or the deletion of harmless prose.
        def typographic(p=p):
            text=p.read_text(encoding='utf-8-sig')
            naive=sum(text.count(c) for c in '\u2018\u2019\u201c\u201d')
            hazards=smart_quote_hazards(text)
            require(not hazards,'Guillemet typographique dans une chaîne littérale : '+str(hazards[:4]))
            return {'typographic_characters':naive,'hazards_in_strings':0}
        check(rel(p)+' : pas de guillemets typographiques dans les chaînes',typographic)
    # XML templates now live in two places: here-strings inside the components, and standalone .xaml files the
    # core loads by name. Both are collected; the old code only knew the core's here-strings, so the main window
    # had simply disappeared from this check.
    windows={}
    for file_name,text in texts.items():
        for match in re.finditer(r'(?m)^\s*\[xml\]\$(\w+)\s*=\s*@([\'\"])\s*\n',text):
            name,q=match.group(1,2);end=re.search(r'(?m)^'+re.escape(q)+r'@',text[match.end():])
            require(end is not None,'Here-string XML non fermé dans '+file_name)
            windows[file_name+'$'+name]=text[match.end():match.end()+end.start()]
    for template in sorted(wad.glob('*.xaml')):
        windows[template.name]=read_ps(template)
    metrics['xml_windows']=len(windows)
    for name,xml in windows.items():
        check('XAML '+name+' : XML bien formé (gabarit)',lambda xml=xml: {'elements':sum(1 for _ in ET.fromstring(xml).iter())})
    def ui_bindings():
        # Re-anchored: the main grid left the core here-doc for wad/Pesto-Shell.xaml, which the core loads by
        # name. Both halves are required, so the template can be neither dropped nor swapped for another file.
        require("Join-Path $PSScriptRoot '"+SHELL_XAML+"'" in s,'Le cœur ne charge plus '+SHELL_XAML)
        require((wad/SHELL_XAML).is_file(),'Gabarit principal absent: '+SHELL_XAML)
        tree=ET.fromstring(read_ps(wad/SHELL_XAML))
        def public_nodes(node):
            # Template parts such as PART_ContentHost legally repeat in independent scopes.
            if node.tag.rsplit('}',1)[-1] in ('ControlTemplate','DataTemplate'):
                return
            yield node
            for child in node:
                yield from public_nodes(child)
        names=[e.attrib.get('Name') or e.attrib.get('{http://schemas.microsoft.com/winfx/2006/xaml}Name') for e in public_nodes(tree)]
        names=[n for n in names if n]
        require(len(names)==len(set(names)),'Noms XAML dupliqués dans la portée publique')
        m=re.search(r'(?ms)^\$names = (.*?)^foreach \(\$n in \$names\)',s)
        require(m is not None,'Liste de liaisons introuvable')
        bound=re.findall(r"'([^']+)'",m.group(1));missing=sorted(set(bound)-set(names))
        require(not missing,'Liaisons sans contrôle : '+', '.join(missing))
        metrics['main_controls_bound']=len(bound)
        return {'bound':len(bound),'named_elements':len(names),'missing':missing,'template':SHELL_XAML}
    check('Correspondance noms XAML / contrôles principaux',ui_bindings)
    def workers():
        # The closed worker list is not one literal: the product builds it with a first @(...) followed by a
        # chain of +=@(...) and only then deduplicates it. Reading only the first assignment (re.search) hid 40
        # exported names, and the guard then reported 16 "missing dependencies" that are in fact exported — an
        # instrument error on my side, not a product defect. Every assignment is now unioned. (The optional
        # operator group is (?:\+)?= , not (?:\+=)?= : the latter demands "+=" *and* another "=", so it silently
        # matched only the two plain assignments — measured: 2 chunks / 68 names instead of 9 chunks / 108.)
        chunks=re.findall(r"\$script:PestoWorkerCoreNames\s*(?:\+)?=\s*@\((.*?)\)",s,re.S)
        require(bool(chunks),'Liste de fonctions worker absente')
        names=[]
        for chunk in chunks:names+=re.findall(r"'([^']+)'",chunk)
        names=list(dict.fromkeys(names))
        missing=set(names)-set(funcs)
        require(not missing,'Fonctions worker absentes : '+str(missing))
        # The worker deliberately supplies non-UI logging/confirmation helpers locally.
        start=s.index('$script:PestoQueueWorker = {')+len('$script:PestoQueueWorker = {')
        depth=1;end=None
        for kind,a,b in tokens(s):
            if a<start:continue
            if kind=='{':depth+=1
            elif kind=='}':
                depth-=1
                if depth==0:end=a;break
        require(end is not None,'Bloc worker non trouvé')
        local=set(functions(s[start:end]))
        refs=set()
        for n in names:
            t=block(n)
            for kind,a,b in tokens(t):
                if kind=='word' and t[a:b] in funcs:refs.add(t[a:b])
        require(not refs-set(names)-local,'Dépendances fonctions absentes du worker : '+str(refs-set(names)-local))
        metrics['worker_functions']=len(names)
        return {'declared':len(names),'missing_dependencies':sorted(refs-set(names)-local),'worker_local_helpers':sorted(local),'scope':'Top-level lexical function references; no dynamic resolution'}
    check('Fonctions exportées aux workers / fermeture lexicale',workers)
    def test_loads():
        t=(root/'tests/Run-EngineTests.ps1').read_text(encoding='utf-8-sig')
        m=re.search(r'\$load=@\((.*?)\)\s*foreach',t,re.S)
        require(m is not None,'Chargement suite de tests absent')
        names=re.findall(r"'([^']+)'",m.group(1))
        require(not set(names)-set(funcs),'La suite charge une fonction absente')
        return {'extracted_function_definitions':len(names),'executed':False}
    check('Suite Windows : fonctions référencées présentes',test_loads)
    def no_password_cli():
        executable=[text[a:b].lower() for text in texts.values() for kind,a,b in tokens(text) if kind=='word']
        require('schtasks.exe' not in executable and 'schtasks' not in executable,'Ancien exécutable trouvé dans le code')
        require("@('/s',$ComputerName)" in block('Get-PestoSchtasksTransportArgs'),'Transport inattendu')
        require("@('/p','/rp','/u')" in block('Invoke-PestoSchtasks'),'Garde anti-arguments secrets absente')
        return 'COM transport and explicit rejection guard present; not a dynamic information-flow proof.'
    check('Absence de schtasks.exe et garde anti-secret CLI',no_password_cli)
    # Three of these fragments moved with the code that carries them; each is re-anchored on the form that
    # exists, with the same intent, and disclosed here rather than dropped:
    #  - the Entra status re-read lost its -Argument label (positional call now);
    #  - the protected-from-deletion restore is no longer a single boolean test but a Set-ADObject guarded by
    #    $restoreRequired, so the guard now names the write that actually restores protection;
    #  - Run-Queue no longer arms the security lock itself: it hands the run to Request-PestoQueuePump, whose
    #    dispatcher catch sets MutationUncertain. The guard is split in two (call site + arm) so neither half can
    #    be deleted without going red.
    for name,fragment in [
        ('Test-PestoPipeClient','GetNamedPipeClientProcessId'),
        ('Invoke-PestoElevatedLocalChange','Test-PestoPipeClient -Pipe $pipe -ExpectedProcessId $proc.Id'),
        ('RenameComputer','Test-PestoConfirmedChange $change'),
        ('AddToDomain','Test-PestoConfirmedChange $change'),
        ('Invoke-PestoDsregLeaveBeforeRename','if($ComputerName -ieq $env:COMPUTERNAME)'),
        ('Invoke-PestoDsregLeaveLocal',"$after=Invoke-DsregNative '/status'"),
        ('RenameComputer','if($leave.ExitCode -ne 20){return $leave}'),
        ('MoveComputer','Move-ADObject -Identity $id'),
        ('MoveComputer','Set-ADObject -Identity $id -ProtectedFromAccidentalDeletion:$true'),
        ('Complete-PestoQueueItem','if($code -in @(32,97,98))'),
        ('Run-Queue','Request-PestoQueuePump'),
        ('Request-PestoQueuePump','$script:MutationUncertain=$true'),
        ('Write-PestoAtomicText','[IO.File]::Replace'),
        ('Read-PestoStartupConfig','Test-CfgValid')]:
        check('Garde structurelle '+name+' : '+fragment[:42],lambda name=name,fragment=fragment:require(fragment in block(name),'Fragment de garde absent'))
    def domain_dn(cfg):
        domain=cfg['CONF'][0]['Domaine'].lower().rstrip('.')
        entries=list(cfg['OUBase'])+list(cfg['OUSite'])
        entries.append({'Nom':'OUScanNoms','OU':cfg['CONF'][0].get('OUScanNoms','')})
        bad=[]
        for e in entries:
            if not e['OU']:continue
            actual='.'.join(re.findall(r'(?:^|,)DC=([^,]+)',e['OU'],re.I)).lower()
            if actual!=domain:bad.append({'name':e['Nom'],'domain':domain,'dn_domain':actual})
        return bad
    cfgs={}
    # cfg.json and cfg.original.json are user files, never shipped: measured absent at HEAD. Reading them
    # unconditionally is what killed this controller (KeyError: 'cfg.json'). Only shipped configurations are
    # required; a user configuration found on disk is still validated.
    for name in ['cfg.json','cfg.original.json','cfg.example.json','cfg.demo.json']:
        def read_cfg(name=name):
            path=root/'wad'/name
            if not path.is_file():
                if name in ('cfg.example.json','cfg.demo.json'):raise AssertionError('Configuration livrée absente : '+name)
                return 'non livré (fichier utilisateur) ; rien à valider ici'
            cfgs[name]=json.loads(path.read_text(encoding='utf-8-sig'));return 'JSON readable; not full runtime configuration validation'
        check(name+' : JSON',read_cfg)
    check('Configuration exemple : domaine / DN cohérents',lambda:require(not domain_dn(cfgs['cfg.example.json']),'Exemple incohérent'))
    check('Démonstration : domaine / DN cohérents',lambda:require(not domain_dn(cfgs['cfg.demo.json']),'Démo incohérente'))
    check('Démonstration : GUI et Simulation actifs',lambda:require(all(str(cfgs['cfg.demo.json']['DEBUG'][k]).lower()=='true' for k in ('GUI','Simulation')),'Démo non isolée'))
    check('Option legacy de réparation désactivée dans l’exemple',lambda:require(str(cfgs['cfg.example.json']['CONF'][0].get('AllowHybridRepair',False)).lower()=='false','Option legacy active dans l’exemple'))
    # Le cfg.json de l'utilisateur est une frontière, pas une donnée de build. Mesuré sur le Mac du 11/10/2026 :
    # DEV/wad/cfg.json (ignoré par git) y est le stub {"SchemaVersion":2,"Configured":false,"Notice":…} que le
    # produit écrit lui-même à la première utilisation. L'ancien code lisait cfg['CONF'] sans filtre : KeyError
    # non rattrapé, contrôleur mort, aucun rapport écrit — 69 gardes supprimées par un fichier utilisateur.
    # Le stub n'est pas une configuration corrompue : Test-CfgValid traite « Configured != $true » comme
    # « première utilisation : importez une configuration d'entreprise valide ». Même sémantique ici : rien à
    # valider, mais un cfg.json qui se déclare configuré sans section CONF reste un FAIL.
    warnings=[]
    def user_config():
        if 'cfg.json' not in cfgs:return 'non livré (fichier utilisateur) ; rien à valider ici'
        cfg=cfgs['cfg.json']
        require(isinstance(cfg,dict),'cfg.json utilisateur : objet JSON inattendu')
        if 'CONF' not in cfg:
            require(cfg.get('Configured') is not True,
                    'cfg.json utilisateur annonce Configured=true sans section CONF')
            return {'state':'non importée (Configured=false)','validated':False}
        bad=domain_dn(cfg)
        if bad:warnings.append({'code':'CFG_DOMAIN_MISMATCH','detail':bad,
                                'impact':'Corriger domaine et DN avant connexion. Valeurs utilisateur conservées.'})
        return {'state':'importée','domain_dn_mismatches':len(bad)}
    check('cfg.json utilisateur : structure et domaine / DN',user_config)
    for name in ['wad/Pesto.ico','wad/ActiveDirectory.psd1','wad/'+SHELL_XAML]:
        check('Ressource '+name,lambda name=name:require((root/name).is_file(),'Ressource manquante'))
    if (root/'tests/original-assets.json').is_file():
        def original_assets():
            # encoding='utf-8' explicitly: this manifest carries notes, and read_text() with no encoding falls
            # back to the machine locale on Windows (cp1252 under Python 3.9), which would raise UnicodeDecodeError
            # inside check() and take the whole controller down — the same failure mode as the cfg.json KeyError.
            # Keys prefixed '_' are manifest notes, not shipped files: the loader used to treat every key as a
            # path, so any note written into the manifest became a FAIL.
            manifest=json.loads((root/'tests/original-assets.json').read_text(encoding='utf-8'))
            notes={k:v for k,v in manifest.items() if k.startswith('_')}
            assets={p:sha for p,sha in manifest.items() if not p.startswith('_')}
            # A manifest that names a file the package no longer ships used to raise FileNotFoundError out of
            # check() and read as a crash of the whole controller. It is now a FAIL that names the file: an
            # unverifiable reference is not a preserved asset, and the report still describes the run.
            absent=sorted(p for p in assets if not (root/p).is_file())
            require(not absent,'Empreinte sans fichier correspondant (manifeste perime ?) : '+', '.join(absent))
            for p,sha in assets.items():require(hashlib.sha256((root/p).read_bytes()).hexdigest()==sha,'Ressource originale altérée : '+p)
            return {'files_verified':len(assets),'manifest_notes':notes}
        check('Configuration originale / icône / modules : empreintes conservées',original_assets)
    # Packaging checks: structural only, not cmd.exe or NTFS execution.
    launch_cmd=(root/'Pesto.cmd').read_text('ascii')
    unblock_path=root/UNBLOCK
    unblock=unblock_path.read_text('ascii')
    # The embedded payload is everything after the batch label LINE. Slicing at the marker itself cuts inside
    # the batch line that searches for it ($m='__PESTO_SUPPORT_POWERSHELL__'), which leaves the lexer one quote
    # out of parity and reporting "Unclosed string" at the end of the file. Measured at HEAD: the whole file
    # lexes (866 tokens) and so does the payload taken from the next line (831 tokens).
    label=re.search(r'(?m)^'+re.escape(UNBLOCK_MARKER)+r'[ \t]*$',unblock)
    unblock_code='' if label is None else unblock[label.end()+1:]
    build=(root/'tools/Build-Pesto.ps1').read_text(encoding='utf-8-sig')
    startup=read_ps(wad/'Pesto-Startup.ps1')
    def cmd_format():
        for name in ('Pesto.cmd',UNBLOCK):
            data=(root/name).read_bytes()
            require(data.isascii(),name+' doit rester ASCII')
            require(b'\n' not in data.replace(b'\r\n',b''),name+' : fins de ligne non CRLF')
            require('DisableDelayedExpansion' in data.decode('ascii'),name+' : chemins avec ! non proteges')
        return 'ASCII / CRLF; delayed expansion disabled in both launchers'
    check('CMD : encodage et chemins avec point d\'exclamation',cmd_format)
    def unblock_structure():
        # Re-anchored: the unblocker was rewritten as a self-carrying CMD. It no longer has the
        # "# Pesto_UNBLOCK_POWERSHELL_START" comment marker nor an Invoke-PestoPackageUnblock function; it now
        # re-reads itself and executes the tail after the :__PESTO_SUPPORT_POWERSHELL__ label. The protected
        # property is unchanged: cmd.exe must exit before that label, and the payload must come from the file
        # itself through an environment variable.
        require(unblock.count('\n'+UNBLOCK_MARKER+'\n')==1,'Marqueur du bloc absent ou dupliqué')
        require('exit /b %PESTO_EXIT%\n'+UNBLOCK_MARKER in unblock,'Le CMD pourrait tomber dans le bloc PowerShell')
        require('$env:PESTO_UNBLOCK_SELF' in unblock and 'ReadAllText($env:PESTO_UNBLOCK_SELF)' in unblock,'Charge non transmise par environnement')
        require('LastIndexOf($m,[StringComparison]::Ordinal)' in unblock,'Le CMD ne prend pas son propre bloc final')
        require(unblock_code.strip(),'Bloc PowerShell vide apres le marqueur')
        return {'lexical_tokens':len(tokens(unblock_code)),'scope':'Lexical only, embedded PowerShell not natively parsed'}
    check('CMD de deblocage : bloc autonome et delimiteurs',unblock_structure)
    check('Deblocage : commande litterale et controle du flux apres retrait',lambda:require(
        unblock.count('Unblock-File -LiteralPath $item.FullName -ErrorAction Stop')==2 and
        unblock.count("throw 'La marque est toujours presente.'")==2,
        'Retrait literal / verification apres retrait manquant'))
    check('Deblocage : garde du dossier Pesto et exclusion des jonctions',lambda:require(
        "@('Pesto.exe','wad\\Pesto-Startup.ps1','wad\\Pesto-Core.ps1')" in unblock and
        "throw 'Ce fichier doit rester dans wad\\support.'" in unblock and
        unblock.count('[IO.FileAttributes]::ReparsePoint')>=5 and '-Recurse' not in unblock,
        'Retrait literal / verification manquant'))
    def no_security_changes():
        body=unblock_code
        code_words={body[a:b].lower() for kind,a,b in tokens(body) if kind=='word'}
        forbidden={'set-executionpolicy','set-mppreference','add-mppreference','icacls','takeown','reg','reg.exe','unlock-adaccount','reset-gpsafetylock'}
        require(not code_words & forbidden,'Changement hors deblocage trouve : '+str(code_words & forbidden))
        require('if($failed -gt 0) {exit 1}' in body,'Erreurs du deblocage masquees')
        return 'No global security-policy / ACL / AD unlock command in the embedded code'
    check('Deblocage : aucun changement de politiques, ACL ou verrou metier',no_security_changes)
    # Re-anchored without loss of force: Pesto.ps1 no longer exists. The chain is Pesto.cmd -> x64 PowerShell ->
    # wad/Pesto-Startup.ps1, which resolves the engine core and rechecks the admin token before loading it.
    # Each of those is now asserted on the file that carries it.
    check('Lanceurs : Pesto.cmd vers wad/Pesto-Startup.ps1, PowerShell x64/STA',lambda:require(
        'Sysnative' in launch_cmd and '-NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned' in launch_cmd and
        'wad\\Pesto-Startup.ps1' in launch_cmd and 'DisableDelayedExpansion' in launch_cmd,
        'Chemin lanceur / parametres incorrects'))
    check('Lanceur : code de sortie du moteur propage',lambda:require(
        'set "Pesto_EXIT_CODE=%ERRORLEVEL%"' in launch_cmd and 'exit /b %Pesto_EXIT_CODE%' in launch_cmd,
        'Code de sortie du moteur perdu'))
    # Re-anchored and strengthened. The old anchor "Join-Path $root 'wad\Pesto-Core.ps1'" never appears in
    # wad/Pesto-Startup.ps1, which resolves the core as CorePath=Join-Path $wad 'Pesto-Core.ps1'. The ordering is
    # now measured against the token RECHECK ("if(-not (Test-PestoStartupAdministrator)){throw") instead of the
    # first occurrence of the function name, which was its definition at the top of the file and therefore
    # trivially earlier than any call — a passing guard that proved nothing.
    check('Demarrage : le chargeur resout le cœur et verifie le jeton avant de le charger',lambda:require(
        "CorePath=Join-Path $wad 'Pesto-Core.ps1'" in startup and
        "if(-not (Test-PestoStartupAdministrator)){throw" in startup and
        startup.index('& $core @parameters')>startup.index("CorePath=Join-Path $wad 'Pesto-Core.ps1'") and
        startup.index('& $core @parameters')>startup.index("if(-not (Test-PestoStartupAdministrator)){throw"),
        'Le cœur pourrait être chargé sans relais UAC vérifié'))
    check('Moteur : les chemins AD pointent dans wad, sans ancien mod',lambda:require(
        sum(text.count("Join-Path $BasePath 'ActiveDirectory.psd1'") for text in texts.values())>=5 and
        not any('mod\\ActiveDirectory.psd1' in text for text in texts.values()) and
        "Join-Path $BasePath 'cfg.demo.json'" in s,
        'Ancien chemin mod/demo ou chemin AD manquant'))
    check('Package : pas de double configuration ou de dossier mod',lambda:require(
        not (root/'mod').exists() and not (root/'cfg.json').exists() and not (root/'demo').exists() and
        not (root/'wad/mod').exists(),
        'Ancienne arborescence encore presente'))
    check('Build : lanceur natif compile, wad copie depuis la liste fermee, manifeste controle',lambda:require(
        'Get-PestoRuntimeFiles' in build and '/MACHINE:X64' in build and "Pesto-launcher.c" in build and
        "Copy-Item -LiteralPath (Join-Path $root $rel) -Destination $target" in build and
        "throw 'EXE et composants non concordants.'" in build and
        'Join-Path $root \'wad\\support\\DEBLOQUER_TOUT.cmd\'' in build,
        'Build incompatible avec le package wad'))
    check('Tests Windows : le banc charge tout wad, pas un fichier unique',lambda:require(
        "-Filter '*.ps1'" in (root/'tests/Run-EngineTests.ps1').read_text(encoding='utf-8-sig') and
        "'..\\wad'" in (root/'tests/Run-EngineTests.ps1').read_text(encoding='utf-8-sig'),
        'Ancien chemin dans les tests Windows'))
    failed=sum(x['status']=='FAIL' for x in checks)
    report=dict(version='17.0-RC12',utc=dt.datetime.now(dt.timezone.utc).isoformat(),source_file=str(source.relative_to(root)) if source.is_relative_to(root) else str(source),source_sha256=hashlib.sha256(raw).hexdigest(),
        files=sorted(texts),
        scope='STATIC ONLY: no native PowerShell parsing/execution, no Windows/AD/WPF/UAC/EXE validation',
        totals=dict(checks=len(checks),passed=len(checks)-failed,failed=failed,warnings=len(warnings)),metrics=metrics,checks=checks,warnings=warnings,
        not_executed=['Windows PowerShell 5.1 native parser','Run-EngineTests.ps1','Run-RC4Tests.ps1','Run-PackageTests.ps1 / NTFS streams','cmd.exe launchers','WPF rendering and interactions','Active Directory operations','UAC / named pipe authentication','Task Scheduler COM operations','PS2EXE compilation','EDR/antivirus compatibility'])
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for c in checks:print(c['status']+' '+c['name']+((' : '+str(c['detail'])) if c['status']=='FAIL' else ''))
    print(json.dumps(report['totals'],ensure_ascii=False));print('Report: '+str(report_path))
    return 1 if failed else 0
if __name__=='__main__':
    sys.exit(main())
