#!/usr/bin/env python3
"""Preview-first local code update. No credential, registry, AD or reboot change.

Run from the NEW extracted DEV tree, never from the destination installation.
A rollback restores files only: it is NOT a rollback of Windows/AD operations.
"""
from __future__ import annotations
import argparse, contextlib, ctypes, hashlib, json, os, re, shutil, stat, sys, tempfile, uuid
from pathlib import Path
from refresh_manifest import VERSION, FILE_VERSION, runtime_files, safe_file, verify_runtime, validate_relative, validate_runtime_relative, file_hash, _is_link_or_junction
from installation_receipt import RECEIPT, PROD_HELPERS, require_intact_receipt, make_receipt


# Resource limits, separate from the exact path/hash checks. A recovery journal
# may contain both runtimes, the package manifest and, only when already
# managed, the ownership receipt and the closed set of preserved helpers.
MAX_RUNTIME_COMPONENTS = 128
MAX_RECOVERY_COMPONENTS = 2 * MAX_RUNTIME_COMPONENTS + 2 + len(PROD_HELPERS)


def _validate_recovery_relative(relative: str) -> None:
    if relative == 'wad/package.json':
        return
    validate_runtime_relative(relative)
    if (relative == 'Pesto.exe' or relative.startswith('wad/Pesto-') or relative in {
        'wad/ActiveDirectory.Format.ps1xml','wad/ActiveDirectory.Types.ps1xml','wad/ActiveDirectory.psd1',
        'wad/ActiveDirectoryPowerShellResources.dll','wad/Microsoft.ActiveDirectory.Management.dll',
        'wad/M4D.Admin.Common.Core.dll','wad/M4D.Admin.Common.Query.dll',
        'wad/M4D.Admin.Common.IO.dll','wad/M4D.Admin.Common.Diagnostics.dll','wad/M4D.Admin.Common.Wpf.dll',
        'wad/common.lock.json','wad/Invoke-PestoAutoJoin.ps1','wad/Invoke-Pesto.ps1',
        'wad/Invoke-PestoExtension.ps1','wad/Pesto.Runtime.dll',
        'wad/Pesto.Engine.Runtime.ps1','wad/Pesto.Engine.psm1','wad/Pesto.Engine.psd1','wad/Pesto.Engine.build.json',
        'wad/fr-FR/ActiveDirectoryPowerShellResources.dll.mui','wad/Pesto.ico'
    }):
        return
    raise ValueError('Recovery path not allowed: '+relative)


def old_components(root: Path) -> tuple[str, ...]:
    path=safe_file(root,'wad/package.json')
    if path.stat().st_size > 262144: raise ValueError('Oversized installed manifest')
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    if not isinstance(data,dict): raise ValueError('Invalid installed manifest: expected an object')
    version=data.get('Version','')
    if data.get('Schema') != 2 or data.get('Scope') != 'Runtime' or not isinstance(version,str) or not re.fullmatch(r'17\.0-RC(?:18|19|20|21|22|23)|1\.\d+',version):
        raise ValueError('Only an intact Pesto 17.0-RC18..RC23 or 1.x installation is supported; no GP migration or state conversion')
    entries=data.get('Files'); paths=[]
    if not isinstance(entries,list) or not 20<=len(entries)<=MAX_RUNTIME_COMPONENTS: raise ValueError('Invalid installed manifest file count')
    for entry in entries:
        if not isinstance(entry,dict): raise ValueError('Invalid installed manifest entry: expected an object')
        name=entry.get('Path'); validate_runtime_relative(name)
        if name.casefold() in {p.casefold() for p in paths}:raise ValueError('Duplicate installed component')
        digest=entry.get('SHA256','')
        if not isinstance(digest,str) or not re.fullmatch(r'[a-fA-F0-9]{64}',digest) or file_hash(safe_file(root,name)).lower()!=digest.lower():
            raise ValueError('Installed code is incomplete or modified: '+name)
        paths.append(name)
    if 'Pesto.exe' not in paths:raise ValueError('Installed launcher absent')
    return tuple(paths)


def _version_label(version: str, file_version: str|None) -> str:
    return f'{version} ({file_version})' if file_version else version


def _parse_version(version: str, file_version: str|None=None) -> tuple[int,...]:
    version=(version or '').strip()
    channel=1
    if re.fullmatch(r'\d+\.\d+-RC\d+', version):
        channel=0
    nums=[]
    if file_version:
        nums=[int(x) for x in re.findall(r'\d+', str(file_version))]
    if not nums:
        rc=re.fullmatch(r'(\d+)\.(\d+)-RC(\d+)', version)
        if rc:
            nums=[int(rc.group(1)), int(rc.group(2)), 0, int(rc.group(3))]
        else:
            nums=[int(x) for x in re.findall(r'\d+', version)]
    if not nums:
        nums=[0]
    nums=(nums+[0,0,0,0])[:4]
    return (channel, *nums)


def _assert_not_downgrade(destination: Path, allow_downgrade: bool) -> None:
    if allow_downgrade:
        return
    path=safe_file(destination,'wad/package.json')
    if path.stat().st_size > 262144:
        raise ValueError('Oversized installed manifest')
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    if not isinstance(data,dict): raise ValueError('Invalid installed manifest: expected an object')
    version=str(data.get('Version',''))
    file_version=data.get('FileVersion')
    if not isinstance(file_version,str):
        file_version=None
    installed=_parse_version(version,file_version)
    source=_parse_version(VERSION,FILE_VERSION)
    if source < installed:
        raise ValueError('Refus de mise à jour vers une version plus ancienne : source '+VERSION+' ('+FILE_VERSION+') < installation '+_version_label(version,file_version)+'. Utilisez --allow-downgrade pour forcer.')


def _pesto_session_mutex_name(root: str, demo: bool) -> str:
    r"""Global mutex name used by Pesto-Startup.ps1 for the session lock.

    Global\GP_Session_<first 24 hex chars, UPPERCASE, of SHA256(root.lower() + 'True'|'False')>
    PowerShell builds it with [BitConverter]::ToString(...).Replace('-',''), which is uppercase,
    and Win32 named-object names are case-sensitive.
    """
    key = root.lower() + ('True' if demo else 'False')
    return 'Global\\GP_Session_' + hashlib.sha256(key.encode('utf-8')).hexdigest()[:24].upper()


