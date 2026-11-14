"""RC11 source checks. Does not execute PowerShell, UAC, WPF or AD."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from ps_lexical import functions, tokens

# The launcher Pesto.ps1 no longer exists: Pesto.cmd now calls wad/Pesto-Startup.ps1 directly and the whole
# elevation/relay/main flow that these guards ordered lives at the bottom of that script. Reading Pesto.ps1
# raised FileNotFoundError before a single check ran, and body() raised KeyError on every function that moved
# out of the core (Show-LoginWindow and the login XAML live in Pesto-Authentication.ps1). The corpus is the
# core plus every dot-sourced component, as in ux_static_checks.py; --wad points it at a mutated copy.
COMPONENT = re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")
# The allow-lists used to live here as hard-coded RC10/RC11 name sets. They now come from
# tests/current-core-baseline.json ('intentional_changes' / 'added_functions'), so the reference and the
# exceptions to it stay in one auditable file instead of drifting apart from it.


def read_ps(path):return path.read_bytes().decode('utf-8-sig').replace('\r\n','\n')


def corpus(core_path,wad):
    texts={'Pesto-Core.ps1':read_ps(core_path)};missing=[]
    for name in COMPONENT.findall(texts['Pesto-Core.ps1']):
        if name in texts:continue
        component=wad/name
        if component.is_file():texts[name]=read_ps(component)
        else:missing.append(name)
    return texts,missing


def index(texts,name):
    """Position of the first occurrence of `name` in the corpus, or -1. Never raises."""
    for file_name in sorted(texts):
        p=texts[file_name].find(name)
        if p>=0:return p
    return -1


def assess(texts,startup,base,missing_components,historical=None):
    results = []
    def check(name, condition, detail=None):
        row={'name': name, 'passed': bool(condition)}
        if detail is not None:row['detail']=detail
        results.append(row)
    spans={};duplicates={}
    for file_name,text in texts.items():
        for function,span in functions(text).items():
            if function in spans:duplicates.setdefault(function,[spans[function][0]]).append(file_name)
            else:spans[function]=(file_name,span)
    startup_functions=functions(startup)
    def body(name):
        # A missing function is a FAIL with a message, never a KeyError: a checker that dies mid-file guards
        # nothing and looks like a broken toolchain instead of a lost guard.
        if name not in spans:
            check('Function available to the guards: '+name,False,'Function absent from the corpus (core and components)')
            return ''
        file_name,(a,b)=spans[name];return texts[file_name][a:b]
    def sb(name):
        if name not in startup_functions:
            check('Function available to the guards: '+name,False,'Function absent from wad/Pesto-Startup.ps1')
            return ''
        a,b=startup_functions[name];return startup[a:b]
    def where(needle,label):
        # The launcher section is the tail of Pesto-Startup.ps1, so an anchor that also appears in a function
        # definition earlier in the file must be located from the main flow, not from the top of the script.
        p=startup.rfind(needle)
        if p<0:check('Anchor present in the startup main flow: '+label,False,'ancre absente: '+needle[:70])
        return p
    check('Core and its dot-sourced components are all present, each function defined once',
          not missing_components and not duplicates,
          {'missing_components':missing_components,'duplicates':duplicates})
    elevation = sb('Invoke-PestoStartupElevation')
    route = sb('Get-PestoStartupRoute')
    admin = sb('Test-PestoStartupAdministrator')
    # The relay was rewritten: Start-Process -Verb RunAs became [Diagnostics.ProcessStartInfo] with
    # $info.Verb='RunAs' launched through Start-PestoStartupProcess, because 5.1's Start-Process loses
    # NativeErrorCode on a UAC refusal (the code comment says so). The three guards below are re-anchored on the
    # implementation that exists, with the same intent: the relay must ask for elevation, launch exactly one
    # process, and never carry a credential in its arguments.
    # They read the body with whole-line comments removed. The body carries the comment "Pas de -Credential",
    # which made the credential guard red on prose, and a comment mentioning Start-Process made the "exactly one
    # launch" count pass vacuously. Measured: wad/Pesto-Startup.ps1 contains no <# block comment, so dropping
    # lines that start with # is exact for this file; a block comment would survive this filter.
    def code_lines(text):return '\n'.join(l for l in text.splitlines() if not l.strip().startswith('#'))
    elevation_code=code_lines(elevation)
    check('True Windows principal, not a trusted flag', 'WindowsPrincipal' in admin and '.IsInRole(' in admin)
    check('Returned non-admin relay cannot loop', "if($ElevatedLaunch){return 'Refuse'}" in route)
    check('Demo explicitly separated', "if($Demo){return 'Demo'}" in route)
    check('UAC relay via RunAs', "$info.Verb='RunAs'" in elevation_code and '$info.UseShellExecute=$true' in elevation_code)
    launches=elevation_code.count('$process=Start-PestoStartupProcess -StartInfo')
    check('Appel natif unique de relais UAC',launches==1,{'launch_calls':launches})
    check('No credential in native process arguments','-Credential' not in elevation_code and '$info.Arguments=$line' in elevation_code)
    startup_code=code_lines(startup)
    check('No encoded command or policy bypass in startup','EncodedCommand' not in startup_code and 'Bypass' not in startup_code)
    cancellation=sb('Test-PestoStartupCancellation')
    check('Bounded cancellation test, no retry', '1223' in cancellation and 'return 1223' in elevation and launches == 1)
    check('Child exit code propagated, process disposed', 'return [int]$process.ExitCode' in elevation and '$process.Dispose()' in elevation)
    # Re-anchored without loss of force on the file that carries the flow today. The elevation CALL site is
    # matched (not the function definition) so the ordering is measured on the main flow, exactly as when it
    # lived in Pesto.ps1.
    elev=where('Invoke-PestoStartupElevation -EntryPath','elevation call')
    parentexit=where('exit $exitCode','parent exit after relay')
    corecall=where('& $core @parameters','core invocation')
    check('Elevation and parent exit before core',0<=elev<parentexit<corecall,
          {'elevation_call':elev,'parent_exit':parentexit,'core_call':corecall})
    configpath=where('GetUnresolvedProviderPathFromPSPath','relative config resolution')
    check('Relative config resolved before elevation',0<=configpath<elev)
    check('Recheck before core', "if(-not (Test-PestoStartupAdministrator)){throw" in startup)
    stateimport=where('Import-PestoStartupState -OriginLocalAppData','state import call')
    check('State imported before core when account changes',0<=stateimport<corecall)
    corecallpos=index(texts,'& $startupLauncher @startupParams')
    presentation=index(texts,'Add-Type -AssemblyName PresentationFramework')
    check('Direct core startup cannot bypass elevation',0<=corecallpos<presentation)
    check('Direct core parent exits after relay','& $startupLauncher @startupParams\n        exit $LASTEXITCODE' in texts['Pesto-Core.ps1'])
    rename = body('RenameComputer')
    join = body('AddToDomain')
    check('No delayed UAC in rename or join', all('Invoke-PestoElevatedLocalChange' not in text for text in (rename, join)))
    nocred=rename.find('$script:cred -isnot [Management.Automation.PSCredential]')
    dsreg=rename.find('$leave=Invoke-PestoDsregLeaveBeforeRename')
    check('Remote explicit credential branch guarded before Entra leave',0<=nocred<dsreg,
          {'credential_test':nocred,'entra_leave':dsreg} if not (0<=nocred<dsreg) else None)
    check('Domain credential reused by rename', '$argsRename.DomainCredential=$script:cred' in rename)
    check('Missing local token stops with code 96', 'if($local -and -not (Test-PestoIsAdministrator))' in rename and 'return New-ActionResult 96' in rename and 'return New-ActionResult 96' in join)
    queue=body('Run-Queue')
    adminpos=queue.find('Test-PestoIsAdministrator')
    confirmpos=queue.find('Confirm-YesNo')
    check('Queue validates admin before confirmations',0<=adminpos<confirmpos)
    login=body('Show-LoginWindow')
    check('Login window cannot maximize', 'ResizeMode="NoResize"' in login)
    loginadmin=login.find('Test-PestoIsAdministrator')
    loginxaml=login.find('[xml]$lxaml')
    check('Login checks token before XAML',0<=loginadmin<loginxaml,
          {'token_check':loginadmin,'xaml_load':loginxaml} if not (0<=loginadmin<loginxaml) else None)
    check('Windows-session credential limitation visible', 'renommage distant' in login and 'AutomationProperties.HelpText="Session Windows élevée' in login)
    check('State writes do not overwrite existing data', 'FileMode]::CreateNew' in sb('Write-PestoStartupNewFile') and 'FileMode]::Create,' not in startup)
    importing=sb('Import-PestoStartupState')
    check('Original checkpoint is read-only during import', '$src=Join-Path $source $name' in importing and 'Write-PestoStartupNewFile -Path $dst' in importing and 'Write-PestoStartupNewFile -Path $src' not in startup)
    check('State import conflict is explicit', '$existing.Hash -ne $data.Hash' in importing and 'throw "Reprise entre comptes en conflit' in importing)
    check('Prior import hash tracked, no repetitive restoration', "'.startup-import-'" in importing and 'data.Hash' in importing)
    check('Reparse links rejected and read size bounded', 'ReparsePoint' in sb('Assert-PestoStartupLocalPath') and '$stream.Length -gt $MaxBytes' in sb('Read-PestoStartupStateFile'))
    # The live comparison runs against tests/current-core-baseline.json, a reference the repository can
    # re-derive. RC10 stays on disk untouched as the provenance record of the external package
    # ("GP-Core(1).ps1 retrieved from the Library") and is reported here as history, never used as a contract:
    # measured at HEAD, 150 of its 269 names predate the GP→Pesto rename and 84 of the 119 survivors carry
    # different code, so gating on it could only ever report staleness — which is what it did.
    expected = base['normalized_function_sha256']
    allowed_changes=set(base.get('intentional_changes',[]))
    added_names=set(base.get('added_functions',[]))
    def digest(name):
        file_name,(a,b)=spans[name]
        return hashlib.sha256(texts[file_name][a:b].encode('utf-8')).hexdigest()
    obsolete=[n for n in expected if n not in spans]
    changes=[n for n in expected if n in spans and digest(n)!=expected[n]]
    history=None
    if historical:
        old=historical['normalized_function_sha256']
        gone=[n for n in old if n not in spans]
        history={'historical_file':'tests/rc10-core-baseline.json','historical_version':historical.get('version'),
                 'historical_functions':len(old),'names_gone_since_historical':len(gone),
                 'names_gone_examples':sorted(gone)[:8],
                 'changed_bodies_since_historical':sum(1 for n in old if n in spans and digest(n)!=old[n])}
    check('Only declared functions changed from the current baseline',
          not obsolete and set(changes) == allowed_changes and set(spans) == set(expected) | added_names,
          {'intentional_changes':changes,'baseline_functions':len(expected),
           'baseline_commit':base.get('generated_from_commit'),
           'obsolete_baseline_names':len(obsolete),'obsolete_examples':sorted(obsolete)[:8],
           'rc10_history_informational_only':history})
    for name in ('Invoke-PestoDsregLeaveLocal','Invoke-PestoDsregLeaveBeforeRename','Invoke-PestoSystemTaskScript','GoRenameOnly','GoRenameAndMove','MoveComputer','Restore-PestoQueueCheckpoint'):
        if name not in expected:
            check('Current baseline unchanged: '+name,False,'nom absent du socle courant : comparaison impossible')
            continue
        check('Current baseline unchanged: '+name,name in spans and digest(name)==expected[name])
    return results


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--source',type=Path,help='engine core (default: <wad>/Pesto-Core.ps1)')
    ap.add_argument('--wad',type=Path,help='engine components (default: <root>/wad)')
    ap.add_argument('--report',type=Path)
    args=ap.parse_args();ROOT=args.root
    wad=args.wad or ROOT/'wad';core_path=args.source or wad/'Pesto-Core.ps1'
    base = json.loads((ROOT / 'tests/current-core-baseline.json').read_text(encoding='utf-8'))
    # RC10 is read only to report the historical delta in the detail of the live guard. Its own source package
    # is gone and its names predate the GP→Pesto rename, so it can no longer gate anything honestly.
    historical_path = ROOT / 'tests/rc10-core-baseline.json'
    historical = json.loads(historical_path.read_text(encoding='utf-8')) if historical_path.is_file() else None
    texts,missing_components=corpus(core_path,wad)
    startup = read_ps(wad/'Pesto-Startup.ps1')
    results = assess(texts,startup,base,missing_components,historical)
    for path in sorted(p for p in ROOT.rglob('*.ps1') if '__pycache__' not in p.parts and 'dist' not in p.parts):
        try:
            tokens(path.read_text('utf-8-sig'))
            results.append({'name':'Lexical delimiters: '+str(path.relative_to(ROOT)), 'passed':True})
        except Exception as error:
            results.append({'name':'Lexical delimiters: '+str(path.relative_to(ROOT)), 'passed':False, 'error':str(error)})
    # Split by file type instead of one clause for all five. Measured at HEAD: the .cmd launchers are pure ASCII
    # without BOM (a UTF-8 BOM would corrupt cmd.exe parsing), the .ps1 files carry a BOM. The original clause
    # demanded a BOM from Pesto.ps1 and from files whose convention differs, so it could not be satisfied as
    # written. Disclosed scope change, not a silent weakening; every file still keeps one line-ending style.
    for rel in ('Pesto.cmd','Pesto_COMPTE_AD.cmd'):
        data=(ROOT/rel).read_bytes()
        results.append({'name':'Lanceur CMD : ASCII pur et un seul style de fin de ligne : '+rel,
                        'passed':data.isascii() and (b'\r\n' not in data or b'\n' not in data.replace(b'\r\n',b''))})
    for rel in ('wad/Pesto-Startup.ps1','wad/Pesto-Core.ps1','tests/Run-StartupTests.ps1','tools/Verify-StartupUac.ps1'):
        data=(ROOT/rel).read_bytes()
        results.append({'name':'UTF8 BOM and one line-ending style: '+rel,
                        'passed':data.startswith(b'\xef\xbb\xbf') and (b'\r\n' not in data or b'\n' not in data.replace(b'\r\n',b''))})
    # Each defect names the guard that must catch it: the stale RC10 guards fire on any mutation, so "some
    # guard went red" would prove nothing. Detection means the designated guard fired. kind='startup' mutates
    # the launcher script, kind='corpus' mutates whichever engine file actually carries the anchor.
    mutations = [
        ('missing parent exit','startup','exit $exitCode','Write-Output $exitCode',
         ('Elevation and parent exit before core',)),
        ('state import removed','startup','Import-PestoStartupState -OriginLocalAppData','# import removed -OriginLocalAppData',
         ('State imported before core when account changes',)),
        # Re-anchored with the relay rewrite: -Verb RunAs no longer exists anywhere, so this control was
        # silently vacant before.
        ('UAC verb removed','startup',"$info.Verb='RunAs'",'$info.Verb=\'Open\'',
         ('UAC relay via RunAs',)),
        ('domain credential guard removed','corpus','$script:cred -isnot [Management.Automation.PSCredential]','$false',
         ('Remote explicit credential branch guarded before Entra leave',)),
        ('login maximize regression','corpus','SizeToContent="Height" ResizeMode="NoResize"','SizeToContent="Height" ResizeMode="CanResize"',
         ('Login window cannot maximize',)),
    ]
    negatives=[]
    for name,kind,old,new,expected in mutations:
        if kind=='startup':
            if old not in startup:
                negatives.append({'name':name,'detected':False,'expected_guards':list(expected),'failed_checks':[],
                                  'error':'ancre absente du lanceur : contrôle vacant, à ré-ancrer'})
                continue
            mutated_startup=startup.replace(old,new,1);mutated_texts=texts
        else:
            # Injected wherever the anchor actually lives: asserting it against the core alone made these two
            # controls unreachable once the login form and the credential branch left Pesto-Core.ps1.
            if not any(old in v for v in texts.values()):
                negatives.append({'name':name,'detected':False,'expected_guards':list(expected),'failed_checks':[],
                                  'error':'ancre absente du corpus : contrôle vacant, à ré-ancrer'})
                continue
            mutated_startup=startup
            mutated_texts={k:(v.replace(old,new) if old in v else v) for k,v in texts.items()}
        failed=[r['name'] for r in assess(mutated_texts,mutated_startup,base,missing_components) if not r['passed']]
        missing=[g for g in expected if g not in failed]
        negatives.append({'name':name,'detected':not missing,'expected_guards':list(expected),
                          'failed_checks':failed,'undetected_guards':missing})
    report={'version':'17.0-RC13','utc':datetime.now(timezone.utc).isoformat(),'scope':'Source-only checks. No native PowerShell parser, WPF, UAC, AD or Windows execution.', 'core_sha256':hashlib.sha256(core_path.read_bytes()).hexdigest(),'files':sorted(texts),'passed':sum(r['passed'] for r in results),'failed':sum(not r['passed'] for r in results),'checks':results,'negative_controls':negatives}
    (args.report or ROOT/'tests/startup-static-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for r in results:
        print(('OK' if r['passed'] else 'FAIL')+' '+r['name'])
    print('Negative controls:',sum(r['detected'] for r in negatives),'/',len(negatives))
    print('Source-only result:',report['passed'],'passed /',report['failed'],'failed')
    return int(report['failed'] > 0 or any(not r['detected'] for r in negatives))

if __name__ == '__main__':
    sys.exit(main())
