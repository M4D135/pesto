#!/usr/bin/env python3
"""Exploratory symbol/call lint for the Pesto engine (tree-sitter based)."""
import sys, pathlib, re, json, collections
import tree_sitter_powershell as tsp
from tree_sitter import Language, Parser

LANG = Language(tsp.language())
COMMON = {'erroraction','warningaction','verbose','debug','errorvariable','warningvariable','outvariable','outbuffer',
          'pipelinevariable','informationaction','informationvariable','whatif','confirm'}

def text(src, n): return src[n.start_byte:n.end_byte].decode('utf-8', 'replace')

def parse(path):
    data = pathlib.Path(path).read_bytes()
    if data[:3] == b'\xef\xbb\xbf': data = data[3:]
    return data, Parser(LANG).parse(data)

def walk(n):
    stack = [n]
    while stack:
        x = stack.pop()
        yield x
        stack.extend(reversed(x.children))

def params_of(src, fn):
    names = []; advanced = False
    for c in walk(fn):
        if c is not fn and c.type == 'function_statement':
            continue
    # only direct param block / declaration (not nested functions)
    def direct(n, depth=0):
        for c in n.children:
            if c.type == 'function_statement': continue
            if c.type in ('param_block', 'function_parameter_declaration'):
                yield c
            elif c.type in ('script_block',):
                yield from direct(c, depth+1)
    for pb in direct(fn):
        for c in walk(pb):
            if c.type == 'script_parameter':
                for v in c.children:
                    if v.type == 'variable':
                        names.append(text(src, v).lstrip('$'))
            if c.type == 'type_identifier' and text(src, c).lower() in ('cmdletbinding', 'parameter'):
                advanced = True
        break
    return names, advanced

def regex_functions(src_text):
    """Fallback discovery: function NAME { param(...) ...  or  function NAME(...) {"""
    out = {}
    for m in re.finditer(r'(?m)^[ \t]*function[ \t]+([A-Za-z0-9_-]+)[ \t]*(\(|\{)?', src_text):
        name = m.group(1); i = m.end()
        params = []; adv = False
        # find param block: either immediately "(" after name, or "param(" as first token in body
        rest = src_text[m.start():m.start()+6000]
        pm = re.search(r'function[ \t]+[A-Za-z0-9_-]+[ \t]*\(', rest)
        start = None
        if pm and pm.start() == 0:
            start = pm.end()-1
        else:
            body = re.search(r'\{', rest)
            if body:
                after = rest[body.end():]
                # skip comments / attributes / whitespace
                k = 0
                while True:
                    mm = re.match(r'\s+|<#.*?#>|#[^\n]*|\[[A-Za-z]+(\([^\)]*\))?\]', after[k:], re.S)
                    if not mm: break
                    if mm.group(0).startswith('['): adv = True
                    k += mm.end()
                if after[k:k+5].lower() == 'param':
                    j = after.find('(', k)
                    if j >= 0 and after[k+5:j].strip() == '': start = body.end()+j
        if start is not None:
            depth = 0; j = start; cur = []
            in_s = None
            while j < len(rest):
                c = rest[j]
                if in_s:
                    if c == in_s: in_s = None
                elif c in "'\"": in_s = c
                elif c in '([{': depth += 1
                elif c in ')]}':
                    depth -= 1
                    if depth == 0: break
                j += 1
            block = rest[start:j+1]
            if re.search(r'\[(Parameter|CmdletBinding)', block, re.I): adv = True
            # top-level variables: depth 1 of the paren block, not after '=' (defaults)
            depth = 0; in_s = None; k = 0; expect = True
            while k < len(block):
                c = block[k]
                if in_s:
                    if c == in_s: in_s = None
                elif c in "'\"": in_s = c
                elif c in '([{': depth += 1
                elif c in ')]}': depth -= 1
                elif c == ',' and depth == 1: expect = True
                elif c == '=' and depth == 1: expect = False
                elif c == '$' and depth == 1 and expect:
                    mm = re.match(r'\$([A-Za-z_][A-Za-z0-9_]*)', block[k:])
                    if mm: params.append(mm.group(1)); expect = False; k += mm.end()-1
                k += 1
        line = src_text.count('\n', 0, m.start())+1
        out.setdefault(name.lower(), []).append((line, name, params, adv))
    return out

