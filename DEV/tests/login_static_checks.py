#!/usr/bin/env python3
"""RC8: specific XAML input contracts, not a Windows rendering test.

The two templates no longer live in one file. The main window template is wad/Pesto-Shell.xaml, loaded
at runtime by Pesto-Core.ps1; the login template is the [xml]$lxaml here-string of Show-LoginWindow in
wad/Pesto-Authentication.ps1. Reading only Pesto-Core.ps1 matched neither, and this checker then returned
after a single FAIL: all of the XAML contracts below silently stopped running.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from ps_lexical import functions
P='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
X='http://schemas.microsoft.com/winfx/2006/xaml'
NS={'p':P,'x':X}
NAME='{'+X+'}Name'
KEY='{'+X+'}Key'
SHELL='Pesto-Shell.xaml'
AUTH='Pesto-Authentication.ps1'
CORE='Pesto-Core.ps1'
LOGIN=re.compile(r'(?ms)^\s*\[xml\]\$lxaml\s*=\s*@"\r?\n(.*?)^"@')
VERSION=re.compile(r"(?m)^\$script:Pesto_VERSION = '([^']+)'")

def checks(shell: str, login_source: str) -> list[dict]:
    results=[]
    def check(name, condition):
        results.append({'name':name,'status':'PASS' if condition else 'FAIL'})
    def missing(detail):
        return [{'name':'Main/login templates exist','status':'FAIL','detail':detail}]
    login=LOGIN.search(login_source)
    if login is None:
        return missing('modèle [xml]$lxaml absent de '+AUTH)
    try:
        tree=ET.fromstring(shell)
    except ET.ParseError as e:
        return missing(SHELL+' illisible: '+str(e))
    try:
        login_tree=ET.fromstring(login[1])
    except ET.ParseError as e:
        return missing('modèle de connexion illisible dans '+AUTH+': '+str(e))
    resources=tree.find('p:Window.Resources',NS)
    if resources is None:
        return missing(SHELL+' sans Window.Resources: styles implicites introuvables')
    for typ in ('TextBox','PasswordBox'):
        styles=[s for s in resources.findall('p:Style',NS) if s.get('TargetType')==typ and not s.get(KEY)]
        check(f'{typ}: implicit style is unique',len(styles)==1)
        if len(styles)!=1:continue
        style=styles[0]
        props={s.get('Property'):s.get('Value') for s in style.findall('p:Setter',NS)}
        hosts=[n for n in style.iter() if n.get(NAME)=='PART_ContentHost']
        check(f'{typ}: one standard ScrollViewer content host',len(hosts)==1 and hosts[0].tag=='{'+P+'}ScrollViewer')
        for h in hosts:
            check(f'{typ}: content host has no duplicate outer spacing',h.get('Margin','0') in ('0','0,0','0,0,0,0'))
            check(f'{typ}: no forced height or clipped maximum on host',not any(k in h.attrib for k in ('Height','MaxHeight')))
        chrome=[n for n in style.iter() if n.tag=='{'+P+'}Border']
        check(f'{typ}: border does not duplicate padding',all(n.get('Padding','0') in ('0','0,0','0,0,0,0') for n in chrome))
        check(f'{typ}: theme text and caret colors supplied',props.get('Foreground')=='{DynamicResource FgText}' and props.get('CaretBrush')=='{DynamicResource FgText}')
        check(f'{typ}: centered contents',props.get('VerticalContentAlignment')=='Center')
    for name,typ in [('TxtUser','TextBox'),('TxtPwd','PasswordBox')]:
        nodes=[n for n in login_tree.iter() if n.get(NAME)==name]
        check(f'{name}: correct native control',len(nodes)==1 and nodes[0].tag=='{'+P+'}'+typ)
        if len(nodes)!=1:continue
        n=nodes[0]
        check(f'{name}: height can grow','Height' not in n.attrib and 'MaxHeight' not in n.attrib)
        check(f'{name}: adequate minimum size',float(n.get('MinHeight','0'))>=44 and float(n.get('FontSize','0'))>=14)
        check(f'{name}: vertical alignment explicit',n.get('VerticalContentAlignment')=='Center')
        check(f'{name}: hover help retained',bool(n.get('ToolTip')) and n.get('ToolTipService.ShowOnDisabled')=='True')
    check('Login remains scrollable on a small display',any(n.tag=='{'+P+'}ScrollViewer' and n.get('VerticalScrollBarVisibility')=='Auto' for n in login_tree.iter()))
    check('No remaining doubled input margin in the source','x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"' not in shell+login_source)
    return results

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--wad',type=Path,help='default: <root>/wad')
    ap.add_argument('--report',type=Path)
    a=ap.parse_args();root=a.root.resolve();wad=a.wad or root/'wad'
    shell=(wad/SHELL).read_bytes().decode('utf-8-sig');auth=(wad/AUTH).read_bytes().decode('utf-8-sig')
    # The reported version is the product's, not a constant copied here: it already drifted once
    # (this report said 17.0-RC9 while $script:Pesto_VERSION is '1.0'). Exactly one declaration.
    versions=VERSION.findall((wad/CORE).read_bytes().decode('utf-8-sig'))
    version=versions[0] if len(versions)==1 else 'unknown'
    r=checks(shell,auth)
    # Lexical validation of the new Windows test, never execution on Linux.
    test=root/'tests/Run-LoginTests.ps1';test_text=test.read_text(encoding='utf-8-sig')
    funcs=functions(test_text)
    r.append({'name':'Targeted Windows test lexical delimiters','status':'PASS','functions':len(funcs)})
    r.append({'name':'Targeted test extracts XAML without executing Pesto','status':'PASS' if 'XamlReader' in test_text and 'Invoke-Expression' not in test_text and '[scriptblock]::Create' not in test_text else 'FAIL'})
    r.append({'name':'Targeted test includes viewport measurement and negative control','status':'PASS' if all(x in test_text for x in ('ViewportHeight','DesiredSize.Height','LegacyPadding','GetRectFromCharacterIndex','Clear()')) else 'FAIL'})
    # Each mutant names the file it must change: the two templates live in different files now.
    mutations=(
        ('Reintroduce double padding in text and password templates',SHELL,lambda s:s.replace('x:Name="PART_ContentHost" Margin="0"','x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"')),
        ('Force fixed login text height',AUTH,lambda s:s.replace('x:Name="TxtUser" MinHeight="44"','x:Name="TxtUser" Height="40"')),
        ('Force fixed password height',AUTH,lambda s:s.replace('x:Name="TxtPwd" MinHeight="44"','x:Name="TxtPwd" Height="40"')),
        ('Remove content host contract',SHELL,lambda s:s.replace('x:Name="PART_ContentHost"','x:Name="MissingContentHost"')),
    )
    negative=[]
    for name,fname,mutate in mutations:
        pair={SHELL:shell,AUTH:auth}
        mutated=dict(pair);mutated[fname]=mutate(pair[fname])
        applied=mutated[fname]!=pair[fname]
        bad=[x['name'] for x in checks(mutated[SHELL],mutated[AUTH]) if x['status']=='FAIL'] if applied else []
        negative.append({'name':name,'file':fname,'applied':applied,'detected':bool(bad),'failed_checks':bad})
    failed=sum(x['status']=='FAIL' for x in r)
    report={'version':version,'utc':dt.datetime.now(dt.timezone.utc).isoformat(),
            'sources_sha256':{n:hashlib.sha256((wad/n).read_bytes()).hexdigest() for n in (SHELL,AUTH)},
            'scope':'XAML contracts and lexical checks. No WPF rendering or PowerShell execution.',
            'summary':{'checks':len(r),'passed':len(r)-failed,'failed':failed},'checks':r,
            'negative_controls':negative}
    out=a.report or root/'tests/login-static-report.json';out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for c in r:print(c['status'],c['name']+('' if c['status']=='PASS' else ' : '+c.get('detail','')))
    for n in negative:
        if not n['detected']:print('NEGATIVE MISSED',n['name'],'sur',n['file'],'(mutation appliquée: '+str(n['applied'])+')')
    print(json.dumps(report['summary']),'; injected defects detected:',sum(x['detected'] for x in negative),'/',len(negative))
    return 1 if failed or not all(x['detected'] for x in negative) else 0
if __name__=='__main__':raise SystemExit(main())
