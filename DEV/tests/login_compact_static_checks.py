"""RC12 compact login contracts on the Pesto 1.0 sources: login XAML and preference functions in
wad/Pesto-Authentication.ps1 (Show-LoginWindow), main window wad/Pesto-Shell.xaml, palettes $script:Themes of
wad/Pesto-Core.ps1. Source and XML only: no native PowerShell parse, no WPF, Windows or AD run.
A negative control counts as detected only when its mutation applies and the check it aims at, named in MUTANTS,
fails; other failing checks are listed, never counted.
Without --report, the run rewrites the versioned tests/login-compact-static-report.json. That file is a regenerated
artifact, not a reference: it holds this checker's output at its last run (UTC time, SHA-256 of those of the three
sources that exist, checks, negative controls, removed checks; file and check names only, no machine path) and changes
on every run. Regenerate it with this script after a source or check change and commit it with that change; otherwise
pass --report outside the repository."""
from pathlib import Path
import argparse, re, json, hashlib, datetime as dt
import xml.etree.ElementTree as ET
from ps_lexical import functions, tokens
from ux_static_checks import read_theme_palettes
P='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
X='http://schemas.microsoft.com/winfx/2006/xaml'
NS={'p':P}
NAME='{'+X+'}Name';KEY='{'+X+'}Key'
AUTH='Pesto-Authentication.ps1';CORE='Pesto-Core.ps1';SHELL='Pesto-Shell.xaml'
COMPONENT=re.compile(r"(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+'(Pesto-[A-Za-z]+\.ps1)'\)")
LOGIN=re.compile(r'(?ms)^\s*\[xml\]\$lxaml\s*=\s*@"\r?\n(.*?)^"@')
FORM=('TxtUser','TxtPwd','ChkRememberUser','BtnOk','BtnCancel','BtnWindows')
# RC11 login helpers (renamed GP -> Pesto), RC12 changed login functions, RC13 authentication helpers,
# plus the two domain-identity diagnostics added by 44feb34 (called from Pesto-Directory.ps1, listed in
# $script:PestoWorkerCoreNames, and exercised by tests/Run-StabilisationTests.ps1).
LOGIN_FUNCTIONS=('Get-PestoLoginPreferencePath','ConvertFrom-PestoLoginPreference','Get-PestoLoginPreference','Save-PestoLoginPreference','Set-PestoLoginFeedback','Invoke-PestoLoginForget','Set-PestoLoginWindowBounds','Show-LoginWindow','Set-PestoLoginBusy','Complete-PestoLoginError','Complete-PestoLoginSuccess','Start-PestoLoginAttempt')
AUTH_FUNCTIONS=('Get-PestoIdentityChangeReason','Get-PestoWindowsAuthIdentity','Get-PestoExplicitCredentialRequirement','Set-PestoAuthenticatedSnapshot','Complete-PestoWindowsConnectionError','Complete-PestoWindowsConnectionSuccess','Start-PestoWindowsConnection','Show-PestoWindowsConnectionWindow','Get-PestoDomainIdentityWarning','Add-PestoDomainIdentityCause','Get-PestoDirectoryIdentitySource')
OTHER_FUNCTIONS=('Invoke-PestoWindowsLocalRename','Get-PestoAuthenticationRoute','Get-PestoStateDirectory','Write-PestoAtomicText','Invoke-PestoThemeToggle')
REMOVED=[
  {'name':'RC11 functions preserved outside declared login and RC13 authentication changes','reason':'tests/rc11-login-baseline.json hashes the monolithic RC11 engine with GP-prefixed names (GP_17_WAD_RC11.zip); the engine is now renamed Pesto and split into wad/Pesto-*.ps1 components, so no baseline function can match. Negative control "Business engine unexpectedly changed" removed with it.'},
  {'name':'Uploaded config unchanged byte-for-byte','reason':'wad/cfg.json is now a local configuration ignored by Git (identical to tools/cfg.template.json); the uploaded GP configuration of the baseline is no longer in the tree.'},
  {'name':'Only declared login and RC13 authentication helpers added','reason':'Replaced: set equality against the RC11 engine baseline is impossible after the split; now scoped to the declared login/authentication functions and the authentication component.'},
]

