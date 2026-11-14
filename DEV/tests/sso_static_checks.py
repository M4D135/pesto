"""RC13 source contracts only. Not a native PS parser or Windows/AD execution."""
from pathlib import Path
import argparse, datetime, hashlib, json, re, sys
import xml.etree.ElementTree as ET
from ps_lexical import functions, tokens

# The engine spread its functions over the components the core dot-sources, and the launcher Pesto.ps1 was
# replaced by Pesto.cmd -> wad/Pesto-Startup.ps1. Reading Pesto.ps1 alone killed this checker with
# FileNotFoundError before a single contract ran, and body() raised KeyError on every relocated function
# (Get-PestoWindowsAuthIdentity lives in Pesto-Authentication.ps1, Invoke-PestoWindowsLocalRename in
# Pesto-Operations.ps1). The corpus is now the core plus every dot-sourced component, as in
# ux_static_checks.py; --wad points the guards at a mutated copy.
COMPONENT=re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")

def read_ps(path):return path.read_bytes().decode('utf-8-sig').replace('\r\n','\n')

def corpus(core_path,wad):
    texts={'Pesto-Core.ps1':read_ps(core_path)};missing=[]
    for name in COMPONENT.findall(texts['Pesto-Core.ps1']):
        if name in texts:continue
        component=wad/name
        if component.is_file():texts[name]=read_ps(component)
        else:missing.append(name)
    return texts,missing

