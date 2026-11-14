#!/usr/bin/env python3
"""RC9 source contracts, not PowerShell execution or proof that UAC/AD works."""
from pathlib import Path
import argparse, datetime, hashlib, json, re
from ps_lexical import functions,tokens
NEW={'Assert-PestoWorkerMayContinue','Get-PestoQueueActivityText','New-PestoQueueMonitor','Publish-PestoWorkerLog','Receive-PestoQueueEvents','Set-PestoQueueCancellationFence','Set-PestoWorkerStage','Test-PestoQueueWorkerStillActive'}
# The engine spread its functions over the components the core dot-sources. Indexing Pesto-Core.ps1 alone
# made this checker die on KeyError at the first relocated term (New-PestoQueueMonitor lives in
# Pesto-Async.ps1, the native workers in Pesto-Operations.ps1), so it guarded nothing any more. The corpus is
# the core plus every dot-sourced component, as in ux_static_checks.py; --wad points it at a mutated copy.
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
def contracts(texts,missing_components):
    s=texts['Pesto-Core.ps1']; s_all='\n'.join(texts.values()); out=[]
    spans={};duplicates={}
    for file_name,text in texts.items():
        for function,span in functions(text).items():
            if function in spans:duplicates.setdefault(function,[spans[function][0]]).append(file_name)
            else:spans[function]=(file_name,span)
    def b(n):
        # A missing function is a FAIL with a message, never a KeyError: a checker that dies mid-file guards
        # nothing and looks like a broken toolchain instead of a lost guard.
        if n not in spans:
            out.append({'name':'Function available to the guards: '+n,'status':'FAIL','detail':'Function absent from the corpus (core and components)'});return ''
        file_name,(a,z)=spans[n];return texts[file_name][a:z]
    def ck(name,value):out.append({'name':name,'status':'PASS' if bool(value) else 'FAIL'})
    ck('Core and its dot-sourced components are all present, each function defined once',not missing_components and not duplicates)
    ck('RC9 monitor functions all exist',NEW<=set(spans))
    ck('Shared monitor uses a synchronized table and concurrent event queue',all(x in b('New-PestoQueueMonitor') for x in ('[hashtable]::Synchronized','ConcurrentQueue[object]','MutationStarted=$false','CancelRequested=$false')))
    ck('Worker messages are sanitized before enqueue',0<=b('Publish-PestoWorkerLog').find('Protect-PestoLogText')<b('Publish-PestoWorkerLog').find('.Enqueue('))
    ck('Stage snapshot is assigned atomically, not a partially edited live object','Stage=[pscustomobject]' in b('Set-PestoWorkerStage'))
    ck('Cancellation and admission share the same monitor lock',all('[Threading.Monitor]::Enter' in b(n) and 'finally' in b(n) and '[Threading.Monitor]::Exit' in b(n) for n in ('Assert-PestoWorkerMayContinue','Set-PestoQueueCancellationFence')))
    ck('Cancellation tested before mutation admission',b('Assert-PestoWorkerMayContinue').find('if($m.CancelRequested)')<b('Assert-PestoWorkerMayContinue').find('if($Mutation)'))
    ck('UI event drain is bounded and uses TryDequeue',all(x in b('Receive-PestoQueueEvents') for x in ('$Maximum=200','$read -lt $Maximum','TryDequeue','Add-LogLine')))
    start=b('Start-PestoNextQueueTask');asyncstart=b('Start-PestoAsyncOperation');tick=b('Invoke-PestoAsyncTimerTick');stop=b('Stop-PestoAsyncOperation')
    ck('Queue worker STA, same telemetry object and 300 second watchdog',all(x in start for x in ('-ApartmentState STA -QueueMonitor $monitor -TimeoutSec 300','Telemetry=$monitor','$script:QueueCurrentTicket.Monitor=$monitor')))
    ck('Read workers remain MTA unless explicitly changed',"$ApartmentState = 'MTA'" in asyncstart and '[System.Threading.ApartmentState]$ApartmentState' in asyncstart)
    # The non-replaceable set was widened from QueueAction alone to every mutating worker, the same widening
    # as the cooperative stop branch below: no mutating worker can be replaced by a second start.
    ck('Active mutating worker cannot be replaced',"if (-not $Replace -or $Name -in @('QueueAction','DomainJoin','DirectAction','RecoveryAction')) { return $false }" in asyncstart)
    ck('Live events are drained before waiting for completion',tick.find('Receive-PestoQueueEvents')<tick.find('if(-not $op.Async.IsCompleted)'))
    ck('Final events are drained before success callback',tick.find('if($op.QueueMonitor){Receive-PestoQueueEvents',tick.find('EndInvoke'))<tick.find('-Callback $op.OnSuccess'))
    ck('Mutating timeout keeps worker registry until actual completion',"if($op.Name -notin @('QueueAction','DomainJoin','DirectAction','RecoveryAction') -and $script:PestoAsyncOperations.ContainsKey" in tick)
    # Every BeginStop call site in the timer must sit behind the mutating-worker exclusion. The old form only
    # matched a BeginStop written on the same line as its if, and missed the guarded call written on the next
    # line; both shapes are checked now.
    tl=tick.split('\n');mutating="$op.Name -notin @('QueueAction','DomainJoin','DirectAction','RecoveryAction')"
    sites=[(i,l) for i,l in enumerate(tl) if '.BeginStop(' in l and 'Methods[' not in l]
    ck('Mutating timeout never directly invokes BeginStop',all(mutating in tl[i] or (i>0 and mutating in tl[i-1]) for i,l in sites))
    # The cooperative stop branch was widened from QueueAction alone to every mutating worker (DomainJoin,
    # DirectAction, RecoveryAction) after this guard was written. It is now required to cover all four names:
    # dropping one back onto the BeginStop path needs a deliberate re-anchor.
    stopmarker="if($Name -in @('QueueAction','DomainJoin','DirectAction','RecoveryAction')){"
    ck('Cooperative stop branch covers every mutating worker',stopmarker in stop)
    i1=stop.find(stopmarker);i2=stop.find('try { $op.Cancelled')
    ck('Cooperative stop branch delimited before the non-cooperative path',i1>=0 and i2>i1)
    branch=stop[i1:i2] if i1>=0 and i2>i1 else ''
    ck('Explicit queue stop fences, suppresses callbacks and keeps monitoring',bool(branch) and all(x in branch for x in ('$op.Cancelled=$true','Set-PestoQueueCancellationFence','return')) and 'BeginStop' not in branch and '.Remove(' not in branch)
    ck('Timeout is labeled uncertain, not a confirmed failure',all(x in b('Complete-PestoQueueItem') for x in ('[TimeoutException]','$code=97','Ne relancez pas')))
    ck('Uncertain summary does not announce Windows completion',all(x in b('Complete-PestoQueueRun') for x in ('File arrêtée pour vérification','à vérifier','Test-PestoQueueWorkerStillActive')))
    ck('Late result cannot overwrite the timeout',tick.find('if($op.Cancelled -or $op.TimeoutReported -or $op.TimerFaultReported)')<tick.find('-Callback $op.OnSuccess') and 'Le verrou reste actif' in tick)
    ck('Safety reset blocked while timed-out worker remains live','if(Test-PestoQueueWorkerStillActive)' in b('Reset-PestoSafetyLock'))
    pulse=b('Invoke-PestoPilotagePulse');ck('15 second audit heartbeat contains current stage',all(x in pulse for x in ('Get-PestoQueueActivityText','TotalSeconds -ge 15','Write-AuditLine','résultat non reçu')))
    helper=b('Invoke-PestoElevatedLocalChange')
    ck('UAC uses STA and announces before shell launch',"ApartmentState -ne 'STA'" in helper and "'-STA'" in helper and helper.find("Set-PestoWorkerStage 'Autorisation Windows attendue'")<helper.find('Start-Process'))
    ck('Helper visible, exits detected before credentials, 120 second connection guard',all(x in helper for x in ('-WindowStyle Normal','$proc.HasExited','AddSeconds(120)','WaitOne(200)')))
    ck('Verified PID before credential send',0<=helper.find('Test-PestoPipeClient -Pipe $pipe -ExpectedProcessId $proc.Id')<helper.find('$credentialSent=$true;$writer.WriteLine') and 'GetNamedPipeClientProcessId' in b('Test-PestoPipeClient') and '$actual -ne [uint32]$ExpectedProcessId' in b('Test-PestoPipeClient'))
    ck('Response waiting is polled and never kills the helper',all(x in helper for x in ('Wait(250)','AddSeconds(300)','CancelRequested','New-ActionResult 97')) and '.Kill(' not in helper)
    ck('Credential transmission follows mutation admission',helper.find('Assert-PestoWorkerMayContinue -Mutation')<helper.find('$credentialSent=$true;$writer.WriteLine'))
    for name,needle in [('RenameComputer','@(Rename-Computer @argsRename)'),('AddToDomain','@(Add-Computer @ac)'),('MoveComputer','$moveStarted=$true')]:
        code=b(name);ck(name+' gates admission before native write',0<=code.find('Assert-PestoWorkerMayContinue -Mutation')<code.find(needle))
    ck('Move finally always attempts original protection restoration',"finally" in b('MoveComputer') and 'ProtectedFromAccidentalDeletion' in b('MoveComputer').split('finally',1)[1] and 'Assert-PestoWorkerMayContinue' not in b('MoveComputer').split('finally',1)[1])
    ck('Rename completion gated before following AD move',b('GoRenameAndMove').find('Assert-PestoWorkerMayContinue')<b('GoRenameAndMove').find('$moveName ='))
    ck('Local source avoids a network ping',"$Nom_du_PC -ine $env:COMPUTERNAME" in b('Go'))
    i1=s.find('$script:PestoQueueWorker =');i2=s.find('function Set-PestoQueueUiLocked')
    ck('Worker region delimited in the core',i1>=0 and i2>i1)
    w=s[i1:i2] if i1>=0 and i2>i1 else ''
    # The worker no longer calls Import-Module itself, it calls Import-PestoADModule. The ordering this guard
    # protects is unchanged: the log sink must exist before the AD module is loaded.
    ck('Worker log sink available before the AD module is imported',0<=w.find('function Write-Log')<w.find('Import-PestoADModule') and "Set-PestoWorkerStage 'Chargement" in w)
    ck('Worker uses only shared data, no WPF dispatcher access',w and not any(x in w for x in ('$Win.','$Grid.','.Dispatcher.Invoke(','.GetNewClosure(')))
    j1=s.find('$script:PestoWorkerCoreNames =');j2=s.find('$script:PestoWorkerCoreSourceCache =')
    ck('Exported worker source region delimited in the core',j1>=0 and j2>j1)
    ck('Required telemetry functions included in exported source',j1>=0 and j2>j1 and all("'"+n+"'" in s[j1:j2] for n in ('Publish-PestoWorkerLog','Set-PestoWorkerStage','Assert-PestoWorkerMayContinue')))
    return out

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);ap.add_argument('--source',type=Path,help='engine core (default: <wad>/Pesto-Core.ps1)');ap.add_argument('--wad',type=Path,help='engine components (default: <root>/wad)');ap.add_argument('--report',type=Path);a=ap.parse_args();r=a.root
    wad=a.wad or r/'wad';core_path=a.source or wad/'Pesto-Core.ps1'
    raw=core_path.read_bytes();texts,missing=corpus(core_path,wad);s=texts['Pesto-Core.ps1'];results=contracts(texts,missing)
    def ck(n,v,**kw):results.append({'name':n,'status':'PASS' if v else 'FAIL',**kw})
    for path in ('tests/Run-ProgressTests.ps1','tools/Diagnostic-Rename.ps1','tools/Build-Pesto.ps1'):
        data=(r/path).read_bytes();txt=data.decode('utf-8-sig').replace('\r\n','\n');tok=tokens(txt)
        ck(path+' UTF-8 BOM and conservative delimiter checks',data.startswith(b'\xef\xbb\xbf'),tokens=len(tok),native_parser_executed=False)
        # Disclosed scope change, not a silent weakening: this clause demanded CRLF. Measured at HEAD the tree
        # is mixed (tools 1 of 8 CRLF, wad 6 of 27, tests 15 of 23), so demanding CRLF guarded a convention the
        # repository no longer follows and reported two healthy files as broken. What is actually protected is
        # that a single file never mixes both endings; the measured style stays in the report.
        ck(path+' keeps one line-ending style',b'\r\n' not in data or b'\n' not in data.replace(b'\r\n',b''),crlf=b'\r\n' in data)
    native=(r/'tests/Run-ProgressTests.ps1').read_text(encoding='utf-8-sig');cases=len(re.findall(r"^Case '",native,re.M))
    ck('Windows tests exercise real timers but never start Pesto',cases==21 and 'Parser]::ParseFile' in native and '. ([scriptblock]::Create($defs[$name]))' in native and 'ADModulePath' not in native,windows_cases_supplied=cases,executed=False)
    # Build-Pesto.ps1 runs no native suite any more (the same split RC4 and pilotage record): the suites are
    # invoked by tests/Run-AllTests.ps1, which honours every child exit code. The guarantee is guarded where it
    # lives now, and it is no longer claimed as a property of the build.
    alltests=(r/'tests/Run-AllTests.ps1').read_text(encoding='utf-8-sig')
    ck('Master runner includes the new suite and a failing suite stops the run','Run-ProgressTests.ps1' in alltests
       and 'if($LASTEXITCODE -ne 0){$failures.Add($suite)}' in alltests and "throw ('Suites en échec : '" in alltests)
    build=(r/'tools/Build-Pesto.ps1').read_text(encoding='utf-8-sig')
    ck('Build aborts on every failing native step',build.count('if($LASTEXITCODE -ne 0){throw')>=5 and "throw 'EXE et composants non concordants.'" in build)
    ck('Diagnostic collects no process arguments or mutations',all(x not in (r/'tools/Diagnostic-Rename.ps1').read_text(encoding='utf-8-sig') for x in ('Rename-Computer','Add-Computer','Move-ADObject','Stop-Process','Restart-Computer','CommandLine','-EncodedCommand')))
    ck('Diagnostic explicitly avoids claiming no operation still active','NE prouve PAS' in (r/'tools/Diagnostic-Rename.ps1').read_text(encoding='utf-8-sig'))
    negatives=[]
    for name,old,new in [
        ('Remove queue STA','-ApartmentState STA -QueueMonitor $monitor -TimeoutSec 300','-ApartmentState MTA -QueueMonitor $monitor -TimeoutSec 300'),
        ('Drop queue deadline','-QueueMonitor $monitor -TimeoutSec 300','-QueueMonitor $monitor -TimeoutSec 0'),
        ('Permit replacement',"-not $Replace -or $Name -in @('QueueAction','DomainJoin','DirectAction','RecoveryAction')",'-not $Replace'),
        ('No callback suppression on stop',"if($Name -in @('QueueAction','DomainJoin','DirectAction','RecoveryAction')){\n        $op.Cancelled=$true", "if($Name -in @('QueueAction','DomainJoin','DirectAction','RecoveryAction')){\n        # cancellation omitted"),
        ('Lose log masking','Text=(Protect-PestoLogText $Text)','Text=$Text'),
        ('Drop native rename fence',"Assert-PestoWorkerMayContinue -Mutation\n        Set-PestoWorkerStage 'Renommage Windows en cours'","# no fence\n        Set-PestoWorkerStage 'Renommage Windows en cours'"),
    ]:
        # The defect is injected wherever the term actually lives in the corpus: asserting it against the core
        # alone made three of these six controls unreachable once the workers moved out of Pesto-Core.ps1. An
        # anchor that no longer exists is recorded as undetected, which still fails the run but keeps the
        # report on disk: a vacant control must be readable, not only loud.
        if not any(old in v for v in texts.values()):
            negatives.append({'name':name,'detected':False,'failed_checks':[],
                              'error':'ancre absente du corpus : contrôle vacant, à ré-ancrer'})
            continue
        mutated={k:(v.replace(old,new) if old in v else v) for k,v in texts.items()}
        faults=[x['name'] for x in contracts(mutated,missing) if x['status']=='FAIL'];negatives.append({'name':name,'detected':bool(faults),'failed_checks':faults})
    failed=sum(x['status']=='FAIL' for x in results)
    report={'version':'17.0-RC9','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_sha256':hashlib.sha256(raw).hexdigest(),'files':sorted(texts),'scope':'STATIC ONLY: textual contracts and lexical checks, not native PowerShell, WPF, UAC or AD execution.','summary':{'checks':len(results),'passed':len(results)-failed,'failed':failed},'checks':results,'negative_controls':negatives,'native_windows_tests_executed':False}
    (a.report or r/'tests/progress-static-report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    for x in results:print(x['status'],x['name'])
    print(report['summary']);print('Injected defects detected:',sum(x['detected'] for x in negatives),'/',len(negatives));return int(failed>0 or not all(x['detected'] for x in negatives))
if __name__=='__main__':raise SystemExit(main())
