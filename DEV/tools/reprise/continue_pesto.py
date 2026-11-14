"""Recover the newest Pesto source tree, retain prior work, correct support packaging,
and run existing validation. Never publish a PROD archive on failed checks.
No Windows, AD, UAC or external service is invoked by this runner.
"""
from __future__ import annotations
import os, re, sys, json, hashlib, shutil, subprocess, tempfile, time, zipfile, struct
from pathlib import Path
from datetime import datetime, timezone

BASE = Path('/mnt/data')
OUT = BASE / 'Pesto_REPRISE'
REPORT = OUT / 'bilan.json'
EXCLUDED = {'node_modules','.git','__pycache__','.pytest_cache','.venv','venv'}
NOW = datetime.now(timezone.utc).isoformat()


def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()


def rc_of(root):
    for p in (root/'wad/package.json',root/'wad/version.json',root/'wad/Pesto-Core.ps1'):
        if p.is_file():
            t=p.read_text('utf-8-sig',errors='replace')[:16000]
            m=re.search(r'17\.0[- ]?RC(\d+)',t,re.I)
            if m: return int(m.group(1))
    return 0


def candidates():
    found=[]
    for dp,dirs,files in os.walk(BASE):
        dirs[:]=[d for d in dirs if d not in EXCLUDED and not d.startswith('Pesto_REPRISE') and d!='pesto_continuation_tools']
        rel=Path(dp).relative_to(BASE)
        if len(rel.parts)>8:
            dirs[:]=[]; continue
        if 'Pesto-Core.ps1' in files and Path(dp).name.lower()=='wad':
            root=Path(dp).parent
            if (root/'Pesto.exe').is_file():
                found.append((rc_of(root),int((root/'tools').is_dir()),(root/'wad/Pesto-Core.ps1').stat().st_mtime,root))
    return sorted(found,reverse=True)


def safe_extract(z, dest):
    with zipfile.ZipFile(z) as arc:
        if sum(i.file_size for i in arc.infolist())>600*1024*1024:
            raise RuntimeError('Archive source trop volumineuse.')
        for i in arc.infolist():
            p=Path(i.filename.replace('\\','/'))
            if p.is_absolute() or '..' in p.parts or ((i.external_attr>>16)&0o170000)==0o120000:
                raise RuntimeError('Entree ZIP non sure : '+i.filename)
        arc.extractall(dest)


def run(cmd,cwd,name,timeout=100):
    start=time.monotonic()
    try:
        p=subprocess.run(cmd,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                         text=True,errors='replace',timeout=timeout)
        result={'name':name,'command':cmd,'exitCode':p.returncode,'status':'PASS' if p.returncode==0 else 'FAIL',
                'seconds':round(time.monotonic()-start,2),'output':p.stdout[-120000:]}
    except subprocess.TimeoutExpired as e:
        s=e.stdout or ''
        if isinstance(s,bytes):s=s.decode('utf-8','replace')
        result={'name':name,'command':cmd,'status':'FAIL','reason':'Timeout de validation, sans operation Windows.','output':s[-120000:]}
    except Exception as e:
        result={'name':name,'command':cmd,'status':'FAIL','reason':str(e)}
    log=OUT/'verification'/f'{name}.json';log.parent.mkdir(parents=True,exist_ok=True)
    log.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    return result


