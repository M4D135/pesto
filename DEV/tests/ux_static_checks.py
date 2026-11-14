#!/usr/bin/env python3
"""Interface source and XAML checks: main window wad/Pesto-Shell.xaml, engine wad/Pesto-Core.ps1 and the
components it dot-sources. Standard library only. NOT WPF or PowerShell execution."""
from __future__ import annotations
import argparse, datetime as dt, hashlib, json, re, sys, xml.etree.ElementTree as ET
from pathlib import Path
from ps_lexical import functions, tokens

P='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
X='http://schemas.microsoft.com/winfx/2006/xaml'
NS={'p':P,'x':X}
N='{'+X+'}Name';K='{'+X+'}Key'
TEMPLATE=re.compile(r'(?ms)^\s*\[xml\]\$(\w+)\s*=\s*@([\'\"])\s*\n(.*?)^\2@')
COMPONENT=re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")
COLOR=re.compile(r'#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})')

def read_theme_palettes(text):
    """Palettes of the literal $script:Themes, read as TEXT: nothing is evaluated.
    Only nested tables of quoted '#RRGGBB' / '#AARRGGBB' strings are accepted; anything else raises ValueError."""
    starts=list(re.finditer(r'(?m)^[ \t]*\$script:Themes[ \t]*=[ \t]*@\{',text))
    if len(starts)!=1:raise ValueError('$script:Themes assignment missing or ambiguous ('+str(len(starts))+')')
    opening=starts[0].end()-1
    if ('{',opening,opening+1) not in tokens(text):raise ValueError('$script:Themes is not code (comment or string)')
    n=len(text);key_re=re.compile(r"[A-Za-z_][A-Za-z0-9_]*|'(?:[^']|'')*'");value_re=re.compile(r"'([^']*)'")
    def skip(i):
        while i<n:
            if text[i] in ' \t\r\n;':i+=1
            elif text[i]=='#':
                j=text.find('\n',i);i=n if j<0 else j+1
            else:break
        return i
    def table(i,depth):
        out={}
        while True:
            i=skip(i)
            if i>=n:raise ValueError('Unterminated $script:Themes table')
            if text[i]=='}':return out,i+1
            k=key_re.match(text,i)
            if not k:raise ValueError('Non-literal key in $script:Themes near: '+text[i:i+40])
            key=k[0][1:-1].replace("''","'") if k[0].startswith("'") else k[0]
            i=skip(k.end())
            if not text.startswith('=',i):raise ValueError('Missing = after key '+key)
            i=skip(i+1)
            if depth==0:
                if not text.startswith('@{',i):raise ValueError('Palette is not a literal table: '+key)
                value,i=table(i+2,1)
            else:
                v=value_re.match(text,i)
                if not v or not COLOR.fullmatch(v[1]):raise ValueError('Colour is not a literal #RRGGBB or #AARRGGBB string: '+key)
                value,i=v[1],v.end()
            if key.lower() in {x.lower() for x in out}:raise ValueError('Duplicate key: '+key)
            out[key]=value
    return table(starts[0].end(),0)[0]