def _check_pesto_session_lock(destination: Path) -> None:
    """Refuses the update if Pesto is open from this folder (session mutex exists).

    Only ERROR_FILE_NOT_FOUND means "not open"; any other failure refuses (cannot verify).
    """
    if os.name != 'nt':
        return
    from ctypes import wintypes as w
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenMutexW.argtypes = [w.DWORD, w.BOOL, w.LPCWSTR]
    kernel.OpenMutexW.restype = w.HANDLE
    kernel.CloseHandle.argtypes = [w.HANDLE]
    kernel.CloseHandle.restype = w.BOOL
    found = False
    for demo in (False, True):
        handle = kernel.OpenMutexW(0x00100000, False, _pesto_session_mutex_name(str(destination), demo))  # SYNCHRONIZE
        if handle:
            kernel.CloseHandle(handle)
            found = True
            continue
        error = ctypes.get_last_error()
        if error != 2:  # ERROR_FILE_NOT_FOUND
            raise ValueError("Impossible de vérifier si Pesto est ouvert depuis ce dossier (code %d) : mise à jour refusée." % error)
    if found:
        raise ValueError('Pesto est ouvert depuis ce dossier : fermez-le avant la mise à jour')

def check_local_states() -> None:
    if os.name != 'nt':return  # Linux is used solely for filesystem fixture tests.
    base=Path(os.environ.get('ProgramData',r'C:\ProgramData'))/'GP'
    for folder in ('Interventions','Join','Operations'):
        directory=base/folder
        if not directory.exists():continue
        for path in directory.glob('*.json'):
            if _is_link_or_junction(path) or path.stat().st_size>131072:raise ValueError('Invalid local operation receipt')
            state=json.loads(path.read_text(encoding='utf-8-sig'))
            if not isinstance(state,dict): raise ValueError('Invalid local operation receipt: expected an object')
            if state.get('Phase') not in ('Failed','NotStarted','Verified') and not _acknowledged(state):
                raise ValueError('A local operation remains unresolved. Verify or acknowledge it before updating; no receipt was removed')


_ACK_KEYS=frozenset(('Schema','Utc','By','Reason','Phase','ResultCode','Observation'))
_ACK_PHASES=frozenset(('Running','PendingRestart','Partial','MoveReady','Protection','Uncertain'))
_ACK_UTC=re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$')
_ACK_CONTROL=re.compile(r'[\x00-\x1f\x7f]')


def _acknowledged(state):
    """Mirror of Test-PestoAcknowledgedReceipt (wad/Pesto-Policy.ps1). Explicit acknowledgement decided by David on
    15/10: the receipt keeps its real phase and code and is never a success, but no longer blocks. The acknowledgement
    is void as soon as the receipt phase or code changed after it. Read-only: the receipt is never modified."""
    ack=state.get('Acknowledged')
    if not isinstance(ack,dict) or set(ack)!=_ACK_KEYS:return False
    if type(ack.get('Schema')) is not int or ack.get('Schema')!=1:return False
    utc,by,reason=ack.get('Utc'),ack.get('By'),ack.get('Reason')
    if not isinstance(utc,str) or len(utc)>64 or not _ACK_UTC.match(utc):return False
    if not isinstance(by,str) or not by.strip() or len(by)>256 or _ACK_CONTROL.search(by):return False
    if not isinstance(reason,str) or len(reason.strip())<3 or len(reason)>500 or _ACK_CONTROL.search(reason):return False
    if ack.get('Phase') not in _ACK_PHASES or ack.get('Phase')!=state.get('Phase'):return False
    code,acked=state.get('ResultCode'),ack.get('ResultCode')
    if code is None or acked is None:return code is None and acked is None
    if type(code) is not int or type(acked) is not int:return False
    return code==acked


# O8: Pesto queues of the current Windows profile, listed by the command line after the preview or the update, outside
# plan_update/apply_update (the plan and update-plan.json do not depend on them). Read-only, informative, never blocking.
# Rules taken from the PowerShell source (wad/Pesto-Core.ps1, Pesto-Startup.ps1, Pesto-Support.ps1, Pesto-Interventions.ps1);
# they are reproduced here, not replayed under Windows PowerShell 5.1. The historical GP names are stable keys: never renamed.
#  Get-PestoStateDirectory / Get-PestoStartupStateId: %LOCALAPPDATA%\GP\State\<id>\queue.json (and history-v1.json),
#    <id> = first 16 uppercase hex digits of SHA-256(UTF-8(GetFullPath(<installation>\wad\cfg.json).ToLowerInvariant())).
#  Save-PestoQueueCheckpoint: UTF-8 without BOM, Schema=1, Mode='REEL' (nothing is written in SIMULATION, demo or read-only
#    mode), Phase Idle | BetweenActions | Active | Uncertain | Reviewed | Acknowledged, 16 MiB cap. Acknowledged: safety
#    lock lifted by an explicit operator acknowledgement (15/10); rows keep their real status.
#  Restore-PestoQueueCheckpoint (REEL only) activates the safety lock when the file is over 16 MiB, unreadable, not
#    Schema 1 / Mode REEL (case-insensitive comparisons), has more than 5000 rows, when Phase is Active or Uncertain,
#    or when a row is 'EN COURS'. Not modelled: owner (Host/MachineId/Domain) and OperationIds checks, which can also lock.
#  Rows to verify: INCERTAIN, TECHNIQUE, PROTECTION (and EN COURS); PARTIEL (code 89): partial move to resume.
QUEUE_LIMIT=16*1024*1024  # Same cap as Save/Restore-PestoQueueCheckpoint.
QUEUE_ROW_LIMIT=5000  # Restore-PestoQueueCheckpoint refuses more rows.
QUEUE_DIR_LIMIT=256  # queue.json files read; the ids of this installation are always read first.
QUEUE_ENTRY_LIMIT=4096  # Entries listed under GP\State: bounds the scan time.
_QUEUE_LOCK_PHASES=frozenset(('active','uncertain'))
_QUEUE_OPEN_PHASES=frozenset(('betweenactions',))  # Lot started, final checkpoint (Idle/Uncertain) never written.
_QUEUE_CLOSED_PHASES=frozenset(('idle','reviewed','acknowledged'))
_QUEUE_LOCK_STATUSES=frozenset(('EN COURS',))
_QUEUE_VERIFY_STATUSES=frozenset(('INCERTAIN','TECHNIQUE','PROTECTION'))
_QUEUE_OPEN_STATUSES=frozenset(('PARTIEL',))
_QUEUE_BOMS=((b'\xff\xfe\x00\x00','utf-32-le'),(b'\x00\x00\xfe\xff','utf-32-be'),(b'\xef\xbb\xbf','utf-8'),
             (b'\xff\xfe','utf-16-le'),(b'\xfe\xff','utf-16-be'))