UNBLOCK=r'''@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PESTO_UNBLOCK_SELF=%~f0"
set "PESTO_UNBLOCK_DIR=%~dp0"
set "PESTO_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PESTO_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PESTO_PS%" (
  echo Windows PowerShell est introuvable.
  pause
  exit /b 2
)
"%PESTO_PS%" -NoLogo -NoProfile -Command "$s=[IO.File]::ReadAllText($env:PESTO_UNBLOCK_SELF); $m=':__PESTO_SUPPORT_POWERSHELL__'; $i=$s.LastIndexOf($m,[StringComparison]::Ordinal); if($i -lt 0){exit 2}; & ([scriptblock]::Create($s.Substring($i+$m.Length)))"
set "PESTO_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %PESTO_EXIT%
:__PESTO_SUPPORT_POWERSHELL__
$ErrorActionPreference='Stop'
$failed=0; $unblocked=0; $already=0; $skipped=0
$entries=New-Object 'System.Collections.Generic.List[string]'
try {
    $support=Get-Item -LiteralPath $env:PESTO_UNBLOCK_DIR -Force
    if(-not $support.PSIsContainer -or $support.Name -ine 'support' -or $support.Parent.Name -ine 'wad') {
        throw 'Ce fichier doit rester dans wad\support.'
    }
    $root=$support.Parent.Parent
    if($null -eq $root -or $null -eq $root.Parent -or $root.FullName -eq [IO.Path]::GetPathRoot($root.FullName)) {
        throw 'Racine de deblocage refusee.'
    }
    # Do not traverse junctions, links or a redirected ancestor.
    $ancestor=$support
    while($null -ne $ancestor) {
        if(($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Chemin redirige refuse : '+$ancestor.FullName)
        }
        $ancestor=$ancestor.Parent
    }
    foreach($relative in @('Pesto.exe','wad\Pesto-Startup.ps1','wad\Pesto-Core.ps1')) {
        $target=Get-Item -LiteralPath ([IO.Path]::Combine($root.FullName,$relative)) -Force
        if($target.PSIsContainer -or (($target.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw ('Composant invalide : '+$relative)
        }
    }
    Write-Host 'Pesto - Debloquer les fichiers de cette installation'
    Write-Host ('Dossier : '+$root.FullName)
    Write-Host 'Retire uniquement les marques de telechargement des fichiers.'
    Write-Host 'Ne modifie ni antivirus, ni strategies Windows, ni droits, ni verrous Pesto.'
    if((Read-Host 'Confirmer la provenance de ces fichiers et continuer ? O/N') -ine 'O') { exit 0 }
    $pending=New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pending.Push($root)
    while($pending.Count -gt 0) {
        $dir=$pending.Pop()
        try { $items=@(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop) }
        catch { $failed++; $entries.Add('ERREUR ENUMERATION '+$dir.FullName+' : '+$_.Exception.Message); continue }
        foreach($item in $items) {
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $skipped++; $entries.Add('LIEN IGNORE '+$item.FullName); continue
            }
            if($item.PSIsContainer) { $pending.Push($item); continue }
            try {
                $streams=@(Get-Item -LiteralPath $item.FullName -Stream '*' -ErrorAction Stop)
                if(@($streams | Where-Object {$_.Stream -eq 'Zone.Identifier'}).Count -eq 0) {$already++;continue}
                Unblock-File -LiteralPath $item.FullName -ErrorAction Stop
                $after=@(Get-Item -LiteralPath $item.FullName -Stream '*' -ErrorAction Stop)
                if(@($after | Where-Object {$_.Stream -eq 'Zone.Identifier'}).Count -gt 0) {throw 'La marque est toujours presente.'}
                $unblocked++; $entries.Add('DEBLOQUE '+$item.FullName)
            } catch {$failed++; $entries.Add('ERREUR '+$item.FullName+' : '+$_.Exception.Message)}
        }
    }
    $summary='Debloques={0}; deja sans marque={1}; liens ignores={2}; erreurs={3}' -f $unblocked,$already,$skipped,$failed
    Write-Host $summary
    $entries.Insert(0,([DateTime]::UtcNow.ToString('o')+' '+$summary))
    try {
        $logdir=[IO.Path]::Combine($root.FullName,'wad\logs')
        if(Test-Path -LiteralPath $logdir) {
            $ld=Get-Item -LiteralPath $logdir -Force
            if(-not $ld.PSIsContainer -or (($ld.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {throw 'Dossier de journal non sur.'}
        } else {[void][IO.Directory]::CreateDirectory($logdir)}
        $log=[IO.Path]::Combine($logdir,('DEBLOCAGE_Pesto_'+[DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss')+'_'+[Guid]::NewGuid().ToString('N')+'.log'))
        $stream=New-Object IO.FileStream($log,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            $bytes=(New-Object Text.UTF8Encoding($true)).GetBytes(($entries -join [Environment]::NewLine))
            $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true)
        } finally {$stream.Dispose()}
        Write-Host ('Journal : '+$log)
    } catch {$failed++;Write-Warning ('Le bilan ne peut pas etre enregistre : '+$_.Exception.Message)}
    if($failed -gt 0) {exit 1}
    exit 0
} catch {Write-Host ('Deblocage non termine : '+$_.Exception.Message) -ForegroundColor Red;exit 2}
'''


