"""Find synthetic secret canaries in textual evidence without printing their values.
This is not general DLP or OCR. Images/binary artifacts are reported unexamined.
Text must be UTF-8 or BOM-marked UTF-16. NUL-containing text, including ambiguous
BOM-less UTF-16, is reported unexamined rather than guessed or counted as clean.
"""
from pathlib import Path
import argparse,json,os,stat
TEXT={'.json','.txt','.log','.csv','.xml','.html','.md','.yml','.yaml','.ps1'}


def _masked_path(relative,canaries):
    # Every replacement shortens the text (canaries are at least eight chars).
    # Repeat in case a replacement joins fragments into another known canary.
    while True:
        previous=relative
        for canary in sorted(canaries,key=len,reverse=True):relative=relative.replace(canary,'[***]')
        if relative==previous:return relative


def _report(examined,hits,unexamined,io_errors=0):
    return {'schema':1,'textFilesExamined':examined,'hits':hits,'unexamined':unexamined,'ioErrors':io_errors,'status':'INCOMPLETE' if io_errors else 'FAIL' if hits else 'NO_CANARY_FOUND_IN_EXAMINED_TEXT','limit':'Only UTF-8 and BOM-marked UTF-16 text without NULs is examined. Images require visual/OCR review; absence of known canaries is not proof that arbitrary secrets are absent.'}


def scan(root,canaries):
    if not canaries or any(not isinstance(c,str) or len(c)<8 for c in canaries):raise ValueError('Synthetic canaries must be at least eight characters')
    root=Path(root)
    try:
        # Check before resolving: resolve() would hide a linked root from the scan.
        mode=root.lstat().st_mode
        if stat.S_ISLNK(mode):raise ValueError('Linked evidence root refused')
        if not stat.S_ISDIR(mode):raise ValueError('Evidence root must be a directory')
        root=root.resolve(strict=True)
    except OSError:
        return _report(0,[],['.'],1)
    hits=[];unexamined=[];examined=0;io_errors=[]
    def unread(path):
        try:relative=Path(path).relative_to(root).as_posix() if path is not None else '.'
        except (TypeError,ValueError):relative='.'
        unexamined.append(_masked_path(relative,canaries));io_errors.append(True)
    # Unlike Path.rglob, walk's callback exposes directory enumeration failures.
    # Never serialize the exception text, which can contain a sensitive path.
    try:
        for directory,dirs,files in os.walk(root,onerror=lambda error:unread(error.filename),followlinks=False):
            dirs.sort()
            for name in sorted(dirs+files):
                path=Path(directory)/name
                relative=_masked_path(path.relative_to(root).as_posix(),canaries)
                try:
                    info=path.lstat()
                    if stat.S_ISLNK(info.st_mode):raise ValueError('Linked evidence refused')
                    if stat.S_ISDIR(info.st_mode):continue
                    if not stat.S_ISREG(info.st_mode) or path.suffix.lower() not in TEXT or info.st_size>16*1024*1024:
                        unexamined.append(relative);continue
                    raw=path.read_bytes()
                except OSError:
                    unread(path);continue
                try:text=raw.decode('utf-16') if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else raw.decode('utf-8-sig')
                except UnicodeError:unexamined.append(relative);continue
                # BOM-less UTF-16 can look like UTF-8 with interleaved NULs.
                if '\x00' in text:unexamined.append(relative);continue
                examined+=1
                count=sum(text.count(canary) for canary in canaries)
                if count:hits.append({'path':relative,'matches':count})
    except OSError:
        unread(None)
    return _report(examined,sorted(hits,key=lambda hit:hit['path']),sorted(unexamined),len(io_errors))


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path);p.add_argument('--canary-file',type=Path,required=True);a=p.parse_args(argv)
    try:
        # Keep the input outside evidence so it is not an intentional hit.
        if a.canary_file.resolve().is_relative_to(a.root.resolve()):raise ValueError('Canary input must be outside evidence')
        report=scan(a.root,a.canary_file.read_text(encoding='utf-8-sig').splitlines())
    except (OSError,UnicodeError):
        report=_report(0,[],['.'],1)
    except ValueError:
        report=_report(0,[],['.']);report['status']='INVALID_INPUT'
    print(json.dumps(report,indent=2))
    return 2 if report['status'] in ('INCOMPLETE','INVALID_INPUT') else 1 if report['hits'] else 0


if __name__=='__main__':raise SystemExit(main())