def _lower_invariant(text: str) -> str:
    """Approximates .NET ToLowerInvariant: one code unit in, one out. Exact for ASCII; parity beyond ASCII not replayed."""
    return ''.join(c if ord(c)>0xFFFF or len(c.lower())!=1 else c.lower() for c in text)


def queue_state_id(config_path: str) -> str:
    """Same id as Get-PestoStateDirectory / Get-PestoStartupStateId for an already full path."""
    return hashlib.sha256(_lower_invariant(config_path).encode('utf-8')).hexdigest()[:16].upper()


def _decode_queue_bytes(data: bytes) -> str:
    """Like .NET StreamReader behind Get-Content -Encoding UTF8: a byte order mark wins, else UTF-8 with replacement."""
    for bom,codec in _QUEUE_BOMS:
        if data.startswith(bom):return data[len(bom):].decode(codec,'replace')
    return data.decode('utf-8','replace')


def _ps_property(value: dict,name: str):
    """PowerShell property access is case-insensitive."""
    if name in value:return value[name]
    folded=name.casefold()
    return next((v for k,v in value.items() if isinstance(k,str) and k.casefold()==folded),None)


def _ps_schema_is_one(value) -> bool:
    """`$state.Schema -ne 1` is false for 1, 1.0 and '1'. Other shapes are treated as refused (reported, never assumed)."""
    if isinstance(value,bool):return False
    if isinstance(value,(int,float)):return value==1
    return value=='1'


def _short_text(value,limit: int=256):
    return value[:limit] if isinstance(value,str) else None


def _new_queue_entry(path: Path) -> dict:
    return {'Path':str(path),'StateId':path.parent.name,'ThisInstallation':False,'State':'Unreadable','SafetyLockExpected':None,
            'Phase':None,'Utc':None,'Domain':None,'Rows':0,'UncertainRows':0,'OpenRows':0,'Statuses':{},'Reasons':[]}


def _read_user_queue(path: Path) -> dict:
    """Read one queue.json without ever raising: an unreadable queue is reported, never fatal."""
    entry=_new_queue_entry(path);reasons=entry['Reasons']
    try:
        if _is_link_or_junction(path):
            reasons.append('lien ou jonction refusé : fichier non lu');return entry
        entry['SafetyLockExpected']=True  # Any failure below makes the restore of Pesto activate its lock.
        if not path.is_file():
            reasons.append("pas un fichier ordinaire : la reprise de Pesto activera le verrou de sécurité");return entry
        with path.open('rb') as stream:
            data=stream.read(QUEUE_LIMIT+1)
        if len(data)>QUEUE_LIMIT:
            reasons.append('plus de 16 Mio : la reprise de Pesto la refusera (verrou de sécurité)');return entry
        value=json.loads(_decode_queue_bytes(data))
    except Exception as exc:  # Informative scan: report, never block the preview.
        reasons.append('illisible ('+type(exc).__name__+') : la reprise de Pesto activera le verrou de sécurité');return entry
    if not isinstance(value,dict):
        reasons.append('contenu inattendu (objet JSON attendu) : la reprise de Pesto activera le verrou de sécurité');return entry
    lock=False;verify=False;open_=False
    mode=_ps_property(value,'Mode')
    if not _ps_schema_is_one(_ps_property(value,'Schema')) or not (isinstance(mode,str) and mode.casefold()=='reel'):
        lock=True;reasons.append('format non reconnu (Schema/Mode) : la reprise de Pesto activera le verrou de sécurité')
    phase=_ps_property(value,'Phase');entry['Phase']=_short_text(phase,64)
    entry['Utc']=_short_text(_ps_property(value,'Utc'),64);entry['Domain']=_short_text(_ps_property(value,'Domain'))
    key=phase.casefold() if isinstance(phase,str) else ''
    if key in _QUEUE_LOCK_PHASES:
        lock=True;reasons.append('phase '+entry['Phase']+' : exécution interrompue ou à vérifier (verrou de sécurité au prochain démarrage)')
    elif key in _QUEUE_OPEN_PHASES:
        open_=True;reasons.append('phase '+entry['Phase']+' : lot commencé sans bilan final (en cours ou interrompu)')
    elif key not in _QUEUE_CLOSED_PHASES:
        open_=True;reasons.append('phase absente ou inconnue')
    rows=_ps_property(value,'Rows')
    if rows is None:rows=[]
    elif isinstance(rows,dict):rows=[rows]  # Windows PowerShell 5.1 may collapse a one-item array.
    elif not isinstance(rows,list):
        open_=True;reasons.append('lignes illisibles');rows=[]
    entry['Rows']=len(rows);statuses={};malformed=0;locked_rows=0
    if len(rows)>QUEUE_ROW_LIMIT:
        lock=True;reasons.append('plus de '+str(QUEUE_ROW_LIMIT)+' lignes : la reprise de Pesto la refusera (verrou de sécurité)')
    for row in rows:
        if not isinstance(row,dict):
            malformed+=1;continue
        # Status only: a row verified in Pesto becomes VÉRIFIÉ but keeps its old code 89 (Apply-PestoQueueObservation).
        status=_ps_property(row,'Statut')
        label=status.upper() if isinstance(status,str) else ''
        if label in _QUEUE_LOCK_STATUSES:locked_rows+=1;entry['UncertainRows']+=1
        elif label in _QUEUE_VERIFY_STATUSES:entry['UncertainRows']+=1
        elif label in _QUEUE_OPEN_STATUSES:entry['OpenRows']+=1
        else:continue
        statuses[label]=statuses.get(label,0)+1
    entry['Statuses']=dict(sorted(statuses.items()))
    if locked_rows:
        lock=True;reasons.append(str(locked_rows)+' ligne(s) EN COURS : action interrompue (verrou de sécurité au prochain démarrage)')
    if entry['UncertainRows']>locked_rows:
        verify=True;reasons.append(str(entry['UncertainRows']-locked_rows)+' ligne(s) au résultat incertain à vérifier')
    if entry['OpenRows']:
        open_=True;reasons.append(str(entry['OpenRows'])+' ligne(s) au déplacement partiel (code 89) à reprendre')
    if malformed:
        open_=True;reasons.append(str(malformed)+' ligne(s) illisible(s)')
    entry['SafetyLockExpected']=lock
    entry['State']='Uncertain' if lock or verify else 'NotConcluded' if open_ else 'Concluded'
    return entry