def manifest_entries(node):
    entries=[]
    if isinstance(node,dict):
        low={k.lower():v for k,v in node.items()}
        path=next((low[k] for k in ('path','relativepath','file','filename') if isinstance(low.get(k),str)),None)
        digest=next((low[k] for k in ('sha256','sha256hash','hash','checksum') if isinstance(low.get(k),str) and re.fullmatch('[0-9a-fA-F]{64}',low[k])),None)
        if path and digest:entries.append((path,digest))
        for k,v in node.items():
            if isinstance(v,str) and re.fullmatch('[0-9a-fA-F]{64}',v) and '.' in k: entries.append((k,v))
            elif isinstance(v,dict):
                vl={x.lower():y for x,y in v.items()}
                d=next((vl[x] for x in ('sha256','hash','checksum') if isinstance(vl.get(x),str) and re.fullmatch('[0-9a-fA-F]{64}',vl[x])),None)
                if d and (k.startswith('wad/') or k.startswith('wad\\') or k.endswith('.exe')):entries.append((k,d))
            entries.extend(manifest_entries(v))
    elif isinstance(node,list):
        for x in node:entries.extend(manifest_entries(x))
    return sorted(set(entries))


def verify(root):
    results=[]
    mp=root/'wad/package.json'
    try:
        data=json.loads(mp.read_text('utf-8-sig'));entries=manifest_entries(data)
        if len(entries)<20:raise ValueError('Schema du manifeste non reconnu ou moins de 20 composants controles.')
        for rel,digest in entries:
            p=Path(rel.replace('\\','/'))
            if p.is_absolute() or '..' in p.parts:raise ValueError('Chemin de manifeste non sur.')
            actual=root/p
            if not actual.is_file():
                alt=root/'wad'/p
                if alt.is_file():actual=alt
            if not actual.is_file() or sha(actual).lower()!=digest.lower():
                raise ValueError('Empreinte absente ou differente : '+rel)
        results.append({'name':'manifest','status':'PASS','components':len(entries)})
    except Exception as e:
        results.append({'name':'manifest','status':'FAIL','reason':str(e)});entries=[]
    try:
        b=(root/'Pesto.exe').read_bytes();pe=struct.unpack_from('<I',b,0x3c)[0]
        assert b[:2]==b'MZ' and b[pe:pe+4]==b'PE\0\0'
        assert struct.unpack_from('<H',b,pe+4)[0]==0x8664
        results.append({'name':'PE-x64','status':'PASS','sha256':sha(root/'Pesto.exe')})
    except Exception as e:results.append({'name':'PE-x64','status':'FAIL','reason':str(e)})
    try:
        import xml.etree.ElementTree as ET
        xs=list((root/'wad').glob('*.xaml'))
        for x in xs:ET.parse(x)
        assert xs
        results.append({'name':'XML','status':'PASS','count':len(xs),'scope':'XML seulement, pas rendu WPF'})
    except Exception as e:results.append({'name':'XML','status':'FAIL','reason':str(e)})
    return results,entries


def make_zip(folder,out):
    with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(folder.rglob('*')):
            if p.is_file() and not p.is_symlink(): z.write(p,p.relative_to(folder.parent).as_posix())
    with zipfile.ZipFile(out) as z:
        bad=z.testzip()
        if bad:raise RuntimeError('ZIP invalide : '+bad)
    return {'path':str(out),'sha256':sha(out),'bytes':out.stat().st_size}


