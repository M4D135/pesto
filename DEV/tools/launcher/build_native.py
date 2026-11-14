#!/usr/bin/env python3
"""Offline LLVM build of the native x64 launcher, no Windows SDK needed.
Uses only Python stdlib plus installed clang and lld-link. Does not run Pesto.
"""
import argparse, datetime, json, os, pathlib, shutil, struct, subprocess, tempfile, hashlib, re, sys
HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parent.parent
sys.path.insert(0,str(ROOT/"tools"))
from release_version import VERSION, FILE_VERSION, VERSION_WORDS
from refresh_manifest import runtime_files, safe_file, _is_link_or_junction

def pad(data): return data+b'\0'*((-len(data))%4)
def wstr(text): return (text+'\0').encode('utf-16le')
def resource(typ, ident, payload):
    head=struct.pack('<HHHH',0xffff,typ,0xffff,ident)+struct.pack('<IHHII',0,0x1030,0x409,0,0)
    return struct.pack('<II',len(payload),len(head)+8)+head+pad(payload)
def vernode(key, val=b'', kids=b'', kind=1, chars=None):
    content=pad(b'\0'*6+wstr(key))+val
    if kids: content=pad(content)+kids
    return struct.pack('<HHH',len(content), (len(val)//2 if kind else len(val)) if chars is None else chars,kind)+content[6:]
def version_info():
    values={'CompanyName':'Pesto Project','FileDescription':'Pesto (launcher)', 'FileVersion':FILE_VERSION,'InternalName':'Pesto', 'OriginalFilename':'Pesto.exe','ProductName':'Pesto', 'ProductVersion':VERSION}
    strings=b''.join(pad(vernode(k,wstr(v))) for k,v in values.items())
    table=vernode('040904B0',kids=strings)
    stringfile=vernode('StringFileInfo',kids=pad(table))
    translation=vernode('Translation',struct.pack('<HH',0x409,1200),kind=0)
    varfile=vernode('VarFileInfo',kids=pad(translation))
    fixed=struct.pack('<13I',0xfeef04bd,0x10000,*VERSION_WORDS,*VERSION_WORDS,0x3f,0,0x40004,1,0,0,0)
    return vernode('VS_VERSION_INFO',fixed,pad(stringfile)+pad(varfile),kind=0)
def make_resources():
    # RES null header then manifest, the supplied icon group, and version data.
    data=struct.pack('<IIHHHHIHHII',0,32,0xffff,0,0xffff,0,0,0,0,0,0)
    data+=resource(24,1,(HERE/'Pesto.manifest').read_bytes())
    icon=(ROOT/'wad/Pesto.ico').read_bytes();reserved,typ,count=struct.unpack_from('<HHH',icon)
    if reserved or typ!=1: raise ValueError('Invalid icon')
    group=struct.pack('<HHH',0,1,count)
    for i in range(count):
        width,height,colors,res,planes,bits,n,off=struct.unpack_from('<BBBBHHII',icon,6+16*i)
        blob=icon[off:off+n]
        if len(blob)!=n: raise ValueError('Truncated icon')
        data+=resource(3,i+1,blob)
        group+=struct.pack('<BBBBHHIH',width,height,colors,res,planes,bits,n,i+1)
    data+=resource(14,1,group)+resource(16,1,version_info())
    return data


def runtime_header():
    paths=runtime_files(ROOT)
    if _is_link_or_junction(HERE/'pesto_runtime.h'):
        raise ValueError('Generated header must not be a link or junction')
    rows=[]; description=[]
    for rel in paths:
        if rel=='Pesto.exe': continue
        p=safe_file(ROOT,rel)
        digest=hashlib.sha256(p.read_bytes()).digest()
        description.append(rel+'|'+digest.hex())
        path=rel.replace('/','\\\\')
        rows.append('{L"'+path+'",{'+','.join('0x%02x'%b for b in digest)+'}}')
    (HERE/'pesto_runtime.h').write_text('/* Generated from reviewed runtime bytes. Rebuild after editing code. */\n'
        'typedef struct {const unsigned short *name;unsigned char hash[32];} PestoRuntime;\n'
        '#define PESTO_RUNTIME_COUNT '+str(len(rows))+'\n'
        'static const PestoRuntime pesto_runtime[PESTO_RUNTIME_COUNT]={\n'+',\n'.join(rows)+'\n};\n' +
        'static const volatile char pesto_runtime_description[]=\"PESTO_BINDING_V1\\n\"\n'+
        '\n'.join('\"'+line+'\\n\"' for line in description)+'\n\"PESTO_BINDING_END\";\n')

def build(out):
    runtime_header()

    clang=shutil.which('clang');lld=shutil.which('lld-link')
    if not clang or not lld: raise RuntimeError('clang and lld-link must be installed; no automatic download.')
    exports={
        'KERNEL32':['ReadFile','GetModuleFileNameW','GetWindowsDirectoryW','GetFullPathNameW','GetFileAttributesW','GetCommandLineW','LocalFree','GetLastError','FormatMessageW','CreateFileW','CreateDirectoryW','WriteFile','CreateProcessW','WaitForSingleObject','GetExitCodeProcess','CloseHandle','ExitProcess','CreateMutexW'],
        'USER32':['MessageBoxW'], 'SHELL32':['CommandLineToArgvW']}
    out=out.resolve();out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='pesto-launcher-') as tmp:
        tmp=pathlib.Path(tmp);libs=[]
        for dll,names in exports.items():
            definition=tmp/(dll+'.def');definition.write_text('LIBRARY '+dll+'.dll\nEXPORTS\n'+'\n'.join(names)+'\n')
            lib=tmp/(dll+'.lib');subprocess.run([lld,'/lib','/machine:x64','/def:'+str(definition),'/out:'+str(lib)],check=True);libs.append(str(lib))
        obj=tmp/'Pesto.obj';res=tmp/'Pesto.res';res.write_bytes(make_resources())
        subprocess.run([clang,'--target=x86_64-pc-windows-msvc','-std=c11','-Os','-ffreestanding','-fno-builtin','-fno-stack-protector','-mno-stack-arg-probe','-fshort-wchar','-Wall','-Wextra','-Werror','-c',str(HERE/'Pesto-launcher.c'),'-o',str(obj)],check=True)
        subprocess.run([lld,'/nologo','/machine:x64','/entry:PestoEntry','/subsystem:windows,6.02','/nodefaultlib','/dynamicbase','/highentropyva','/nxcompat','/Brepro','/out:'+str(out),str(obj),str(res),*libs],check=True)
    record=write_build_record(out,clang,lld)
    print('Compiled:',out, out.stat().st_size,'bytes (not executed)')
    print('Toolchain:',record['Clang'],'|',record['Lld'])

RECORD=HERE/'last-build.json'
INPUTS=('tools/launcher/Pesto-launcher.c','tools/launcher/pesto_runtime.h','tools/launcher/pesto_sha256.h','tools/launcher/pesto_verify.h','tools/launcher/Pesto.manifest','wad/Pesto.ico','tools/version.json')
def tool_version(exe):
    r=subprocess.run([exe,'--version'],capture_output=True,text=True)
    return ((r.stdout or r.stderr).strip().splitlines() or ['unknown'])[0]
def write_build_record(out,clang,lld):
    # Build proof: the EXE is not reproducible across LLVM versions, so the toolchain is part of its identity.
    record={'Schema':1,'Version':VERSION,'FileVersion':FILE_VERSION,'Utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'Clang':tool_version(clang),'Lld':tool_version(lld),'Exe':out.name,'Size':out.stat().st_size,
        'SHA256':hashlib.sha256(out.read_bytes()).hexdigest(),
        'Inputs':{rel:hashlib.sha256((ROOT/rel).read_bytes()).hexdigest() for rel in INPUTS},'WindowsExecution':'NOT_RUN'}
    if out==(ROOT/'Pesto.exe').resolve():RECORD.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    return record
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path,default=ROOT/'Pesto.exe');a=p.parse_args();build(a.output)