def list_user_queues(config_paths=(),local_appdata=None) -> dict:
    """Read-only inventory of the current profile's Pesto queues. Never writes, removes or raises.

    local_appdata defaults to %LOCALAPPDATA%; tests inject a temporary directory.
    """
    result={'Scope':'CurrentUser','LocalAppData':None,'Status':'NotExamined','Queues':[],'Warning':None,
            'Note':"Lecture seule du profil Windows courant : les autres comptes, dont le compte élevé d'un relais UAC, "
                   "ne sont pas examinés. Classement établi d'après les règles de reprise de Pesto ; le propriétaire de la file "
                   "(poste, domaine) et ses identifiants d'opération ne sont pas contrôlés. "
                   "Aperçu informatif : la mise à jour n'est pas bloquée (décision non prise)."}
    queues=result['Queues']
    try:
        raw=os.environ.get('LOCALAPPDATA') if local_appdata is None else os.fspath(local_appdata)
        if not raw:
            result['Warning']="Profil local (LOCALAPPDATA) non déterminé : files de lots non examinées. Vérifiez-les dans Pesto avant --apply."
            return result
        base=Path(raw);result['LocalAppData']=str(base)
        if not base.is_absolute():
            result['Warning']='LOCALAPPDATA non absolu : files de lots non examinées. Vérifiez-les dans Pesto avant --apply.';return result
        state=base/'GP'/'State'
        for item in (base,base/'GP',state):
            if _is_link_or_junction(item):
                result['Warning']='Lien ou jonction refusé ('+str(item)+') : files de lots non examinées. Vérifiez-les dans Pesto avant --apply.'
                return result
        if not state.is_dir():
            result['Status']='NoQueue';return result
        ours={queue_state_id(str(p)) for p in config_paths}
        # This installation first, so that the limits below can never hide its own queue.
        children=[state/sid for sid in sorted(ours) if os.path.lexists(state/sid)]
        listed=[];truncated=False
        for child in state.iterdir():
            if len(listed)>=QUEUE_ENTRY_LIMIT:truncated=True;break
            listed.append(child)
        first={c.name.upper() for c in children}
        children+=sorted((c for c in listed if c.name.upper() not in first),key=lambda p:p.name.casefold())
        examined=0;skipped=0
        for child in children:
            queue=child/'queue.json'
            if _is_link_or_junction(child):
                entry=_new_queue_entry(queue);entry['Reasons'].append('dossier lien ou jonction refusé : non lu')
            elif not child.is_dir() or not os.path.lexists(queue):
                continue  # History-only directory or plain file: no queue.
            elif examined>=QUEUE_DIR_LIMIT:
                skipped+=1;continue
            else:
                examined+=1;entry=_read_user_queue(queue)
            entry['StateId']=child.name;entry['ThisInstallation']=child.name.upper() in ours
            queues.append(entry)
        attention=[q for q in queues if q['State']!='Concluded']
        result['Status']='Attention' if attention or skipped or truncated else 'Clear' if queues else 'NoQueue'
        notes=[]
        if skipped:notes.append(str(skipped)+' file(s) de lots non examinée(s) (plus de '+str(QUEUE_DIR_LIMIT)+').')
        if truncated:notes.append("Plus de "+str(QUEUE_ENTRY_LIMIT)+" entrées dans "+str(state)+" : liste tronquée, files restantes non examinées.")
        if attention:
            mine=', dont celle de cette installation' if any(q['ThisInstallation'] for q in attention) else ''
            locked=sum(1 for q in attention if q['SafetyLockExpected'])
            lock_text=(' Verrou de sécurité attendu au prochain démarrage de Pesto pour '+str(locked)+' file(s).') if locked else ''
            notes.insert(0,'ATTENTION : '+str(len(attention))+' file(s) de lots non conclue(s), incertaine(s) ou illisible(s) dans ce profil'+mine+
                         ". Vérifiez dans Pesto l'état réel des postes concernés avant --apply."+lock_text+
                         " La mise à jour n'est pas bloquée (décision non prise).")
        elif notes:
            notes.append("Vérifiez-les dans Pesto avant --apply. La mise à jour n'est pas bloquée (décision non prise).")
        result['Warning']=' '.join(notes) or None
    except Exception as exc:  # Informative scan: report, never block the preview.
        result['Status']='NotExamined'
        result['Warning']='Files de lots non examinées ('+type(exc).__name__+'). Vérifiez-les dans Pesto avant --apply.'
    return result


def installation_queues(destination: Path,local_appdata=None) -> dict:
    """Queues of the current profile for one installation, as the command line reports them. Never raises.

    Called by main() only once the plan or the update has succeeded, never by plan_update or apply_update:
    the plan (preview, plan under the lock, update-plan.json) stays the same whatever the queues do,
    and the scan can neither refuse nor interrupt an update.
    """
    paths=[]
    try:
        # Pesto hashes the full path as launched (GetFullPath, not resolved): the typed form first, then the resolved one.
        paths.append(str(Path(os.path.abspath(destination))/'wad'/'cfg.json'))
        paths.append(str(Path(destination).resolve(strict=True)/'wad'/'cfg.json'))
    except Exception:pass  # Forms already computed are kept; queues are listed anyway.
    try:return list_user_queues(paths,local_appdata)
    except Exception as exc:  # Defence in depth: list_user_queues already reports its own failures.
        return {'Scope':'CurrentUser','LocalAppData':None,'Status':'NotExamined','Queues':[],
                'Warning':'Files de lots non examinées ('+type(exc).__name__+'). Vérifiez-les dans Pesto avant --apply.'}