def assess(texts,cmd_plain,cmd_ad,startup,base,missing_components,historical=None):
    s=texts['Pesto-Core.ps1'];results=[]
    spans={};duplicates={}
    for file_name,text in texts.items():
        for function,span in functions(text).items():
            if function in spans:duplicates.setdefault(function,[spans[function][0]]).append(file_name)
            else:spans[function]=(file_name,span)
    def check(name,ok,detail=None):
        row={'name':name,'passed':bool(ok)}
        if detail is not None:row['detail']=detail
        results.append(row)
    def body(name):
        # A missing function is a FAIL with a message, never a KeyError: a checker that dies mid-file guards
        # nothing and looks like a broken toolchain instead of a lost guard.
        if name not in spans:
            check('Function available to the guards: '+name,False,'Function absent from the corpus (core and components)')
            return ''
        file_name,(a,b)=spans[name];return texts[file_name][a:b]
    def pos(haystack,needle,label):
        # .index() on a moved anchor raised StopIteration/ValueError and killed the run. A lost anchor is now a
        # named FAIL, and every ordering guard below requires both positions to be real (0 <= a < b).
        p=haystack.find(needle)
        if p<0:check('Anchor present: '+label,False,'ancre absente du corpus: '+needle[:70])
        return p
    check('Core and its dot-sourced components are all present, each function defined once',
          not missing_components and not duplicates,
          {'missing_components':missing_components,'duplicates':duplicates})
    route=body('Get-PestoAuthenticationRoute');identity=body('Get-PestoWindowsAuthIdentity')
    auto=body('Start-PestoWindowsConnection');window=body('Show-PestoWindowsConnectionWindow')
    local=body('Invoke-PestoWindowsLocalRename');rename=body('RenameComputer');queue=body('Run-Queue')
    check('Domaine : choix Windows automatique sauf demande explicite',"if($InDomain -and -not $AskCredential){return 'Windows'}" in route)
    check('Démonstration séparée et mode explicite conservé',"if($Demo){return 'Demo'}" in route and "return 'Explicit'" in route)
    check('Identité lue du véritable jeton Windows','WindowsIdentity]::GetCurrent()' in identity and '$env:USERNAME' not in identity and 'WindowsPrincipal' in identity)
    check('Compte local/système rejeté',all(x in identity for x in ('$identity.IsAuthenticated','-not $identity.IsSystem','$authority -ine $env:COMPUTERNAME','NT AUTHORITY')))
    admin=pos(auto,'$identity.IsAdministrator','admin check before snapshot')
    dom=pos(auto,'$identity.IsDomainUser','domain check before snapshot')
    snap=pos(auto,'New-PestoDirectorySnapshotRequest','snapshot request construction')
    check('Domaine et administrateur contrôlés avant snapshot',0<=admin<snap and 0<=dom<snap)
    req=[l for l in auto.splitlines() if '$request=New-PestoDirectorySnapshotRequest' in l]
    check('Requête de snapshot unique et identifiée',len(req)==1,{'lines':len(req)})
    check('Snapshot courant sans paramètre Credential',bool(req) and '-Credential' not in req[0])
    check('Connexion asynchrone bornée à 180 s','-TimeoutSec 180' in auto and 'Start-PestoAsyncOperation' in auto)
    check('Callbacks nommés et contexte de requête vérifié',all('$Context.Id -ne $state.Id' in body(n) for n in ('Complete-PestoWindowsConnectionError','Complete-PestoWindowsConnectionSuccess')) and '.GetNewClosure' not in auto)
    check('Annulation invalide la réponse avant fermeture',"$s.Result='Cancelled';$s.Window.Close()" in window and "Stop-PestoAsyncOperation 'WindowsAuth'" in window)
    check('Erreur sans formulaire ni mutation automatique',all(x not in body('Complete-PestoWindowsConnectionError') for x in ('Show-LoginWindow','Start-Process','Run-Queue','Rename-Computer')))
    check('Le formulaire nécessite un choix explicite en mode domaine',"if($connection -eq 'Explicit'){$loginOk=Show-LoginWindow}" in s)
    snapshot=body('Set-PestoAuthenticatedSnapshot')
    check('Snapshot compare domaine et identité du worker','Snapshot.Domain' in snapshot and 'Snapshot.Identity -ine $User' in snapshot)
    success=body('Complete-PestoWindowsConnectionSuccess')
    check('Aucun credential en succès intégré','-Credential' not in success and "-Mode 'Windows'" in success)
    m=re.search(r"(?ms)\[xml\]\$wxaml=@'\n(.*?)\n'@",window)
    check('Gabarit de connexion Windows présent',m is not None)
    if m:
        try:tree=ET.fromstring(m[1])
        except Exception as e:tree=None;check('Gabarit de connexion Windows : XML bien formé',False,str(e))
        if tree is not None:
            check('Attente sans champ de mot de passe',not any(e.tag.endswith('PasswordBox') or e.tag.endswith('TextBox') for e in tree.iter()))
            check('Attente non maximisable et hauteur adaptative',tree.get('ResizeMode')=='NoResize' and tree.get('SizeToContent')=='Height')
            check('Aide sur les boutons y compris désactivés',all(e.get('ToolTip') and e.get('AutomationProperties.HelpText') and e.get('ToolTipService.ShowOnDisabled')=='True' for e in tree.iter() if e.tag.endswith('Button')))
    # Re-anchored without loss of force: the launcher Pesto.ps1 no longer exists. The optional credential now
    # crosses the elevation hop as Pesto_COMPTE_AD.cmd -> Pesto.cmd -> wad/Pesto-Startup.ps1 -> core. Each hop
    # is asserted on the file that actually carries it today, and the plain launcher is still required not to
    # force a second login.
    check('Paramètre facultatif propagé avant et après UAC',
          '[switch]$AskCredential' in startup and "if($AskCredential){$parts.Add('-AskCredential')}" in startup
          and '[switch]$AskCredential' in s and '$startupParams=@{AskCredential=$AskCredential.IsPresent}' in s
          and 'param([bool]$InDomain,[bool]$AskCredential,[bool]$Demo)' in route,
          {'startup_switch':'[switch]$AskCredential' in startup,
           'startup_forward':"if($AskCredential){$parts.Add('-AskCredential')}" in startup,
           'core_switch':'[switch]$AskCredential' in s,
           'core_forward':'$startupParams=@{AskCredential=$AskCredential.IsPresent}' in s})
    check('Lanceur normal ne force pas le second login','-AskCredential' not in cmd_plain)
    check('Lanceur autre compte est explicitement nommé','-AskCredential' in cmd_ad)
    credential=pos(queue,'Get-PestoExplicitCredentialRequirement','explicit credential requirement')
    confirm=pos(queue,'Confirm-YesNo','confirmation prompt')
    running=pos(queue,'$script:Running=$true','run started flag')
    check('File bloque tout le lot distant sans credential avant confirmation',0<=credential<confirm<running)
    leave=pos(rename,"if(-not $local){return New-ActionResult 96",'remote refusal before Entra leave')
    dsreg=pos(rename,'$leave=Invoke-PestoDsregLeaveBeforeRename','Entra leave call')
    check('Précontrôle distant avant dsregcmd dans moteur',0<=leave<dsreg)
    nocred=pos(rename,'$script:cred -isnot [Management.Automation.PSCredential]','missing-credential test')
    localpath=pos(rename,'return Invoke-PestoWindowsLocalRename','local rename call')
    argsrename=pos(rename,'$argsRename=@','native argument construction')
    check('Chemin local intégré remplace seulement absence de credential',0<=nocred<localpath<argsrename)
    check('Chemin avec credential explicite conservé','$argsRename.DomainCredential=$script:cred' in rename and 'Rename-Computer @argsRename' in rename)
    member=pos(local,'$cs.DomainRole','member role check')
    partof=pos(local,'$cs.PartOfDomain -isnot [bool]','part-of-domain check')
    leavelocal=pos(local,'$leave=Invoke-PestoDsregLeaveBeforeRename','Entra leave call')
    check('Précontrôle WMI local, rôle membre et domaine avant retrait Entra',0<=member<leavelocal and 0<=partof<leavelocal)
    check('Cible locale uniquement',"$ComputerName -ine $env:COMPUTERNAME" in local)
    call=[l for l in local.splitlines() if '$result=@(Invoke-CimMethod' in l]
    check('Appel CIM local unique',len(call)==1,{'lines':len(call)})
    calltext=call[0] if call else ''
    check('Méthode Rename sur instance, pas de méthode statique','-Query $query' in calltext and '-ClassName' not in calltext and "-MethodName 'Rename'" in calltext)
    check('Appel COM local : aucune cible distante ni session explicite',all(x not in calltext for x in ('-ComputerName','-CimSession','-InputObject','-Credential')))
    check('Arguments natifs limités au nouveau nom','-Arguments @{Name=$NewName}' in calltext and 'Password' not in calltext and 'UserName' not in calltext)
    exitcode=pos(local,'if($leave.ExitCode -ne 20){return $leave}','Entra leave gate')
    cim=pos(local,'$result=@(Invoke-CimMethod','Rename call')
    check('Retrait Entra confirmé avant unique appel Rename',0<=exitcode<cim and local.count('$result=@(Invoke-CimMethod')==1)
    check('Réponse unique typée et zéro uniquement',all(x in local for x in ('$result.Count -ne 1',"Properties['ReturnValue']",'$code -isnot [uint32]','if([uint32]$code -eq 0)')))
    check('Exception ou résultat incomplet conserve code97','Résultat incertain' in local and 'return New-ActionResult 97' in local)
    check('Pas de nouvel UAC, retry ou reboot dans helper local',all(x not in local for x in ('Start-Process','-Verb RunAs','Restart-Computer','Invoke-RenameComputerTaskFallback','Rename-Computer ')))
    exports=re.search(r'(?s)\$script:PestoWorkerCoreNames\s*=\s*@\((.*?)\)',s)
    check('Liste des fonctions exportées vers le worker présente',exports is not None)
    exportstext=exports[1] if exports else ''
    check('Helpers locaux exportés dans le worker de mutation',all("'"+n+"'" in exportstext for n in ('Get-PestoWindowsAuthIdentity','Invoke-PestoWindowsLocalRename')))
    check('Compte actif affiché sans secret','Set-Chip $ChipAccount $accountLabel' in s and "'AuthMode='+[string]$script:AuthMode" in s)
    # The live comparison runs against tests/current-core-baseline.json, a reference the repository can
    # re-derive. RC12 stays on disk untouched as the provenance record of the external package
    # (input_zip_sha256 / core_sha256) and is reported as history only: measured at HEAD, 157 of its 276 names
    # predate the GP→Pesto rename and 84 of the 119 survivors carry different code, so gating on it could only
    # ever report staleness — which is exactly what it did.
    old=base['normalized_function_sha256']
    def normalised(name):
        # Raw span, no substitution. The old .replace('17.0-RC13','VERSION') matched nothing (measured: zero
        # '17.0-RC*' strings anywhere in the corpus) and would only have masked a version literal re-appearing
        # inside a function body.
        file_name,(a,b)=spans[name]
        return hashlib.sha256(texts[file_name][a:b].encode()).hexdigest()
    obsolete=[n for n in old if n not in spans]
    changed=[n for n in old if n in spans and normalised(n)!=old[n]]
    history=None
    if historical:
        rc12=historical['normalized_function_sha256']
        gone=[n for n in rc12 if n not in spans]
        history={'historical_file':'tests/rc12-sso-baseline.json','historical_version':historical.get('version'),
                 'historical_functions':len(rc12),'names_gone_since_historical':len(gone),
                 'names_gone_examples':sorted(gone)[:8],
                 'changed_bodies_since_historical':sum(1 for n in rc12 if n in spans and normalised(n)!=rc12[n])}
    check('Fonctions existantes modifiées : uniquement celles déclarées par le socle courant',
          not obsolete and set(changed)==set(base.get('intentional_changes',[])),
          {'intentional_changes':changed,'baseline_functions':len(old),
           'baseline_commit':base.get('generated_from_commit'),
           'obsolete_baseline_names':len(obsolete),'obsolete_examples':sorted(obsolete)[:8],
           'rc12_history_informational_only':history})
    check('Aucune fonction ajoutée ou supprimée hors socle courant',
          not obsolete and set(spans)==set(old)|set(base.get('added_functions',[])),
          {'added_names':sorted(set(spans)-set(old))})
    # Re-anchored on the current baseline. The nine RC13 additions were recorded under GP names that no longer
    # exist; the contract this guard protects is "the Windows-connection SSO surface exists", so it now asserts
    # the nine Pesto counterparts are present. It still reads the GP list out of the RC12 file on purpose: if
    # that history disappears the guard goes red instead of quietly disappearing.
    renamed=[n.replace('Get-GP','Get-Pesto').replace('Set-GP','Set-Pesto').replace('Show-GP','Show-Pesto')
             .replace('Start-GP','Start-Pesto').replace('Complete-GP','Complete-Pesto').replace('Invoke-GP','Invoke-Pesto')
             for n in (historical or {}).get('rc13_added_functions',[])]
    check('Les neuf ajouts RC13 existent sous leur nom Pesto',bool(renamed) and all(n in spans for n in renamed),
          {'absentes':[n for n in renamed if n not in spans],
           'source':'tests/rc12-sso-baseline.json rc13_added_functions (noms GP), relus comme historique'})
    for n in ('Invoke-PestoDsregLeaveLocal','Invoke-PestoDsregLeaveBeforeRename','Invoke-PestoSystemTaskScript','AddToDomain','GoRenameOnly','GoRenameAndMove','MoveComputer','Get-PestoRenameMoveDecision','Restore-PestoQueueCheckpoint'):
        if n not in old:
            check('Socle courant inchangé : '+n,False,'nom absent du socle courant : comparaison impossible')
            continue
        check('Socle courant inchangé : '+n,n in spans and normalised(n)==old[n])
    return results

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--source',type=Path,help='engine core (default: <wad>/Pesto-Core.ps1)')
    ap.add_argument('--wad',type=Path,help='engine components (default: <root>/wad)')
    ap.add_argument('--report',type=Path)
    a=ap.parse_args();root=a.root
    wad=a.wad or root/'wad';core_path=a.source or wad/'Pesto-Core.ps1'
    raw=core_path.read_bytes()
    texts,missing_components=corpus(core_path,wad)
    base=json.loads((root/'tests/current-core-baseline.json').read_text())
    # RC12 is read only to report the historical delta and to keep the RC13 additions named from their source
    # record. Its own package (input_zip_sha256) is gone, so it can no longer gate anything honestly.
    historical_path=root/'tests/rc12-sso-baseline.json'
    historical=json.loads(historical_path.read_text()) if historical_path.is_file() else None
    cmd_plain=(root/'Pesto.cmd').read_text('utf-8-sig')
    cmd_ad=(root/'Pesto_COMPTE_AD.cmd').read_text('utf-8-sig')
    startup=read_ps(wad/'Pesto-Startup.ps1')
    rows=assess(texts,cmd_plain,cmd_ad,startup,base,missing_components,historical)
    # Split by file type instead of one clause for all five. Measured at HEAD: the two .cmd launchers are pure
    # ASCII without BOM (a UTF-8 BOM would corrupt cmd.exe parsing), the .ps1 files carry a BOM. The original
    # clause demanded a BOM from the .cmd files too, which no version of them ever had. Disclosed scope change,
    # not a silent weakening: each file type is now held to the convention that actually protects it, and both
    # still have to keep a single line-ending style.
    for rel in ('Pesto.cmd','Pesto_COMPTE_AD.cmd'):
        data=(root/rel).read_bytes()
        rows.append({'name':'Lanceur CMD : ASCII pur et un seul style de fin de ligne : '+rel,
                     'passed':data.isascii() and (b'\r\n' not in data or b'\n' not in data.replace(b'\r\n',b''))})
    for rel in ('wad/Pesto-Core.ps1','wad/Pesto-Startup.ps1','tests/Run-SsoTests.ps1'):
        data=(root/rel).read_bytes()
        try:
            lexical=len(tokens(data.decode('utf-8-sig')));delimiters=True;detail=''
        except Exception as e:
            lexical=0;delimiters=False;detail=str(e)
        rows.append({'name':'Délimiteurs lexicaux, BOM UTF8 et un seul style de fin de ligne : '+rel,
                     'passed':delimiters and data.startswith(b'\xef\xbb\xbf') and (b'\r\n' not in data or b'\n' not in data.replace(b'\r\n',b'')),
                     'detail':detail or {'lexical_tokens':lexical,'crlf':b'\r\n' in data}})
    # Each defect names the guard that must catch it. The stale RC12 guards below fire on any mutation
    # (a mutated body changes a baseline hash), so "some guard went red" would prove nothing: detection means
    # the designated guard fired.
    mutations=[
        ('Domaine ne prend plus le compte Windows',"if($InDomain -and -not $AskCredential){return 'Windows'}","if($InDomain -and -not $AskCredential){return 'Explicit'}",
         ('Domaine : choix Windows automatique sauf demande explicite',)),
        ('Credential réintroduit dans la requête automatique','$request=New-PestoDirectorySnapshotRequest -IncludeLocalHardware','$request=New-PestoDirectorySnapshotRequest -Credential $script:cred -IncludeLocalHardware',
         ('Snapshot courant sans paramètre Credential',)),
        ('Renommage local change en appel distant','$result=@(Invoke-CimMethod -Query $query','$result=@(Invoke-CimMethod -ComputerName $ComputerName -Query $query',
         ('Appel COM local : aucune cible distante ni session explicite',)),
        # Re-anchored: the success branch gained a Set-PestoEffect call, so the old two-term anchor no longer
        # existed anywhere and this control was silently unreachable.
        ('Faux succès WMI non nul',"if([uint32]$code -eq 0){Set-PestoEffect","if([uint32]$code -ne 0){Set-PestoEffect",
         ('Réponse unique typée et zéro uniquement',)),
        ('Comparaison identité de worker supprimée','[string]$Snapshot.Identity -ine $User','$false',
         ('Snapshot compare domaine et identité du worker',)),
    ];negative=[]
    for name,old,new,expected in mutations:
        # The defect is injected wherever the anchor actually lives in the corpus: three of these five left
        # Pesto-Core.ps1 with the split, so asserting them against the core alone made them unreachable.
        if not any(old in v for v in texts.values()):
            negative.append({'name':name,'detected':False,'expected_guards':list(expected),'failed_checks':[],
                             'error':'ancre absente du corpus : contrôle vacant, à ré-ancrer'})
            continue
        mutated={k:(v.replace(old,new) if old in v else v) for k,v in texts.items()}
        failed=[row['name'] for row in assess(mutated,cmd_plain,cmd_ad,startup,base,missing_components) if not row['passed']]
        missing=[g for g in expected if g not in failed]
        negative.append({'name':name,'detected':not missing,'expected_guards':list(expected),
                         'failed_checks':failed,'undetected_guards':missing})
    report={'version':'17.0-RC13','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'scope':'Source/XML checks only. Not a PowerShell parser; no Windows, WPF execution, AD, UAC or real mutation.',
            'core_sha256':hashlib.sha256(raw).hexdigest(),'files':sorted(texts),
            'passed':sum(x['passed'] for x in rows),'failed':sum(not x['passed'] for x in rows),
            'checks':rows,'negative_controls':negative,'windows_tests_executed':False}
    (a.report or root/'tests/sso-static-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    for row in rows:print(('PASS ' if row['passed'] else 'FAIL ')+row['name'])
    print(report['passed'],'passed /',report['failed'],'failed; negative controls',
          sum(x['detected'] for x in negative),'/',len(negative))
    return int(report['failed']>0 or any(not x['detected'] for x in negative))
if __name__=='__main__':sys.exit(main())