def load(wad):
    core=(wad/CORE).read_text('utf-8-sig');files={CORE:core,SHELL:(wad/SHELL).read_text('utf-8-sig')}
    for n in COMPONENT.findall(core)+[AUTH]:
        if (wad/n).is_file():files[n]=(wad/n).read_text('utf-8-sig')
    return files

def assess(files):
    out=[]
    def require(c,msg):
        if not c:raise AssertionError(msg)
        return True
    def check(name,fn):
        try:
            r=fn()
            if not isinstance(r,dict) and not r:raise AssertionError('condition not met')
            row={'name':name,'passed':True}
            if isinstance(r,dict):row['detail']=r
        except Exception as e:
            row={'name':name,'passed':False,'detail':(str(e) if isinstance(e,AssertionError) else type(e).__name__+': '+str(e)) or 'condition not met'}
        out.append(row)
    core=files.get(CORE,'');order=[CORE]+[n for n in dict.fromkeys(COMPONENT.findall(core)) if n!=CORE]
    missing=[n for n in order if n not in files];defs={};lexical=[]
    for fname in order:
        if fname in missing:continue
        try:
            for n,(a,b) in functions(files[fname]).items():defs.setdefault(n.lower(),[]).append((fname,a,b))
        except ValueError as e:lexical.append(fname+': '+str(e))
    def body(n):
        d=defs.get(n.lower(),[])
        if len(d)!=1:raise AssertionError(n+' defined '+str(len(d))+' time(s): '+str([x[0] for x in d]))
        f,a,b=d[0];return files[f][a:b]
    check('Engine components readable; Pesto-Authentication.ps1 dot-sourced by the core',lambda:require(not missing and not lexical and AUTH in order,'Missing components '+str(missing)+'; lexical errors '+str(lexical)+'; authentication component dot-sourced: '+str(AUTH in order)) and {'files':len(order)})
    show=body('Show-LoginWindow') if len(defs.get('show-loginwindow',[]))==1 else ''
    m=LOGIN.search(show);tree=None
    if m:
        try:tree=ET.fromstring(m[1])
        except ET.ParseError:tree=None
    check('Login XAML exists',lambda:require(tree is not None and len(LOGIN.findall(files.get(AUTH,'')))==1,'No single well-formed [xml]$lxaml template in Show-LoginWindow of '+AUTH))
    if tree is None:return out
    xaml=m[1];names={e.get(NAME):e for e in tree.iter() if e.get(NAME)}
    try:shell=ET.fromstring(files[SHELL]);res=shell.find('p:Window.Resources',NS)
    except (KeyError,ET.ParseError):shell=res=None
    check('No maximize or resize in login XAML',lambda:tree.get('ResizeMode')=='NoResize' and tree.get('WindowState')=='Normal')
    check('Compact width and content-sized height',lambda:tree.get('Width')=='460' and tree.get('SizeToContent')=='Height' and 'Height' not in tree.attrib and 'MinHeight' not in tree.attrib)
    check('Native title bar, no custom drag imitation',lambda:tree.get('WindowStyle')=='SingleBorderWindow')
    check('Runtime bounds use work area in WPF units',lambda:'SystemParameters]::WorkArea' in body('Set-PestoLoginWindowBounds') and '$Window.MaxHeight=' in body('Set-PestoLoginWindowBounds') and 'ResizeMode]::NoResize' in body('Set-PestoLoginWindowBounds'))
    check('Runtime bounds applied before ShowDialog',lambda:show.index('Set-PestoLoginWindowBounds')<show.index('$window.ShowDialog()'))
    check('Maximized-state guard present',lambda:'$window.Add_StateChanged' in show and '$sender.WindowState=[Windows.WindowState]::Normal' in show)
    check('Short RBP header, not tall marketing banner',lambda:"else{'Compte administrateur requis'}" in show and 'Connexion à Pesto' in xaml and 'Connectez-vous à votre espace' not in xaml)
    check('Feedback collapsed at rest without reserved blank area',lambda:names['LoginFeedback'].get('Visibility')=='Collapsed' and 'Height' not in names['LoginFeedback'].attrib and 'MinHeight' not in names['LoginFeedback'].attrib)
    check('Name/password native and extensible',lambda:names['TxtUser'].tag=='{'+P+'}TextBox' and names['TxtPwd'].tag=='{'+P+'}PasswordBox' and all('Height' not in names[n].attrib and names[n].get('MinHeight')=='44' for n in ('TxtUser','TxtPwd')))
    check('No password literal in XAML',lambda:'Password' not in names['TxtPwd'].attrib)
    interactive=[e for e in tree.iter() if e.tag.rsplit('}',1)[-1] in ('TextBox','PasswordBox','CheckBox','Button')]
    def help_fields():
        gaps=[str(e.get(NAME))+' '+a for e in interactive for a in ('ToolTip','AutomationProperties.HelpText') if not e.get(a)]
        gaps+=[str(e.get(NAME))+' ToolTipService.ShowOnDisabled' for e in interactive if e.get('ToolTipService.ShowOnDisabled')!='True']
        require(not gaps,'Missing help: '+', '.join(gaps))
        return {'controls':len(interactive)}
    check('Help on every interactive control including disabled controls',help_fields)
    def tab_order():
        idx={e.get(NAME):e.get('TabIndex') for e in interactive}
        require(all(n in idx for n in FORM),'Form controls missing or not interactive: '+str([n for n in FORM if n not in idx]))
        require(sorted(int(idx[n] or -1) for n in FORM)==list(range(6)),'Form tab order is not 0..5: '+str({n:idx[n] for n in FORM}))
        extra=[int(v) for n,v in idx.items() if n not in FORM and v is not None]
        require(all(v>5 for v in extra) and len(extra)==len(set(extra)),'Other controls interleave the form tab order: '+str({n:v for n,v in idx.items() if n not in FORM}))
        return {'form':{n:int(idx[n]) for n in FORM},'after_form':sorted(str(n) for n in idx if n not in FORM)}
    check('Distinct keyboard tab order',tab_order)
    check('Enter connects; Escape cancels',lambda:names['BtnOk'].get('IsDefault')=='True' and names['BtnCancel'].get('IsCancel')=='True')
    check('Remember username is opt-in',lambda:names['ChkRememberUser'].get('IsChecked')=='False')
    check('Username preference tied to config/profile and domain',lambda:"'login.json'" in body('Get-PestoLoginPreferencePath') and 'Get-PestoStateDirectory' in body('Get-PestoLoginPreferencePath') and '$Preference.Domain -ine $Domain' in body('ConvertFrom-PestoLoginPreference'))
    check('Boolean opt-in and bounded username validated',lambda:all(x in body('ConvertFrom-PestoLoginPreference') for x in ('RememberUser -isnot [bool]','UserName -isnot [string]','$name.Length -gt 256','[\\x00-\\x1f\\x7f]')))
    check('Stored JSON is username-only allowlist',lambda:bool(re.search(r'\$data=\[ordered\]@\{Schema=1;Domain=\[string\]\$script:DOMAINE;RememberUser=\$true;UserName=\$UserName.Trim\(\)\}',body('Save-PestoLoginPreference'))))
    check('No credential parameter in preference writer',lambda:'param([bool]$RememberUser,[AllowEmptyString()][string]$UserName=' in body('Save-PestoLoginPreference'))
    check('Preference write atomic, no backup retained',lambda:'Write-PestoAtomicText -Path $path -Text' in body('Save-PestoLoginPreference') and '-Backup' not in body('Save-PestoLoginPreference'))
    check('Preference read bounded and symlinks rejected',lambda:'$info.Length -gt 16384' in body('Get-PestoLoginPreference') and 'ReparsePoint' in body('Get-PestoLoginPreference'))
    check('Uncheck wired to immediate forgetting',lambda:'$ui.Remember.Add_Unchecked({Invoke-PestoLoginForget})' in show and 'Save-PestoLoginPreference -RememberUser $false' in body('Invoke-PestoLoginForget') and '[IO.File]::Delete($path)' in body('Save-PestoLoginPreference'))
    check('Remember only after explicit successful AD authentication',lambda:"if($state.PendingMode -eq 'Explicit')" in body('Complete-PestoLoginSuccess') and 'Save-PestoLoginPreference' in body('Complete-PestoLoginSuccess') and 'Save-PestoLoginPreference' not in body('Start-PestoLoginAttempt') and 'Save-PestoLoginPreference' not in body('Complete-PestoLoginError'))
    check('Password cleared on login window closing',lambda:'if($script:PestoLoginUi){$script:PestoLoginUi.Password.Clear()}' in show)
    check('Preference checkbox locked during authentication',lambda:'$ui.Remember' in body('Set-PestoLoginBusy') and '$control.IsEnabled=-not $Busy' in body('Set-PestoLoginBusy'))
    check('Username errors use visible feedback',lambda:'Set-PestoLoginFeedback -ErrorMessage' in body('Start-PestoLoginAttempt') and 'Set-PestoLoginFeedback -ErrorMessage' in body('Complete-PestoLoginError'))
    def shared_theme():
        require('$window.Resources=$Win.Resources' in show,'Login does not take the main window resources')
        require('ControlTemplate' not in xaml,'Login XAML duplicates a control template')
        require("Join-Path $PSScriptRoot 'Pesto-Shell.xaml'" in core,'Core does not load Pesto-Shell.xaml as the main window')
        require(res is not None,'Pesto-Shell.xaml unreadable or without Window.Resources')
        for typ in ('TextBox','PasswordBox'):
            st=[s for s in res.findall('p:Style',NS) if s.get('TargetType')==typ and not s.get(KEY)]
            require(len(st)==1 and any(e.tag=='{'+P+'}ControlTemplate' for e in st[0].iter()),'Shared implicit '+typ+' template missing or ambiguous in Pesto-Shell.xaml')
        return True
    check('Theme shared; no duplicate input templates',shared_theme)
    def palette_keys():
        pal=read_theme_palettes(core)
        require({'Light','Dark'}<=set(pal),'Light/Dark palettes missing: '+str(sorted(pal)))
        require(res is not None,'Pesto-Shell.xaml unreadable or without Window.Resources')
        used=sorted(set(re.findall(r'\{(?:Dynamic|Static)Resource\s+([^{}\s]+)\s*\}',xaml)))
        brushes={e.get(KEY) for e in res if e.tag=='{'+P+'}SolidColorBrush'}
        gaps=[k+' absent from '+w for w,keys in [(SHELL,brushes)]+[('palette '+t,set(c)) for t,c in sorted(pal.items())] for k in used if k not in keys]
        require(used and not gaps,'; '.join(gaps) or 'No shared resource referenced by the login XAML')
        require('${function:Invoke-PestoThemeToggle}' in show and body('Invoke-PestoThemeToggle'),'Login theme button not wired to the engine theme toggle')
        return {'resources':used,'palettes':sorted(pal)}
    check('Login colours resolved by the main window brushes and every palette',palette_keys)
    check('Windows session limitation remains in tooltip',lambda:'renommer un autre PC' in names['BtnWindows'].get('ToolTip',''))
    def declared():
        bad={}
        for n in LOGIN_FUNCTIONS+AUTH_FUNCTIONS+OTHER_FUNCTIONS:
            d=[x[0] for x in defs.get(n.lower(),[])]
            if len(d)!=1 or (n not in OTHER_FUNCTIONS and d!=[AUTH]):bad[n]=d
        own=[n for n,d in defs.items() if any(x[0]==AUTH for x in d)];allowed={n.lower() for n in LOGIN_FUNCTIONS+AUTH_FUNCTIONS}
        require(not bad,'Declared functions missing, duplicated or outside '+AUTH+': '+str(bad))
        require(set(own)<=allowed,'Undeclared functions in '+AUTH+': '+str(sorted(set(own)-allowed)))
        return {'declared':len(LOGIN_FUNCTIONS+AUTH_FUNCTIONS+OTHER_FUNCTIONS)}
    check('Only declared login and RC13 authentication functions, each defined once',declared)
    return out