def queue_warning_lines(info) -> list[str]:
    """Console lines: always the examined profile and its limit, details only when a queue needs attention."""
    if not isinstance(info,dict):return []
    profile=str(info.get('LocalAppData') or 'profil non déterminé')
    scope="Autres comptes Windows, dont le compte élevé d'un relais UAC : non examinés."
    if not info.get('Warning'):
        count=len(info.get('Queues') or [])
        found=str(count)+' file(s), toutes conclues' if count else 'aucune file'
        return ['Files de lots Pesto ('+profile+') : '+found+'. '+scope]
    lines=['','*** Files de lots Pesto - profil courant : '+profile+' ***',str(info['Warning'])]
    for q in info.get('Queues') or []:
        if q.get('State')=='Concluded':continue
        mark=' [cette installation]' if q.get('ThisInstallation') else ''
        lines.append('  - '+str(q.get('State'))+mark+' : '+str(q.get('Path'))+' | '+'; '.join(q.get('Reasons') or []))
    lines.append(scope)
    return lines


def print_queue_lines(info,stream=None) -> None:
    """Write the queue lines to stderr without ever failing a preview or an update that already succeeded."""
    lines=queue_warning_lines(info)
    if not lines:return
    try:
        stream=sys.stderr if stream is None else stream
        sys.stdout.flush()
        text='\n'.join(lines)+'\n';encoding=getattr(stream,'encoding',None) or 'utf-8'
        try:text.encode(encoding)
        except LookupError:text=text.encode('ascii','replace').decode('ascii')
        except UnicodeError:text=text.encode(encoding,'replace').decode(encoding,'replace')
        stream.write(text);stream.flush()
    except Exception:  # A console that cannot show the message must not turn success into failure.
        pass


@contextlib.contextmanager
def mutation_guard():
    if os.name!='nt':yield;return
    from ctypes import wintypes as w
    dll=ctypes.WinDLL('kernel32',use_last_error=True)
    dll.CreateMutexW.argtypes=[ctypes.c_void_p,w.BOOL,w.LPCWSTR];dll.CreateMutexW.restype=w.HANDLE
    dll.WaitForSingleObject.argtypes=[w.HANDLE,w.DWORD];dll.WaitForSingleObject.restype=w.DWORD
    dll.ReleaseMutex.argtypes=[w.HANDLE];dll.CloseHandle.argtypes=[w.HANDLE]
    handle=dll.CreateMutexW(None,False,'Global\\GP_PostMutation_v1')
    if not handle:raise OSError(ctypes.get_last_error(),'Cannot acquire mutation coordination')
    owned=False
    try:
        status=dll.WaitForSingleObject(handle,0)
        if status not in (0,0x80):raise ValueError('A mutation is active or the mutex cannot be inspected')
        owned=True;yield
    finally:
        if owned:dll.ReleaseMutex(handle)
        dll.CloseHandle(handle)


def plan_update(source: Path,destination: Path,*,allow_downgrade: bool=False) -> dict:
    if _is_link_or_junction(source) or _is_link_or_junction(destination):raise ValueError('Linked roots are refused')
    source=source.resolve(strict=True);destination=destination.resolve(strict=True)
    if source==destination or source in destination.parents or destination in source.parents:
        raise ValueError('Source and installation must be separate directories')
    verify_runtime(source)
    before=old_components(destination)
    _assert_not_downgrade(destination,allow_downgrade)
    config=safe_file(destination,'wad/cfg.json')
    managed=_managed_receipt(destination,before)
    # No configuration/operation receipt/preference/log is in this copy list.
    # Managed ownership metadata is staged separately from the installed receipt,
    # never copied/adopted from the distribution being installed.
    paths=tuple(runtime_files(source))+('wad/package.json',)
    if not 20<=len(paths)-1<=MAX_RUNTIME_COMPONENTS:raise ValueError('Invalid source runtime file count')
    for path in paths:
        target=destination/path
        for item in (target,*target.parents):
            if item==destination:break
            if _is_link_or_junction(item):raise ValueError('Linked destination component')
        try:
            resolved=target.resolve(strict=False)
        except OSError as exc:
            raise ValueError('Cannot resolve destination component: '+path) from exc
        if destination not in resolved.parents:
            raise ValueError('Resolved destination component escapes root: '+path)
    return {'Source':str(source),'Destination':str(destination),'Files':list(paths),'PreviousFiles':list(before),
            'ConfigurationSHA256':file_hash(config),'Version':VERSION,'Kind':'ApplicationCodeOnly',
            'ManagedInstallation':managed is not None,
            'InstallationReceiptSHA256':file_hash(safe_file(destination,RECEIPT)) if managed is not None else None}


def _managed_receipt(root: Path,components,*,required=False):
    manifest_path=safe_file(root,'wad/package.json')
    if manifest_path.stat().st_size>262144:raise ValueError('Oversized installed manifest')
    manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    if not isinstance(manifest,dict):raise ValueError('Invalid installed manifest')
    return require_intact_receipt(root,components,required=required,version=manifest.get('Version'))


def _preparation_fence(destination: Path,plan: dict) -> dict:
    fence={'Schema':1,'Stage':'Preparing','Destination':str(destination)}
    if plan['ManagedInstallation']:
        fence['InstallationReceiptSHA256']=plan['InstallationReceiptSHA256']
    return fence



def _replace_windows_preserving_acl(replacement, target) -> None:
    """ReplaceFileW keeps the target DACL and filesystem metadata.

    Refuse any merge failure: no IGNORE_ACL_ERRORS / delete-then-move fallback.
    https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-replacefilew
    """
    from ctypes import wintypes as w
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    replace = kernel.ReplaceFileW
    replace.argtypes = [w.LPCWSTR, w.LPCWSTR, w.LPCWSTR, w.DWORD, w.LPVOID, w.LPVOID]
    replace.restype = w.BOOL
    if not replace(str(target), str(replacement), None, 0, None, None):
        error = ctypes.get_last_error()
        raise OSError(error, 'Replacement refused; existing permissions could not be preserved', str(target))


def _replace_from(source: Path,target: Path) -> None:
    target.parent.mkdir(parents=True,exist_ok=True)
    fd,name=tempfile.mkstemp(prefix='.pesto-copy-',suffix='.tmp',dir=target.parent)
    try:
        with os.fdopen(fd,'wb') as out,source.open('rb') as stream:
            shutil.copyfileobj(stream,out);out.flush();os.fsync(out.fileno())
        if target.exists():
            if os.name == 'nt':
                _replace_windows_preserving_acl(name, target)
            else:
                # Preserve explicit access mode instead of publishing mkstemp's
                # private 0600 permissions over an existing installation.
                os.chmod(name, stat.S_IMODE(target.stat().st_mode))
                os.replace(name,target)
        else:
            os.replace(name,target)
        _fsync_directory(target.parent)
    finally:
        if os.path.exists(name):os.unlink(name)



