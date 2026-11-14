#!/usr/bin/env python3
"""Execute actual C launcher logic against doubles, plus SHA/argument tests.
Linux compiler runner only. This does NOT execute the Windows PE or any AD action.
"""
import argparse,ctypes,hashlib,json,pathlib,random,shutil,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2];HERE=ROOT/'tools/launcher'
def main():
 clang=shutil.which('clang')
 if not clang:raise RuntimeError('clang is required; no download is performed')
 from importlib.util import spec_from_file_location,module_from_spec
 spec=spec_from_file_location('build_native',HERE/'build_native.py');mod=module_from_spec(spec);spec.loader.exec_module(mod);mod.runtime_header()
 report={'Kind':'Linux C execution with mocked Windows APIs','WindowsExecuted':False,'Commands':[],'ShaCases':0}
 with tempfile.TemporaryDirectory(prefix='pesto-native-tests-') as tmp:
  tmp=pathlib.Path(tmp)
  flags=[clang,'-fdeclspec','-fshort-wchar','-ffunction-sections','-fdata-sections','-Wno-ignored-attributes','-Wno-incompatible-pointer-types','-Wl,-dead_strip' if sys.platform=='darwin' else '-Wl,--gc-sections']
  for source,name in [('test_entry.c','entry'),('test_arguments.c','args')]:
   command=flags+[str(HERE/source),'-o',str(tmp/name)];subprocess.run(command,check=True)
  for i in range(48):
   r=subprocess.run([str(tmp/'entry'),str(i),str(ROOT)],text=True,capture_output=True)
   report['Commands'].append({'Name':'entry-'+str(i),'ReturnCode':r.returncode,'Output':r.stdout+r.stderr})
   if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  r=subprocess.run([str(tmp/'args')],text=True,capture_output=True)
  report['Commands'].append({'Name':'arguments','ReturnCode':r.returncode,'Output':r.stdout+r.stderr})
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  wrapper=tmp/'sha.c'
  wrapper.write_text('#include "pesto_sha256.h"\nvoid test_hash(const unsigned char *p,size_t n,size_t step,unsigned char out[32]){PestoSHA s;pesto_sha_init(&s);while(n){size_t q=n<step?n:step;pesto_sha_update(&s,p,q);p+=q;n-=q;}pesto_sha_final(&s,out);}\n')
  library=tmp/'libsha.so'
  subprocess.run([clang,'-shared','-fPIC','-O2','-Wall','-Wextra','-Werror','-I',str(HERE),str(wrapper),'-o',str(library)],check=True)
  fun=ctypes.CDLL(str(library)).test_hash;fun.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_size_t,ctypes.c_void_p];fun.restype=None
  randomizer=random.Random(190930)
  vectors=[b'',b'abc',b'a'*1000000]+[randomizer.randbytes(n) for n in [1,2,7,31,55,56,57,63,64,65,127,128,129,255,256,1024,65535,65536,65537]]
  for data in vectors:
   source=ctypes.create_string_buffer(data)
   for chunk in (1,7,64,65,1024,65536):
    out=ctypes.create_string_buffer(32);fun(source,len(data),chunk,out)
    if out.raw!=hashlib.sha256(data).digest():raise AssertionError('SHA256 mismatch length='+str(len(data)))
    report['ShaCases']+=1
 report['Passed']=True
 output=ROOT/'tests/rc23-native-portable.json';output.write_text(json.dumps(report,indent=2)+'\n')
 print('PASS: 48 C entry scenarios, 9 explicit argument checks, 2000 argument roundtrips, '+str(report['ShaCases'])+' SHA256 cases. No Windows APIs executed.')
if __name__=='__main__':main()