def argb(color):
    c=color.strip().upper();return '#FF'+c[1:] if len(c)==7 else c

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--source',type=Path,help='Engine core (default: wad/Pesto-Core.ps1)')
    parser.add_argument('--shell',type=Path,help='Main window XAML (default: wad/Pesto-Shell.xaml)')
    parser.add_argument('--report',type=Path)
    a=parser.parse_args();root=a.root.resolve();wad=root/'wad'
    path=a.source or wad/'Pesto-Core.ps1';shell_path=a.shell or wad/'Pesto-Shell.xaml'
    def read(p):return p.read_bytes().decode('utf-8-sig').replace('\r\n','\n')
    raw=path.read_bytes();s=raw.decode('utf-8-sig').replace('\r\n','\n')
    shell_raw=shell_path.read_bytes();shell=shell_raw.decode('utf-8-sig').replace('\r\n','\n')
    # Components dot-sourced by the core, always read from wad (also when --source is a copy elsewhere).
    texts={'Pesto-Core.ps1':s};missing_components=[]
    for name in COMPONENT.findall(s):
        if name in texts:continue
        if (wad/name).is_file():texts[name]=read(wad/name)
        else:missing_components.append(name)
    ff={};duplicates={}
    for fname,text in texts.items():
        for n,(x,y) in functions(text).items():
            if n in ff:duplicates.setdefault(n,[ff[n][0]]).append(fname)
            else:ff[n]=(fname,x,y)
    allsrc='\n'.join(texts.values())
    checks=[];metrics={}
    def require(test,msg):
        if not test:raise AssertionError(msg)
    def check(name,fn):
        try:checks.append(dict(name=name,status='PASS',detail=fn()))
        except Exception as e:checks.append(dict(name=name,status='FAIL',detail=str(e)))
    def block(n):
        if n not in ff:raise AssertionError('Function missing from the engine and its components: '+n)
        f,x,y=ff[n];return texts[f][x:y]
    def code_words(t):return {t[x:y] for k,x,y in tokens(t) if k=='word'}
    templates={};template_errors=[]
    def add_template(label,text):
        try:templates[label]=ET.fromstring(text)
        except ET.ParseError as e:template_errors.append(label+': '+str(e))
    add_template('Pesto-Shell.xaml',shell)
    if (wad/'Pesto-Join.xaml').is_file():add_template('Pesto-Join.xaml',read(wad/'Pesto-Join.xaml'))
    else:template_errors.append('Pesto-Join.xaml: missing')
    for fname,text in texts.items():
        for m in TEMPLATE.finditer(text):add_template(fname+':'+str(text.count('\n',0,m.start())+1)+':$'+m[1],m[3])
    if 'Pesto-Shell.xaml' not in templates:raise SystemExit('Main window XAML unreadable: '+'; '.join(template_errors))
    tree=templates['Pesto-Shell.xaml'];parents={c:e for e in tree.iter() for c in e}
    def kind(e):return e.tag.rsplit('}',1)[-1] if isinstance(e.tag,str) else ''
    def in_template(e):
        while e in parents:
            e=parents[e]
            if kind(e) in ('ControlTemplate','DataTemplate','ItemsPanelTemplate'):return True
        return False
    names={e.get(N):e for e in tree.iter() if e.get(N) and not in_template(e)}
    resources=tree.find('p:Window.Resources',NS)
    keys={e.get(K) for e in resources if e.get(K)}
    public=[e.get(N) for e in tree.iter() if e.get(N) and not in_template(e)]
    ui=[n for n in ff if 'PestoUx' in n]
    login=[l for l in templates if l.startswith('Pesto-Authentication.ps1:') and l.endswith(':$lxaml')]
    versions=re.findall(r"(?m)^\$script:Pesto_VERSION = '([^']+)'",s)
    metrics.update(public_names=len(names),ui_functions=len(ui),xml_templates=len(templates),engine_files=len(texts))
    def components():
        require(not missing_components,'Dot-sourced components missing: '+str(missing_components))
        require(not duplicates,'Functions defined in several files: '+str(duplicates))
        return {'files':sorted(texts),'functions':len(ff)}
    check('Engine components are present and define each function once',components)
    def version():
        require(len(versions)==1,'Engine version missing or declared several times: '+str(versions))
        title=tree.get('Title','')
        require(re.search(r'(?<![\w.])Pesto '+re.escape(versions[0])+r'(?![\w.])',title) is not None,'Main window title does not show the engine version: '+title)
        return {'version':versions[0],'title':title}
    check('Engine version is declared once and shown in the main window title',version)
    def well_formed():
        require(not template_errors,'Malformed or missing XML templates: '+str(template_errors))
        require(kind(tree)=='Window' and resources is not None,'Main window root or resources missing')
        require(len(login)==1,'Login template missing or ambiguous: '+str(login))
        return {'templates':sorted(templates)}
    check('XML templates are present and well formed',well_formed)
    check('Public XAML names are unique',lambda:require(len(public)==len(set(public)),'Duplicate public name'))
    def bound():
        m=re.search(r'(?ms)^\$names = (.*?)^foreach \(\$n in \$names\)',s);require(m is not None,'No core binding list')
        main_items=re.findall(r"'([^']+)'",m[1])
        m2=re.search(r"\$names=@\(([^)]*)\)",block('Initialize-PestoSuiteUI'));require(m2 is not None,'No suite binding list')
        suite_items=re.findall(r"'([^']+)'",m2[1])
        lookups=set(re.findall(r"\$Win\.FindName\('([^']+)'\)",allsrc))
        dup=sorted({x for x in main_items if main_items.count(x)>1}|{x for x in suite_items if suite_items.count(x)>1})
        require(not dup,'Duplicate bound names: '+str(dup))
        unknown=sorted((set(main_items)|set(suite_items)|lookups)-set(public))
        require(not unknown,'Bound or looked-up names outside the public main window scope: '+str(unknown))
        return {'bound_core':len(main_items),'bound_suite':len(suite_items),'literal_lookups':len(lookups),'public':len(public)}
    check('Every bound control is a public main window element, without template-part confusion',bound)
    def references():
        missing=[]
        for e in tree.iter():
            for value in e.attrib.values():
                for key in re.findall(r'\{(?:Static|Dynamic)Resource\s+([^{}]+)\}',value):
                    if key not in keys:missing.append(key)
        require(not missing,'Unresolved resource keys: '+str(sorted(set(missing))))
        return {'explicit_keys':len(keys)}
    check('All referenced explicit style and brush keys exist',references)
    def resource_order():
        seen=set()
        for item in resources:
            for e in item.iter():
                for value in e.attrib.values():
                    for key in re.findall(r'\{StaticResource\s+([^{}]+)\}',value):
                        require(key in seen,'Forward StaticResource in resource dictionary: '+key)
            if item.get(K):seen.add(item.get(K))
    check('No forward StaticResource lookup in the resource dictionary',resource_order)
    def targets():
        styles={e.get(K):e for e in resources if kind(e)=='Style' and e.get(K)}
        for e in tree.iter():
            m=re.fullmatch(r'\{StaticResource ([^}]+)\}',e.get('Style',''))
            if m and m[1] in styles:
                require(styles[m[1]].get('TargetType')==kind(e),'Style/element type mismatch: '+m[1])
    check('Explicit styles match their target element types',targets)
    interactive={'Button','CheckBox','ComboBox','TextBox','PasswordBox','DataGrid','RichTextBox','MenuItem','TreeView','Expander','TabItem','GridSplitter'}
    # Historical scope: main window, dialogs declared in the core, login dialogs (moved to Pesto-Authentication.ps1).
    # Other component dialogs set part of their help at run time and are not covered by this static rule.
    help_scope=[l for l in templates if l=='Pesto-Shell.xaml' or l.startswith(('Pesto-Core.ps1:','Pesto-Authentication.ps1:'))]
    def help_fields():
        count=0;gaps=[]
        for name in help_scope:
            w=templates[name];wp={c:p for p in w.iter() for c in p}
            for e in w.iter():
                p=e;templated=False
                while p in wp:
                    p=wp[p]
                    if kind(p) in ('ControlTemplate','DataTemplate','ItemsPanelTemplate'):templated=True;break
                if kind(e) not in interactive or templated:continue
                count+=1;label=name+':'+str(e.get(N) or e.get('Content') or e.get('Header') or kind(e))
                if not(e.get('ToolTip') or e.find('p:'+kind(e)+'.ToolTip',NS) is not None):gaps.append('No tooltip: '+label)
                if not e.get('AutomationProperties.HelpText'):gaps.append('No HelpText: '+label)
                if e.get('ToolTipService.ShowOnDisabled')!='True':gaps.append('Disabled tooltip absent: '+label)
        metrics['interactive_elements_with_help']=count
        require(not gaps,'; '.join(gaps))
        return {'controls':count,'templates':len(help_scope),'scope':'Explicit source metadata, not runtime accessibility certification'}
    check('Interactive elements of the main window, core and login dialogs have tooltips, HelpText and disabled help',help_fields)
    check('Tooltip style wraps and lasts 30 seconds on controls',lambda:require('Property="MaxWidth" Value="380"' in shell and 'TextWrapping="Wrap"' in shell and 'ToolTipService.ShowDuration="30000"' in shell,'Tooltip layout policy missing'))
    for typ,part in [('ComboBox','PART_Popup'),('ComboBox','PART_EditableTextBox'),('TextBox','PART_ContentHost'),('PasswordBox','PART_ContentHost'),('TabControl','PART_SelectedContentHost')]:
        def part_check(typ=typ,part=part):
            found=[e for e in resources.iter() if kind(e)=='ControlTemplate' and e.get('TargetType')==typ]
            require(any(any(c.get(N)==part for c in e.iter()) for e in found),f'{typ} missing {part}')
        check('WPF named part contract '+typ+'/'+part,part_check)
    check('Editable ComboBox retains its textbox visibility trigger',lambda:require('TargetName="PART_EditableTextBox" Property="Visibility" Value="Visible"' in shell,'Editable part remains hidden'))
    check('ComboBox and queue retain virtualization settings',lambda:require('VirtualizingPanel.VirtualizationMode' in shell and 'EnableRowVirtualization' in shell and 'EnableColumnVirtualization' in shell,'Virtualization configuration missing'))
    def palette():
        data=read_theme_palettes(s)
        require('Light' in data and 'Dark' in data,'Light/Dark palette missing: '+str(sorted(data)))
        light=data['Light']
        for mode,colors in data.items():
            require(set(colors)==set(light),'Theme key mismatch '+mode+'/Light: '+str(sorted(set(colors)^set(light))))
        brushes={e.get(K):e for e in resources if kind(e)=='SolidColorBrush' and e.get(K)}
        absent=sorted(set(light)-set(brushes));require(not absent,'Palette keys without a SolidColorBrush in the main window resources: '+str(absent))
        stray=sorted(set(brushes)-set(light));require(not stray,'Main window brushes not driven by the palettes (Set-Theme leaves them unchanged): '+str(stray))
        differ=sorted(k for k in light if argb(brushes[k].get('Color',''))!=argb(light[k]))
        require(not differ,'Main window default brushes differ from the Light palette: '+str(differ))
        return {'themes':sorted(data),'colors_per_theme':len(light),'source':'$script:Themes in Pesto-Core.ps1 (text, not executed)'}
    check('Both complete color palettes match the core and the main window resources',palette)
    def state_rings():
        # X5: in high contrast, AccentSoft is the window colour; the keyboard-highlighted list item, the selected tab and the
        # current menu button get a ring instead. The ring is an overlay (no child, no background, not hit-testable) so the
        # layout never moves, and its brushes are fully transparent in every regular palette: Light and Dark look unchanged.
        rings={'HcStateRing':'Highlight','HcSelStateRing':'HighlightText'}
        for mode,colors in read_theme_palettes(s).items():
            for key in rings:
                require(key in colors,'Ring colour missing from palette '+mode+': '+key)
                require(argb(colors[key])[1:3]=='00','Ring visible outside high contrast: '+mode+'.'+key+'='+colors[key])
        roles=dict(re.findall(r"\b(\w+)='(\w+)'",block('ConvertTo-PestoHighContrastPalette')))
        for key,role in rings.items():require(roles.get(key)==role,'High-contrast role of '+key+' must be '+role+', got '+str(roles.get(key)))
        expected=[('Button','ButtonState',{('Tag','Selected')},'HcStateRing'),('TabItem','InnerTabState',{('IsSelected','True')},'HcStateRing'),
                  ('ComboBoxItem','ComboItemState',{('IsHighlighted','True')},'HcStateRing'),
                  ('ComboBoxItem','ComboItemState',{('IsHighlighted','True'),('IsSelected','True')},'HcSelStateRing')]
        setters=[]
        for t in (e for e in resources.iter() if kind(e)=='ControlTemplate'):
            tp={c:p for p in t.iter() for c in p}
            for trig in t.iter():
                if kind(trig)=='Trigger':cond={(trig.get('Property'),trig.get('Value'))}
                elif kind(trig)=='MultiTrigger':cond={(c.get('Property'),c.get('Value')) for c in trig.iter() if kind(c)=='Condition'}
                else:continue
                for st in trig:
                    if kind(st)=='Setter' and st.get('TargetName'):setters.append((t.get('TargetType'),st.get('TargetName'),frozenset(cond),st.get('Property'),st.get('Value')))
            for name in {r for _,r,_,_ in expected}:
                ring=next((e for e in t.iter() if e.get(N)==name),None)
                if ring is None:continue
                label=t.get('TargetType')+'/'+name
                require(kind(ring)=='Border' and ring.get('BorderThickness')=='2' and ring.get('IsHitTestVisible')=='False' and len(ring)==0,'Ring is not a 2 px overlay without content or hit testing: '+label)
                require(not {'BorderBrush','Background','Margin','Padding'}&set(ring.attrib),'Ring brush, background or spacing set outside its triggers: '+label)
                host=tp.get(ring);require(host is not None and kind(host)=='Grid' and list(host).index(ring)==len(host)-1 and len(host)>=2,'Ring is not the last layer over the chrome: '+label)
        for typ,name,cond,brush in expected:
            require((typ,name,frozenset(cond),'BorderBrush','{DynamicResource '+brush+'}') in setters,'State without its high-contrast ring: '+typ+'/'+name+' when '+str(sorted(cond))+' needs '+brush)
        ring_names={r for _,r,_,_ in expected}
        stray=sorted(str(x) for x in setters if x[1] in ring_names and x[4] not in {'{DynamicResource '+k+'}' for k in rings} and x[3]!='Opacity')
        require(not stray,'Ring painted with a brush visible in Light/Dark: '+str(stray))
        users=sorted({kind(e)+'.'+a for e in tree.iter() for a,v in e.attrib.items() if re.search(r'\{DynamicResource (?:'+'|'.join(rings)+r')\}',v) and not (kind(e)=='Setter' and e.get('TargetName') in ring_names)})
        require(not users,'Ring brushes used outside the ring setters: '+str(users))
        return {'states':len(expected),'brushes':sorted(rings),'scope':'Static source; the visible result needs a Windows high-contrast capture'}
    check('High-contrast state rings (X5): transparent overlays in Light/Dark, selection colours only in high contrast',state_rings)
    def theme_before_login():
        require("Get-PestoAppearanceValue 'Theme'" in block('Initialize-PestoAppearance'),'Theme preference not read at appearance initialisation')
        call=s.find('Initialize-PestoAppearance -OwnerSid');applied=s.find('$Win.Resources[$key]=New-Brush $script:Themes[$script:CurrentTheme][$key]')
        login_call=s.find('$authRoute=Get-PestoAuthenticationRoute')
        require(min(call,applied,login_call)>=0,'Appearance initialisation, theme application or login route missing')
        require(call<applied<login_call,'Theme restored too late')
    check('Theme preference is loaded and applied before the login call',theme_before_login)
    check('Login and programmatic OU dialog inherit the main theme resources',lambda:require('$window.Resources=$Win.Resources' in block('Show-LoginWindow') and '$w.Resources=$Win.Resources' in block('Show-OUBrowser'),'Dialog does not inherit styles'))
    check('Login error and progress have flexible heights',lambda:require('SizeToContent="Height"' in block('Show-LoginWindow') and 'x:Name="LoginFeedback" Visibility="Collapsed"' in block('Show-LoginWindow') and 'TextWrapping="Wrap"' in block('Show-LoginWindow'),'Fixed clipped login message area'))
    check('OU tree and selection buttons expose explicit help',lambda:require(all(f'${n}.ToolTip=' in block('Show-OUBrowser') for n in ('tree','ok','cl')),'Programmatic dialog help missing'))
    check('Interface projection calls the canonical rename/site rule',lambda:require('Get-PestoRenameMoveDecision' in code_words(block('Get-PestoUxSnapshot')),'Duplicated decision logic'))
    check('Same-site preview keeps current OU instead of proposed OU',lambda:require("$futureOU=if(-not $InDomain -or ($decision.Valid -and $decision.Move)){$TargetOU}else{$CurrentOU}" in block('Get-PestoUxSnapshot'),'Preview destination can be misleading'))
    check('Preview distinguishes draft from execution results',lambda:require('Brouillon du formulaire, pas un résultat' in shell,'Draft/result label missing'))
    check('Operation mode and reboot intent are explicit',lambda:require('MODE RÉEL : écritures après confirmation' in s and 'Redémarrage : non demandé' in s and 'SIMULATION : aucune mutation réelle' in s,'Mode or reboot ambiguity'))
    check('UI projection never writes safety flags or enables execution',lambda:require(not re.search(r'\$(?:script:)?MutationUncertain\s*=|\$BtnRun\.IsEnabled\s*=',block('Update-PestoUx')+block('Get-PestoUxSnapshot')),'UI projection overrides a safety gate'))
    def mutations():
        forbidden={'Rename-Computer','Move-ADObject','Add-Computer','Restart-Computer','Go','Run-Queue','Add-Or-UpdateRow','Start-PestoAsyncOperation','Invoke-PestoElevatedLocalChange'}
        for name in ui:
            bad=code_words(block(name))&forbidden;require(not bad,'Mutation or arbitrary worker in '+name+': '+str(bad))
        return {'functions_audited':len(ui),'scope':'Direct lexical calls only, not a runtime information-flow proof'}
    check('New presentation functions do not call mutation entry points',mutations)
    check('UI timers use named script-bound delegates',lambda:require(all('${function:'+n+'}' in block('Initialize-PestoUx') for n in ('Invoke-PestoUxRefreshTick','Invoke-PestoUxComputerLookupTick')),'Anonymous/unbound timer callback'))
    check('No private closure module in the new UI functions',lambda:require(all('.GetNewClosure' not in block(n) for n in ui),'Private closure regression'))
    def event_references():
        found=re.findall(r'\$\{function:([^}]+)\}',block('Initialize-PestoUx'))
        require(not set(found)-set(ff),'Missing event function: '+str(set(found)-set(ff)))
        return {'delegate_references':len(found)}
    check('All named UI event delegates exist',event_references)
    def typing_invalidates():
        b=block('Request-PestoUxComputerLookup');reset=b.find('Reset-ConfigFields -KeepName')
        require(reset>=0,'Source identity not invalidated')
        triggers=[t for t in ('$script:PestoUxLookupTimer.Start()','Select-PCName','Invoke-PestoUxReadComputer') if t in b]
        for t in triggers:require(b.find(t)>reset,'Read requested before invalidation: '+t)
        return {'automatic_read':bool(triggers)}
    check('Typing invalidates the source identity before any read',typing_invalidates)
    check('Lookup immediately disables adding and cancels stale probe generation',lambda:require(all(x in block('Request-PestoUxComputerLookup') for x in ('$BtnAdd.IsEnabled=$false','$script:PCProbeGeneration=[int]$script:PCProbeGeneration+1',"Stop-PestoAsyncOperation 'PCProbe'")),'Lookup invalidation incomplete'))
    check('Enter reads a computer, never executes or adds',lambda:require('Invoke-PestoUxReadComputer' in block('Invoke-PestoUxSourceKey') and not code_words(block('Invoke-PestoUxSourceKey'))&{'Add-Or-UpdateRow','Run-Queue'},'Unsafe Enter behavior'))
    check('TextChanged is wired to source invalidation',lambda:require('$TxtPCName.Add_TextChanged({ Request-PestoUxComputerLookup })' in s,'TextChanged does not invalidate the source'))
    check('F1/Ctrl navigation shortcuts never execute a queue',lambda:require('Key]::F1' in block('Invoke-PestoUxKey') and not code_words(block('Invoke-PestoUxKey'))&{'Run-Queue','Add-Or-UpdateRow','Restart-Computer'},'Unsafe shortcut handler'))
    check('Closing the main window stops both UI timers',lambda:require('Stop-PestoUx' in s[s.index('$Win.Add_Closed({'):s.index('$Win.Add_Closing({')] and '$timer.Stop()' in block('Stop-PestoUx'),'UI timers left alive'))
    check('Compact/wide layout reuses existing controls',lambda:require('[Windows.Controls.Grid]::SetRow($PreviewPanel,1)' in block('Update-PestoUxLayout') and '[Windows.Controls.Grid]::SetRow($PreviewPanel,0)' in block('Update-PestoUxLayout'),'Responsive layout not reversible'))
    def navigation():
        b=block('Set-PestoUxPage')
        require('Rename=0;Names=1;Settings=2;Log=3;Home=4;History=5;Help=6' in b,'Legacy navigation index regression')
        m=re.search(r'\$map=@\{([^}]*)\}',b);require(m is not None,'Page map missing')
        mapping={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',m[1])}
        tabs=[e for e in names['MainTabs'] if kind(e)=='TabItem']
        headers={'Rename':'Renommer','Names':'Noms disponibles','Settings':'Paramètres','Log':'Journal','Home':'Accueil','History':'Historique','Help':'Aide','Join':'Ajouter au domaine'}
        for page,index in mapping.items():
            require(index<len(tabs),'Page outside MainTabs: '+page)
            require(tabs[index].get('Header')==headers.get(page),'Page '+page+' opens tab '+str(index)+' ('+str(tabs[index].get('Header'))+')')
        return {'pages':len(mapping),'tabs':len(tabs)}
    check('Original navigation indexes preserved and mapped to the right main window tabs',navigation)
    def simple_columns():
        cols=list(names['Grid'].find('p:DataGrid.Columns',NS));visible=[c for c in cols if c.get('Visibility','Visible')=='Visible']
        require(len(visible)==6,'Simple queue must expose six columns, got '+str(len(visible)))
        require(len(cols)>len(visible),'Detailed columns removed')
        metrics['queue_columns']=len(cols)
        return {'visible':len(visible),'retained':len(cols)}
    check('Queue starts with six columns and retains the technical columns',simple_columns)
    check('Technical column toggle changes visibility, not queue contents',lambda:require('Binding.Path.Path' in block('Set-PestoUxTechnicalColumns') and 'SortMemberPath' in block('Set-PestoUxTechnicalColumns') and '$col.Visibility=' in block('Set-PestoUxTechnicalColumns') and '.Rows' not in block('Set-PestoUxTechnicalColumns'),'Index-based or destructive toggle'))
    check('History read is local, bounded and domain-scoped',lambda:require(all(x in block('Update-PestoUxHistory') for x in ("'history-v1.json'",'2MB','$data.Schema -ne 1','$data.Domain -ine $script:DOMAINE','-First 100')),'History bounds/scope missing'))
    check('History page cannot relaunch a completed action',lambda:require(not code_words(block('Update-PestoUxHistory'))&{'Run-Queue','Add-Or-UpdateRow','Import-QueueCsv'},'History has mutation capability'))
    for f in ('tests/Run-UxTests.ps1','tests/Run-AllTests.ps1'):
        def native_syntax(f=f):
            content=(root/f).read_bytes();require(content.startswith(b'\xef\xbb\xbf'),'BOM required by PS5.1')
            text=content.decode('utf-8-sig');return {'lexical_tokens':len(tokens(text)),'native_execution':False}
        check(f+' encoding and conservative lexical structure',native_syntax)
    def test_closure():
        text=(root/'tests/Run-UxTests.ps1').read_text(encoding='utf-8-sig');load=re.search(r'\$load=@\((.*?)\)\s*foreach',text,re.S)
        require(load is not None,'Test load list missing');loaded=set(re.findall(r"'([^']+)'",load[1]));doubles=set(functions(text));missing={}
        require(not loaded-set(ff),'Tests load a missing engine function: '+str(sorted(loaded-set(ff))))
        require(not loaded&doubles,'Loaded engine function also redefined by the test: '+str(sorted(loaded&doubles)))
        for name in loaded:
            refs=code_words(block(name))&set(ff);outside=refs-loaded-doubles
            if outside:missing[name]=sorted(outside)
        require(not missing,'Missing isolated test dependencies: '+str(missing))
        require("$script:PREFIXE='111301'" in text,'Fixture prefix missing')
        require('RC6_UI_TOKENS' not in text and 'Pesto-Shell.xaml' in text,'UI test does not read the current main window and palettes')
        return {'loaded_engine_functions':len(loaded),'files':sorted({ff[n][0] for n in loaded}),'windows_test_cases':len(re.findall(r"(?m)^\s*Case '",text)),'executed':False}
    check('Native UI fixture has complete lexical function dependencies',test_closure)
    check('UI test runner launches STA and preserves failure status',lambda:require('-STA ' in (root/'TEST_INTERFACE.cmd').read_text(encoding='utf-8') and 'exit /b %Pesto_TEST_EXIT%' in (root/'TEST_INTERFACE.cmd').read_text(encoding='utf-8'),'Broken STA/exit contract'))
    check('Master runner includes the new isolated UI suite',lambda:require("'Run-UxTests.ps1'" in (root/'tests/Run-AllTests.ps1').read_text(encoding='utf-8-sig'),'UI suite omitted'))
    def dev_pack():
        text=(root/'tools/package_distribution.py').read_text(encoding='utf-8')
        trees=re.search(r'DEV_TREES\s*=\s*\(([^)]*)\)',text);suffixes=re.search(r'DEV_SUFFIXES\s*=\s*\{([^}]*)\}',text)
        require(trees is not None and '"tests"' in trees[1],'tests folder not shipped in the DEV pack')
        require(suffixes is not None and '".ps1"' in suffixes[1] and '".py"' in suffixes[1],'Test scripts not shipped in the DEV pack')
        require('source.glob("TEST*.cmd")' in text and (root/'TEST_INTERFACE.cmd').is_file(),'UI test launcher not shipped in the DEV pack')
    check('DEV pack ships the UI suite and its launcher',dev_pack)
    bad=sum(c['status']=='FAIL' for c in checks)
    report={'version':versions[0] if len(versions)==1 else 'unknown','utc':dt.datetime.now(dt.timezone.utc).isoformat(),
      'source_sha256':hashlib.sha256(raw).hexdigest(),'shell_sha256':hashlib.sha256(shell_raw).hexdigest(),
      'scope':'STATIC SOURCE ONLY. No native PowerShell parsing, WPF loading, screenshots, Windows testing or AD execution.',
      'totals':{'checks':len(checks),'passed':len(checks)-bad,'failed':bad},'metrics':metrics,'checks':checks}
    target=a.report or root/'tests/ux-static-report.json';target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for c in checks:print(c['status']+' '+c['name']+(' : '+str(c['detail']) if c['status']=='FAIL' else ''))
    print(json.dumps(report['totals']));return int(bool(bad))
if __name__=='__main__':sys.exit(main())