def main():
    OUT.mkdir(exist_ok=True)
    cs=candidates()
    if not cs or max(c[0] for c in cs)<19:
        archive=BASE/'Pesto_17_RC18_DEV.zip'
        fallback=OUT/'original_archive'
        if not archive.is_file():raise FileNotFoundError('Archive RC18 absente et aucun arbre source exploitable.')
        if not (fallback/'DEV/wad/Pesto-Core.ps1').is_file():safe_extract(archive,fallback)
        if not cs:cs=[(18,1,time.time(),fallback/'DEV')]
    chosen=cs[0][3]
    if (chosen/'tools').is_dir() is False:
        devs=[x for x in cs if x[0]==cs[0][0] and x[1]]
        if devs:chosen=devs[0][3]
    target=OUT/'DEV'
    if target.exists():
        backup=OUT/('previous_DEV_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
        target.rename(backup)
    shutil.copytree(chosen,target,ignore=shutil.ignore_patterns('__pycache__','.git','.pytest_cache','*.pyc'))
    initial,entries=verify(target)
    report={'createdUtc':NOW,'source':str(chosen),'sourceVersionRC':rc_of(chosen),
            'candidates':[{'rc':a,'developerTree':bool(b),'path':str(d)} for a,b,c,d in cs],
            'baselineChecks':initial,'changes':[],'validation':[],
            'windowsValidation':{'PowerShell51':'NOT_RUN','WPF':'NOT_RUN','UAC':'NOT_RUN','AD':'NOT_RUN','WindowsExecutable':'NOT_RUN'},
            'all44AuditItemsCompleted':False,
            'scope':'Reprise et conservation du travail existant; support et validation. Ne certifie pas la completion des 44 taches.'}
    (target/'wad/support').mkdir(parents=True,exist_ok=True)
    u=target/'wad/support/DEBLOQUER_TOUT.cmd'
    u.write_bytes(UNBLOCK.replace('\n','\r\n').encode('utf-8'))
    old=target/'DEBLOQUER_TOUT.cmd'
    if old.exists():
        (target/'docs/historique-support').mkdir(parents=True,exist_ok=True)
        shutil.copy2(old,target/'docs/historique-support/DEBLOQUER_TOUT_RACINE.cmd.txt');old.unlink()
    report['changes'].append({'id':'PE-33','status':'CODED_WINDOWS_NOT_RUN',
        'detail':'Deblocage dans wad/support; racine deux niveaux au-dessus; controle des composants; confirmation; liens ignores; verification ADS; bilan avec fichier unique.'})
    # Keep originals and incomplete earlier implementation. Never rewrite the engine blindly.
    if (target/'tools/launcher/build_native.py').is_file():
        report['validation'].append(run([sys.executable,'tools/launcher/build_native.py'],target,'native-build',180))
    if (target/'tests').is_dir():
        report['validation'].append(run([sys.executable,'-m','unittest','discover','-s','tests','-p','test*.py','-v'],target,'python-tests',180))
    else:
        report['validation'].append({'name':'python-tests','status':'NOT_RUN','reason':'Dossier tests absent de la source reprise.'})
    # Native PowerShell Core parser, where available, is not called Windows PowerShell 5.1.
    pwsh=shutil.which('pwsh')
    if pwsh:
        parser=OUT/'parse_sources.ps1'
        parser.write_text("param([string]$Root)\n$bad=0;Get-ChildItem -LiteralPath (Join-Path $Root 'wad') -File -Recurse | Where-Object {$_.Extension -in '.ps1','.psm1'} | ForEach-Object { $t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$t,[ref]$e);if($e){$bad++;$e | Format-List | Out-String | Write-Output}};if($bad){exit 1};Write-Output 'Parser PowerShell Core: aucune erreur syntaxique';exit 0\n",encoding='utf-8-sig')
        report['validation'].append(run([pwsh,'-NoProfile','-File',str(parser),str(target)],target,'powershell-core-parser',120))
    else:report['validation'].append({'name':'powershell-core-parser','status':'NOT_RUN','reason':'pwsh absent.'})
    final,entries=verify(target);report['finalChecks']=final
    # Delivery note explicitly reports any failure. Existing completion claims are not reused.
    note='''# Pesto : reprise du travail\n\nCe dossier conserve la source la plus recente trouvee, sans assimiler les anciens rapports a une validation courante.\n\nLe deblocage est dans `wad\\support\\DEBLOQUER_TOUT.cmd`. Il vise la racine Pesto deux niveaux au-dessus. Aucun fichier de support n'est une dependance obligatoire du moteur.\n\nLes resultats reels de cette reprise figurent dans `bilan-reprise.json` et `verification/`. Tout FAIL ou NOT_RUN reste visible. Le rendu WPF, Windows PowerShell 5.1, l'UAC et les operations AD ne sont pas valides ici.\n\nLes 44 taches de l'audit ne sont pas declarees toutes terminees par cette reprise. Le certificat de signature de l'organisation et une recette Windows interactive restent necessaires. Ne pas utiliser un pack avec des controles en echec sur le domaine de production.\n\nPreserver cfg.json, preferences et etats existants. Ne pas effacer de verrou pour relancer une mutation incertaine.\n'''
    (target/'docs').mkdir(exist_ok=True)
    (target/'docs/REPRISE_ET_LIMITES.md').write_text(note,encoding='utf-8')
    report['productionPackCreated']=False
    failures=[r for r in report['validation']+final if r.get('status')=='FAIL']
    # Native validation of the safety changes is still pending. Never claim a completed release.
    if not failures and entries:
        prod=OUT/'PROD'
        if prod.exists():shutil.rmtree(prod)
        prod.mkdir()
        for rel,_ in entries:
            p=Path(rel.replace('\\','/'));src=target/p
            if not src.is_file():src=target/'wad'/p
            dest=prod/src.relative_to(target);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
        for rel in ('Pesto.exe','wad/package.json','wad/cfg.json','wad/support/DEBLOQUER_TOUT.cmd'):
            src=target/rel
            if src.is_file():
                dst=prod/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
        report['prodChecks'],_=verify(prod)
        if all(r['status']=='PASS' for r in report['prodChecks']):
            report['productionPack']=make_zip(prod,BASE/'Pesto_REPRISE_PROD.zip')
            report['productionPackCreated']=True
    report['releaseStatus']='RECETTE_WINDOWS_REQUISE' if not failures else 'DEVELOPPEMENT_CONTROLES_EN_ECHEC'
    report['runtimeFilesChangedByThisRunner']=False
    # Record the full retained source changes separately from this runner's edits.
    refzip=BASE/'Pesto_17_RC18_DEV.zip'
    diffs=[]
    if refzip.is_file():
        with zipfile.ZipFile(refzip) as z:
            zn=set(z.namelist())
            for p in sorted((target/'wad').glob('Pesto-*')):
                if not p.is_file():continue
                rel=p.relative_to(target).as_posix();oldname='DEV/'+rel
                olddigest=hashlib.sha256(z.read(oldname)).hexdigest() if oldname in zn else None
                current=sha(p)
                if olddigest!=current:diffs.append({'path':rel,'rc18sha256':olddigest,'currentSha256':current})
    report['retainedRuntimeDiffFromRC18']=diffs
    (target/'docs/bilan-reprise.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    shutil.copytree(OUT/'verification',target/'verification',dirs_exist_ok=True) if (OUT/'verification').exists() else None
    report['developerPack']=make_zip(target,BASE/'Pesto_REPRISE_DEV.zip')
    REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (BASE/'Pesto_REPRISE_BILAN.json').write_text(REPORT.read_text('utf-8'),encoding='utf-8')
    return report

if __name__=='__main__':
    try:
        r=main()
        print(json.dumps({'status':r['releaseStatus'],'source':r['source'],'sourceRC':r['sourceVersionRC'],
                          'changedRuntimeFilesComparedWithRC18':len(r['retainedRuntimeDiffFromRC18']),
                          'prodCreated':r['productionPackCreated'],'report':str(REPORT),
                          'tests':[{k:v for k,v in x.items() if k in ('name','status','reason','exitCode')} for x in r['validation']]},ensure_ascii=False,indent=2))
    except Exception as e:
        OUT.mkdir(exist_ok=True)
        (OUT/'REPRISE_ERREUR.txt').write_text(type(e).__name__+': '+str(e),encoding='utf-8')
        raise
