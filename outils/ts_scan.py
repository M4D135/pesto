#!/usr/bin/env python3
"""Scan PowerShell sources with tree-sitter-powershell; list ERROR/MISSING nodes."""
import sys, pathlib
import tree_sitter_powershell as tsp
from tree_sitter import Language, Parser
LANG=Language(tsp.language())
def scan(path, show=True, ctx=110):
    data=pathlib.Path(path).read_bytes()
    if data[:3]==b'\xef\xbb\xbf': data=data[3:]
    tree=Parser(LANG).parse(data)
    out=[]
    def walk(n):
        if n.type=='ERROR' or n.is_missing:
            out.append(n); return
        for c in n.children: walk(c)
    walk(tree.root_node)
    if show:
        for n in out:
            s=n.start_byte; e=n.end_byte
            line=n.start_point[0]+1
            snippet=data[max(0,s-40):min(len(data),s+ctx)].decode('utf-8','replace').replace('\n','\\n').replace('\r','')
            kind='MISSING '+n.type if n.is_missing else 'ERROR'
            print(f"  {pathlib.Path(path).name}:{line}:{n.start_point[1]+1} [{kind} len={e-s}] ...{snippet}")
    return out
if __name__=='__main__':
    total=0
    for p in [a for a in sys.argv[1:] if a!='-q']:
        r=scan(p, show='-q' not in sys.argv)
        total+=len(r)
        print(f"{p}: {len(r)} error nodes")
    print('TOTAL',total)