# (name, mutated file, mutation, check that must fail)
MUTANTS=[
  ('Login maximize enabled',AUTH,lambda t:t.replace('SizeToContent="Height" ResizeMode="NoResize"','SizeToContent="Height" ResizeMode="CanResize"'),'No maximize or resize in login XAML'),
  ('Large fixed-height login returns',AUTH,lambda t:t.replace('Width="460" SizeToContent="Height"','Width="460" Height="700"'),'Compact width and content-sized height'),
  ('Password field added to preference serialization',AUTH,lambda t:t.replace('RememberUser=$true;UserName=$UserName.Trim()}','RememberUser=$true;UserName=$UserName.Trim();Password="BAD"}'),'Stored JSON is username-only allowlist'),
  ('Opt-in enabled by default',AUTH,lambda t:t.replace('Content="Mémoriser uniquement l\'identifiant" IsChecked="False"','Content="Mémoriser uniquement l\'identifiant" IsChecked="True"'),'Remember username is opt-in'),
  ('Remember checkbox left enabled during authentication',AUTH,lambda t:t.replace('$ui.Password,$ui.Remember)','$ui.Password)'),'Preference checkbox locked during authentication'),
  ('Theme button interleaved in the form tab order',AUTH,lambda t:t.replace('x:Name="LoginTheme" Grid.Column="3"','x:Name="LoginTheme" Grid.Column="3" TabIndex="2"'),'Distinct keyboard tab order'),
  ('Login colour missing from a palette',CORE,lambda t:re.sub(r"(?m)^[ \t]*ErrFg='#[0-9A-Fa-f]{6,8}'[ \t]*\r?\n",'',t,count=1),'Login colours resolved by the main window brushes and every palette'),
  ('Shared PasswordBox template no longer implicit',SHELL,lambda t:t.replace('<Style TargetType="PasswordBox">','<Style TargetType="PasswordBox" x:Key="LegacyPasswordBox">',1),'Theme shared; no duplicate input templates'),
  ('Login function duplicated in another component',CORE,lambda t:t+'\nfunction Save-PestoLoginPreference { }\n','Only declared login and RC13 authentication functions, each defined once'),
]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--report',type=Path,help='default: tests/login-compact-static-report.json under --root')
    a=ap.parse_args();root=a.root.resolve();wad=root/'wad'
    files=load(wad);rows=assess(files);base={r['name'] for r in rows if r['passed']}
    for p in (root/'tests/Run-LoginPreferencesTests.ps1',root/'tests/Run-LoginTests.ps1'):
        try:tokens(p.read_text('utf-8-sig'));rows.append({'name':'Conservative lexical delimiters: '+p.name,'passed':True})
        except (OSError,ValueError) as e:rows.append({'name':'Conservative lexical delimiters: '+p.name,'passed':False,'detail':(type(e).__name__+': '+(e.strerror or 'unreadable')+': tests/'+p.name) if isinstance(e,OSError) else str(e)})
    negatives=[]
    for name,fname,mutate,expected in MUTANTS:
        changed=dict(files);changed[fname]=mutate(files.get(fname,''));applied=changed[fname]!=files.get(fname,'')
        hit=[r['name'] for r in assess(changed) if not r['passed'] and r['name'] in base] if applied else []
        negatives.append({'name':name,'file':fname,'applied':applied,'expected_check':expected,'detected':expected in hit,
                          'failed_checks':hit,'other_failed_checks':[n for n in hit if n!=expected]})
    versions=re.findall(r"(?m)^\$script:Pesto_VERSION = '([^']+)'",files[CORE])
    report={'version':versions[0] if len(versions)==1 else 'unknown','utc':dt.datetime.now(dt.timezone.utc).isoformat(),
      'sources_sha256':{n:hashlib.sha256((wad/n).read_bytes()).hexdigest() for n in (AUTH,CORE,SHELL) if (wad/n).is_file()},
      'scope':'Source and XML only; not a native PowerShell parse or Windows/WPF/AD run.',
      'negative_rule':'Detected = the mutation applies and its expected check, passing on the intact sources, fails.','passed':sum(r['passed'] for r in rows),'failed':sum(not r['passed'] for r in rows),
      'checks':rows,'negative_controls':negatives,'removed_checks':REMOVED}
    target=a.report or root/'tests/login-compact-static-report.json';target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for r in rows:print(('PASS' if r['passed'] else 'FAIL'),r['name']+('' if r['passed'] else ' : '+r.get('detail','')))
    for n in negatives:print('NEGATIVE','detected' if n['detected'] else 'MISSED',n['name'],n['failed_checks'],'' if n['detected'] else 'expected: '+repr(n['expected_check'])+('' if n['applied'] else ' (mutation not applied)'))
    print(report['passed'],'passed;',report['failed'],'failed;',sum(n['detected'] for n in negatives),'/',len(negatives),'negative controls detected')
    return int(bool(report['failed']) or not all(n['detected'] for n in negatives))
if __name__=='__main__':raise SystemExit(main())