def _fsync_directory(directory: Path) -> None:
    """POSIX fixture durability; Windows file FlushFileBuffers is via os.fsync."""
    if os.name != 'nt':
        fd=os.open(directory,os.O_RDONLY)
        try:os.fsync(fd)
        finally:os.close(fd)


def _write_json(path: Path,value: dict) -> None:
    data=json.dumps(value,ensure_ascii=False,sort_keys=True,indent=2).encode('utf-8')
    fd,name=tempfile.mkstemp(prefix='.pesto-journal-',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as stream:
            stream.write(data);stream.flush();os.fsync(stream.fileno())
        os.replace(name,path);_fsync_directory(path.parent)
    finally:
        if os.path.exists(name):os.unlink(name)


def _plain_target(root: Path,relative: str) -> Path:
    validate_relative(relative)
    target=root/relative
    for item in (target,*target.parents):
        if item==root:break
        if _is_link_or_junction(item):raise ValueError('Linked update component: '+relative)
    if target.exists() and not target.is_file():raise ValueError('Not a regular update component: '+relative)
    try:
        resolved=target.resolve(strict=False)
    except OSError as exc:
        raise ValueError('Cannot resolve update component: '+relative) from exc
    if root not in resolved.parents:
        raise ValueError('Resolved update component escapes root: '+relative)
    return target


def _digest_or_none(path: Path) -> str|None:
    return file_hash(path) if path.is_file() else None


def _load_json(path: Path,limit: int=262144) -> dict:
    if _is_link_or_junction(path) or not path.is_file() or path.stat().st_size>limit:raise ValueError('Invalid update journal')
    with path.open('rb') as stream:
        data=stream.read(limit+1)
    if len(data)>limit:raise ValueError('Oversized update journal')
    value=json.loads(data.decode('utf-8'))
    if not isinstance(value,dict):raise ValueError('Update journal must be an object')
    return value


def _restore_records(destination: Path,backup: Path,records: list[dict]) -> list[str]:
    failures=[]
    for entry in reversed(records):
        rel=entry['Path']
        try:
            target=_plain_target(destination,rel)
            current=_digest_or_none(target)
            if current not in (entry['OldSHA256'],entry['NewSHA256'],None):
                raise ValueError('File changed outside this update: '+rel)
            if entry['OldSHA256'] is None:
                if current is not None:target.unlink();_fsync_directory(target.parent)
            else:
                old=safe_file(backup/'old',rel)
                if file_hash(old)!=entry['OldSHA256']:raise ValueError('Invalid rollback backup: '+rel)
                if current!=entry['OldSHA256']:_replace_from(old,target)
        except (OSError,ValueError) as exc:failures.append(str(exc))
    return failures


def apply_update(source: Path,destination: Path,*,allow_downgrade: bool=False,_inject_after: int|None=None,_crash_after: int|None=None,_crash_stage: str|None=None) -> dict:
    """Stage verified code before copying. Keep a durable recovery fence after a crash.

    Fixture injection arguments are Python test-only, not command-line switches.
    This is recoverable per-file replacement, not an atomic OS/AD transaction.
    """
    plan=plan_update(source,destination,allow_downgrade=allow_downgrade)
    source=Path(plan['Source']);destination=Path(plan['Destination'])
    lock=destination/'.pesto-update.lock';backup=None;can_remove=False
    with mutation_guard():
        check_local_states()
        # Before the O_EXCL fence: a refusal here leaves no lock behind.
        _check_pesto_session_lock(destination)
        fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
        with os.fdopen(fd,'wb') as stream:
            # The destination is recorded so that --recover can release this fence after checking the installation is intact.
            stream.write(json.dumps(_preparation_fence(destination,plan)).encode('utf-8'));stream.flush();os.fsync(stream.fileno())
        _fsync_directory(destination)
        records=[];changed=[]
        try:
            plan=plan_update(source,destination,allow_downgrade=allow_downgrade)
            # Again with the fence in place (new launches are refused); a refusal releases the lock.
            _check_pesto_session_lock(destination)
            _write_json(lock,_preparation_fence(destination,plan))
            backup=Path(tempfile.mkdtemp(prefix=destination.name+'-code-backup-',dir=destination.parent))
            os.chmod(backup,0o700)
            paths=set(plan['Files'])|set(plan['PreviousFiles'])
            if plan['ManagedInstallation']:paths.update(PROD_HELPERS)
            paths=sorted(paths,key=lambda p:(p=='Pesto.exe',p=='wad/package.json',p))
            for rel in paths:
                current=_plain_target(destination,rel);new=safe_file(source,rel) if rel in plan['Files'] else current
                record={'Path':rel,'OldSHA256':_digest_or_none(current),'NewSHA256':file_hash(new)}
                if record['OldSHA256'] is not None:_replace_from(current,backup/'old'/rel)
                _replace_from(new,backup/'new'/rel)
                records.append(record)
                if _crash_stage=='preparing':os._exit(94)
            verify_runtime(backup/'new')
            if plan['ManagedInstallation']:
                # Helpers remain the installed bytes; their ownership is retained.
                # The receipt is the last replacement and participates in rollback.
                current=safe_file(destination,RECEIPT)
                if file_hash(current)!=plan['InstallationReceiptSHA256']:raise ValueError('Installation ownership changed during preparation')
                _replace_from(current,backup/'old'/RECEIPT)
                if file_hash(safe_file(backup/'old',RECEIPT))!=plan['InstallationReceiptSHA256']:raise ValueError('Installation ownership changed while staging')
                _managed_receipt(backup/'old',plan['PreviousFiles'],required=True)
                _write_json(backup/'new'/RECEIPT,make_receipt(backup/'new',runtime_files(backup/'new'),plan['Version']))
                _managed_receipt(backup/'new',runtime_files(backup/'new'),required=True)
                records.append({'Path':RECEIPT,'OldSHA256':plan['InstallationReceiptSHA256'],
                                'NewSHA256':file_hash(safe_file(backup/'new',RECEIPT))})
            journal={'Schema':1,'Id':uuid.uuid4().hex,'Destination':str(destination),'Records':records,
                     'ConfigurationSHA256':plan['ConfigurationSHA256'],'Version':plan['Version'],
                     'ManagedInstallation':plan['ManagedInstallation']}
            _write_json(backup/'transaction.json',journal)
            _write_json(backup/'update-plan.json',plan)
            _write_json(lock,{'Schema':1,'Stage':'Copying','Backup':str(backup),'Destination':str(destination),
                              'Id':journal['Id'],'JournalSHA256':file_hash(backup/'transaction.json')})
            try:
                for record in records:
                    rel=record['Path'];target=_plain_target(destination,rel)
                    if _digest_or_none(target)!=record['OldSHA256']:raise ValueError('Concurrent code change: '+rel)
                    changed.append(record) # Record intent even when the replacement raises after changing the file.
                    _replace_from(safe_file(backup/'new',rel),target)
                    if _crash_after is not None and len(changed)==_crash_after:os._exit(93)
                    if _inject_after is not None and len(changed)==_inject_after:raise OSError('Injected fixture interruption')
                verify_runtime(destination)
                _managed_receipt(destination,runtime_files(destination),required=plan['ManagedInstallation'])
                if file_hash(destination/'wad/cfg.json')!=plan['ConfigurationSHA256']:raise ValueError('Configuration changed concurrently')
            except BaseException as error:
                failures=_restore_records(destination,backup,changed)
                if not failures:
                    try:
                        previous=old_components(destination)
                        _managed_receipt(destination,previous,required=plan['ManagedInstallation'])
                    except (OSError,ValueError) as verify_error:failures.append(str(verify_error))
                _write_json(backup/'rollback-result.json',{'RollbackFailures':failures,'OriginalError':str(error)})
                can_remove=not failures
                if failures:raise RuntimeError('Code rollback incomplete; recovery lock retained. Backup: '+str(backup)) from error
                raise
            _write_json(backup/'completed.json',{'Updated':True,'Version':plan['Version']})
            if _crash_stage=='completed':os._exit(95)
            can_remove=True
            return {'Updated':True,'Backup':str(backup),'Version':plan['Version'],'ConfigPreserved':True,
                    'ManagedInstallation':plan['ManagedInstallation'],
                    'Note':'Application code only; a crash retains the lock for explicit --recover. No AD rollback.'}
        except BaseException:
            # Preparation failures occur before any destination replacement.
            if not changed:can_remove=True
            raise
        finally:
            if can_remove:lock.unlink(missing_ok=True);_fsync_directory(destination)


def plan_recovery(destination: Path) -> dict:
    if _is_link_or_junction(destination):raise ValueError('Linked installation root refused')
    destination=destination.resolve(strict=True)
    lock=_load_json(destination/'.pesto-update.lock',8192)
    preparing_fields={'Schema','Stage','Destination'}
    if type(lock.get('Schema')) is int and lock.get('Schema')==1 and lock.get('Stage')=='Preparing' and set(lock) in (preparing_fields,preparing_fields|{'InstallationReceiptSHA256'}):
        # Interrupted before any replacement: release only if the installed code still matches its own manifest.
        # A legacy fence without its recorded destination stays a manual decision.
        if lock['Destination']!=str(destination):raise ValueError('Wrong recovery target')
        previous=old_components(destination)
        managed='InstallationReceiptSHA256' in lock
        if managed and (not isinstance(lock['InstallationReceiptSHA256'],str) or
                        not re.fullmatch(r'[a-f0-9]{64}',lock['InstallationReceiptSHA256']) or
                        file_hash(safe_file(destination,RECEIPT))!=lock['InstallationReceiptSHA256']):
            raise ValueError('Installation ownership changed after interrupted preparation')
        _managed_receipt(destination,previous,required=managed)
        return {'Destination':str(destination),'Backup':None,'Files':[],'Records':[],'Conflicts':[],
                'ConfigurationPreserved':True,'Kind':'ReleaseInterruptedPreparation'}
    if set(lock)!= {'Schema','Stage','Backup','Destination','Id','JournalSHA256'} or type(lock['Schema']) is not int or lock['Schema']!=1 or lock['Stage']!='Copying':
        raise ValueError('Incomplete preparation journal; no automatic recovery. Inspect the retained backup before removing the fence')
    if (lock['Destination']!=str(destination) or not isinstance(lock['Id'],str) or
            not re.fullmatch(r'[a-f0-9]{32}',lock['Id'])):raise ValueError('Wrong recovery target')
    if not isinstance(lock['Backup'],str) or not lock['Backup'] or not isinstance(lock['JournalSHA256'],str) or not re.fullmatch(r'[a-f0-9]{64}',lock['JournalSHA256']):
        raise ValueError('Invalid recovery backup or journal hash')
    backup=Path(lock['Backup'])
    if _is_link_or_junction(backup) or backup.parent!=destination.parent or not backup.name.startswith(destination.name+'-code-backup-'):
        raise ValueError('Recovery backup must be the recorded sibling directory')
    transaction=safe_file(backup,'transaction.json')
    if file_hash(transaction)!=lock['JournalSHA256']:raise ValueError('Recovery journal hash mismatch')
    journal=_load_json(transaction)
    if type(journal.get('Schema')) is not int or journal.get('Schema')!=1 or journal.get('Id')!=lock['Id'] or journal.get('Destination')!=str(destination):raise ValueError('Journal identity mismatch')
    managed=journal.get('ManagedInstallation',False)
    if type(managed) is not bool:raise ValueError('Invalid managed installation recovery flag')
    owned_metadata={RECEIPT,*PROD_HELPERS} if managed else set()
    records=journal.get('Records')
    if not isinstance(records,list) or not 20<=len(records)<=MAX_RECOVERY_COMPONENTS:raise ValueError('Invalid recovery file count')
    expected={'Pesto.exe','wad/package.json'};seen=set();conflicts=[]
    for r in records:
        if not isinstance(r,dict) or set(r)!= {'Path','OldSHA256','NewSHA256'}:raise ValueError('Unexpected recovery fields')
        rel=r['Path']
        if not isinstance(rel,str) or rel not in owned_metadata:_validate_recovery_relative(rel)
        if rel.casefold() in seen:raise ValueError('Duplicate recovery path: '+rel)
        seen.add(rel.casefold())
        for h in ('OldSHA256','NewSHA256'):
            if not (h=='OldSHA256' and r[h] is None) and not re.fullmatch(r'[a-f0-9]{64}',str(r[h])):raise ValueError('Invalid recovery hash')
        if r['OldSHA256'] is not None and file_hash(safe_file(backup/'old',rel))!=r['OldSHA256']:raise ValueError('Rollback file is corrupt: '+rel)
        if file_hash(safe_file(backup/'new',rel))!=r['NewSHA256']:raise ValueError('Staged file is corrupt: '+rel)
        current=_digest_or_none(_plain_target(destination,rel))
        if current not in (None,r['OldSHA256'],r['NewSHA256']):conflicts.append(rel)
    if not {x.casefold() for x in expected}.issubset(seen):raise ValueError('Recovery manifest/launcher absent')
    # Validate the closed old manifest; never restore arbitrary user files from a journal.
    old=old_components(backup/'old')
    verify_runtime(backup/'new')
    if {r['Path'] for r in records} != set(old)|set(runtime_files(backup/'new'))|{'wad/package.json'}|owned_metadata:raise ValueError('Recovery list does not match the two runtime manifests and ownership')
    if managed:
        _managed_receipt(backup/'old',old,required=True)
        _managed_receipt(backup/'new',runtime_files(backup/'new'),required=True)
        # Management may update ownership, never silently start owning new helper
        # bytes from a source distribution or an arbitrary unowned file.
        for record in records:
            if record['Path'] in owned_metadata and (record['OldSHA256'] is None or
                    (record['Path'] in PROD_HELPERS and record['OldSHA256']!=record['NewSHA256'])):
                raise ValueError('Managed recovery cannot adopt or replace unowned metadata')
    if not set(old).issubset({r['Path'] for r in records}):raise ValueError('Incomplete old runtime backup')
    completed=backup/'completed.json'
    if completed.is_file() and not _is_link_or_junction(completed) and _load_json(completed,4096)=={'Updated':True,'Version':journal.get('Version')}:
        # Crash after a verified update, before the fence was removed: keep the new code, do not roll it back.
        if all(_digest_or_none(_plain_target(destination,r['Path']))==r['NewSHA256'] for r in records):
            verify_runtime(destination)
            _managed_receipt(destination,runtime_files(destination),required=managed)
            return {'Destination':str(destination),'Backup':str(backup),'Files':[],'Records':[],'Conflicts':[],
                    'ConfigurationPreserved':True,'Kind':'ReleaseCompletedUpdate'}
    return {'Destination':str(destination),'Backup':str(backup),'Files':[r['Path'] for r in records],
            'Records':records,'Conflicts':conflicts,'ConfigurationPreserved':True,'Kind':'RestorePreviousCodeOnly',
            'ManagedInstallation':managed}


def recover_update(destination: Path,*,apply: bool=False) -> dict:
    plan=plan_recovery(destination)
    if not apply:return {k:v for k,v in plan.items() if k!='Records'}
    with mutation_guard():
        check_local_states();plan=plan_recovery(destination)
        if plan['Kind'] in ('ReleaseInterruptedPreparation','ReleaseCompletedUpdate'):
            # Verified state: no file is copied, only the fence is removed.
            root=Path(plan['Destination']);(root/'.pesto-update.lock').unlink();_fsync_directory(root)
            note=('Preparation interrupted before any replacement; installed code verified intact.' if plan['Kind']=='ReleaseInterruptedPreparation'
                  else 'Update had completed; new code verified in place and kept.')
            return {'Recovered':True,'Destination':str(root),'Backup':plan['Backup'],'ConfigPreserved':True,'Kind':plan['Kind'],'Note':note}
        if plan['Conflicts']:raise ValueError('Code edited outside update; automatic recovery refused: '+', '.join(plan['Conflicts']))
        root=Path(plan['Destination']);backup=Path(plan['Backup'])
        failures=_restore_records(root,backup,plan['Records'])
        if not failures:
            try:
                previous=old_components(root)
                _managed_receipt(root,previous,required=plan.get('ManagedInstallation',False))
            except (OSError,ValueError) as exc:failures.append(str(exc))
        # Restored bytes do not complete recovery while the publication fence remains.
        _write_json(backup/'recovery-result.json',{'Recovered':False,'Failures':failures,
                    'CodeRestored':not failures,'FenceRetained':True})
        if failures:raise RuntimeError('Recovery incomplete; lock retained. Inspect '+str(backup))
        (root/'.pesto-update.lock').unlink();_fsync_directory(root)
        report_written=True
        try:_write_json(backup/'recovery-result.json',{'Recovered':True,'Failures':[]})
        except OSError:report_written=False
        return {'Recovered':True,'Destination':str(root),'Backup':str(backup),'ConfigPreserved':True,
                'ResultReportWritten':report_written,
                'Note':'Previous application code restored, no operation receipt changed and no AD action.'}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[1])
    p.add_argument('--destination',type=Path,required=True)
    p.add_argument('--apply',action='store_true',help='Without this flag, preview only')
    p.add_argument('--recover',action='store_true',help='Preview/restore the previous code after an interrupted update')
    p.add_argument('--allow-downgrade',action='store_true',help='Autorise explicitement une version source plus ancienne')
    a=p.parse_args()
    try:
        if a.recover:result=recover_update(a.destination,apply=a.apply)
        else:result=apply_update(a.source,a.destination,allow_downgrade=a.allow_downgrade) if a.apply else plan_update(a.source,a.destination,allow_downgrade=a.allow_downgrade)
    except (OSError,ValueError,RuntimeError) as e:p.exit(1,'Update refused: '+str(e)+'\n')
    if not a.recover:
        # O8: listed after the preview or the completed update, outside both; read-only, never blocking (no decision taken on blocking).
        result=dict(result,UserQueues=installation_queues(a.destination))
    try:print(json.dumps(result,ensure_ascii=False,indent=2))
    except UnicodeEncodeError:print(json.dumps(result,ensure_ascii=True,indent=2))  # O8: console code page: stays valid JSON.
    print_queue_lines(result.get('UserQueues'))  # O8: after the JSON, on stderr; stdout stays parseable JSON.
if __name__=='__main__':main()