def collect(files):
    defs = collections.defaultdict(list)   # lower name -> [(file,line,name,params,advanced,nested)]
    calls = []                             # (file,line,cmdname,[params],enclosing function or None)
    funcrefs = []                          # ${function:Name}
    for f in files:
        src, tree = parse(f)
        fname = pathlib.Path(f).name
        def visit(n, enclosing, depth):
            if n.type == 'function_statement':
                name = None
                for c in n.children:
                    if c.type == 'function_name': name = text(src, c)
                ps, adv = params_of(src, n)
                defs[name.lower()].append((fname, n.start_point[0]+1, name, ps, adv, depth > 0))
                for c in n.children: visit(c, name, depth+1)
                return
            if n.type == 'command':
                cname = None; plist = []
                for c in n.children:
                    if c.type == 'command_name': cname = text(src, c)
                    if c.type == 'command_elements':
                        for e in c.children:
                            if e.type == 'command_parameter':
                                plist.append(text(src, e))
                if cname:
                    calls.append((fname, n.start_point[0]+1, cname, plist, enclosing))
            for c in n.children: visit(c, enclosing, depth)
        visit(tree.root_node, None, 0)
        # merge regex fallback (functions inside grammar ERROR regions, one-line param blocks)
        for key, items in regex_functions(src.decode('utf-8', 'replace')).items():
            for line, name, ps, adv in items:
                known = [d for d in defs.get(key, []) if d[0] == fname and d[1] == line]
                if known:
                    d = known[0]
                    if len(ps) > len(d[3]) or (adv and not d[4]):
                        defs[key][defs[key].index(d)] = (d[0], d[1], d[2], ps if len(ps) > len(d[3]) else d[3], d[4] or adv, d[5])
                else:
                    defs[key].append((fname, line, name, ps, adv, True))
        for m in re.finditer(rb'\$\{function:([A-Za-z0-9_-]+)\}', src):
            line = src.count(b'\n', 0, m.start())+1
            funcrefs.append((fname, line, m.group(1).decode()))
    return defs, calls, funcrefs

def main():
    files = sys.argv[1:]
    defs, calls, funcrefs = collect(files)
    checked=sum(1 for c in calls if c[2].lower() in defs); withp=sum(1 for c in calls if c[2].lower() in defs and c[3])
    print('calls to engine functions:',checked,'with named params:',withp)
    print('functions defined:', sum(len(v) for v in defs.values()), 'unique:', len(defs))
    # duplicates at top level
    for k, v in sorted(defs.items()):
        tops = [d for d in v if not d[5]]
        if len(tops) > 1:
            print('DUPLICATE top-level:', v[0][2], [(d[0], d[1]) for d in tops])
    # ${function:} references
    for f, line, name in funcrefs:
        if name.lower() not in defs:
            print(f'UNDEFINED function reference: {f}:{line} ${{function:{name}}}')
    # parameter checks
    unknown_cmds = collections.Counter()
    for f, line, cname, plist, enc in calls:
        key = cname.lower()
        if key not in defs:
            unknown_cmds[cname] += 1
            continue
        allowed = set(); adv = False
        for d in defs[key]:
            allowed |= {p.lower() for p in d[3]}; adv = adv or d[4]
        for p in plist:
            pn = p.lstrip('-').rstrip(':').lower()
            if not pn: continue
            if pn in allowed: continue
            pref = [a for a in allowed if a.startswith(pn)]
            if len(pref) == 1: continue
            if adv and (pn in COMMON or any(c.startswith(pn) for c in COMMON)): continue
            print(f'UNKNOWN PARAM: {f}:{line} {cname} {p}  (defined: {sorted(allowed)})')
    json.dump({k: v for k, v in unknown_cmds.most_common()}, open('unknown_cmds.json', 'w'), indent=1)
    print('distinct command names not defined in engine:', len(unknown_cmds))

if __name__ == '__main__':
    main()
