#requires -Version 5.1
# Shared libraries are embedded and pinned. No download or compilation at runtime.
function Initialize-PestoCommon {
    param([string]$Root='', [switch]$IncludeWpf)
    if(-not $Root){$Root=$PSScriptRoot}
    $rootPath=[IO.Path]::GetFullPath($Root)
    if($IncludeWpf -and [Environment]::OSVersion.Platform -ne 'Win32NT'){throw 'Les primitives WPF communes exigent Windows.'}
    $ancestor=$rootPath
    while($ancestor){
        $ancestorItem=Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
        if($ancestorItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Chemin lié du socle commun refusé.'}
        $ancestor=[IO.Path]::GetDirectoryName($ancestor)
    }
    $lockPath=Join-Path $rootPath 'common.lock.json'
    $lockItem=Get-Item -LiteralPath $lockPath -Force -ErrorAction Stop
    if($lockItem.Length -gt 65536 -or ($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Manifeste du socle commun invalide.'}
    $lock=Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    if($lock.Schema -ne 1 -or $lock.Version -cne '0.2.0' -or $lock.TargetFramework -cne 'net472' -or
       $lock.Repository -cne 'https://github.com/M4D135/m4d-admin-common' -or $lock.SourceCommit -notmatch '^[a-f0-9]{40}$' -or
       $lock.SourceSHA256 -notmatch '^[a-f0-9]{64}$' -or $lock.SourceDirty -isnot [bool] -or $lock.SourceDirty -or $lock.Consumer -cne 'Pesto'){throw 'Version du socle commun incompatible avec ce paquet.'}
    $required=@('M4D.Admin.Common.Core.dll','M4D.Admin.Common.Query.dll','M4D.Admin.Common.IO.dll','M4D.Admin.Common.Diagnostics.dll')
    $optional='M4D.Admin.Common.Wpf.dll';$allowed=$required+@($optional)
    if(@($lock.Files).Count -notin @($required.Count,($required.Count+1))){throw 'Liste des bibliothèques communes incomplète.'}
    $seen=@{};$checked=@()
    foreach($file in @($lock.Files)){
        $name=[string]$file.Name
        if($name -cnotin $allowed -or $seen.ContainsKey($name) -or [string]$file.SHA256 -notmatch '^[a-f0-9]{64}$'){throw 'Bibliothèque commune inattendue ou répétée.'}
        $seen[$name]=$true;$path=Join-Path $rootPath $name
        $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if($item.Length -ne $file.Bytes -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
           (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ine [string]$file.SHA256){throw ('Bibliothèque commune absente ou modifiée : '+$name)}
        $identity=[Reflection.AssemblyName]::GetAssemblyName($path)
        if($identity.Name -cne [IO.Path]::GetFileNameWithoutExtension($name) -or $identity.Version.ToString() -cne '0.1.1.0'){throw ('Identité de DLL incompatible : '+$name)}
        $checked+=@{Name=$identity.Name;Identity=$identity.FullName;Path=$path;SHA256=[string]$file.SHA256;Load=($name -cne $optional -or $IncludeWpf)}
    }
    foreach($name in $required){if(-not $seen.ContainsKey($name)){throw 'Liste des bibliothèques communes incomplète.'}}
    if($IncludeWpf -and -not $seen.ContainsKey($optional)){throw 'Bibliothèque WPF commune absente de ce paquet.'}
    # Verify the entire bundle before loading any member. Assemblies live for the
    # AppDomain lifetime, so their verified provenance must survive child script
    # scopes too (for example two successive calls through & Invoke-PestoAutoJoin).
    $domain=[AppDomain]::CurrentDomain
    $registryKey='Pesto.Common.VerifiedAssemblies.v1'
    [Threading.Monitor]::Enter($domain)
    try{
        $registry=$domain.GetData($registryKey)
        if($null -eq $registry){
            $registry=@{}
            $domain.SetData($registryKey,$registry)
        }
        if($registry -isnot [hashtable]){throw 'Registre du socle commun invalide.'}
        foreach($entry in $checked){
            $loaded=@($domain.GetAssemblies()|Where-Object {$_.GetName().Name -ceq $entry.Name})
            if($loaded.Count){
                $known=$registry[$entry.Name]
                if($loaded.Count -ne 1 -or $known -isnot [hashtable] -or
                   -not [object]::ReferenceEquals($known.Assembly,$loaded[0]) -or
                   $known.Identity -cne $entry.Identity -or $loaded[0].FullName -cne $entry.Identity -or
                   $known.SHA256 -cne $entry.SHA256 -or $known.Path -ine $entry.Path -or
                   $loaded[0].Location -ine $entry.Path){throw ('Une autre version du socle commun est déjà chargée : '+$entry.Name)}
            }elseif($entry.Load){
                $assembly=[Reflection.Assembly]::LoadFrom($entry.Path)
                if($assembly.FullName -cne $entry.Identity -or $assembly.Location -ine $entry.Path){throw ('Provenance de DLL incompatible : '+$entry.Name)}
                $registry[$entry.Name]=@{Assembly=$assembly;Identity=$entry.Identity;Path=$entry.Path;SHA256=$entry.SHA256}
            }
        }
    }finally{[Threading.Monitor]::Exit($domain)}
}

function Initialize-PestoRuntimeTypes {
    param([string]$Root='')
    $expected='6cd066ec56afb3240d6b493732ea97098c4a4bd77f3a79f2e46517ec3ac13d47' # PESTO_COMPILED_SHA256
    $domain=[AppDomain]::CurrentDomain;$key='Pesto.Runtime.Verified.v1'
    [Threading.Monitor]::Enter($domain)
    try{
        foreach($typeName in @('Pesto.Runtime.AsyncAuditWriter','Pesto.Inventory.CompactIndex','Pesto.NativePipe17','Pesto.NativeShell')){
            $type=$typeName -as [type]
            if($type -and $type.Assembly.GetName().Name -cne 'Pesto.Runtime'){throw 'Un type helper non verifie est deja charge.'}
        }
        $known=$domain.GetData($key)
        if(-not $Root){$Root=if($known){[IO.Path]::GetDirectoryName([string]$known.Path)}else{$PSScriptRoot}}
        if(-not $Root){throw 'Repertoire des helpers verifie absent.'}
        $path=[IO.Path]::GetFullPath((Join-Path $Root 'Pesto.Runtime.dll'))
        $ancestor=$path
        while($ancestor){
            if((Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Chemin lie des helpers refuse.'}
            $ancestor=[IO.Path]::GetDirectoryName($ancestor)
        }
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ine $expected){throw 'Helpers C# modifies : reinstallez le paquet complet.'}
        $identity=[Reflection.AssemblyName]::GetAssemblyName($path)
        if($identity.Name -cne 'Pesto.Runtime' -or $identity.Version.ToString() -cne '1.0.0.0'){throw 'Identite des helpers incompatible.'}
        $loaded=@($domain.GetAssemblies()|Where-Object {$_.GetName().Name -ceq 'Pesto.Runtime'})
        if($loaded.Count){
            if($loaded.Count -ne 1 -or -not $known -or -not [object]::ReferenceEquals($known.Assembly,$loaded[0]) -or
               $known.Path -ine $path -or $known.SHA256 -cne $expected -or $loaded[0].Location -ine $path){throw 'Une autre provenance des helpers est deja chargee.'}
        }else{
            $assembly=[Reflection.Assembly]::LoadFrom($path)
            if($assembly.FullName -cne $identity.FullName -or $assembly.Location -ine $path){throw 'Chargement des helpers incoherent.'}
            $domain.SetData($key,@{Assembly=$assembly;Path=$path;SHA256=$expected})
        }
    }finally{[Threading.Monitor]::Exit($domain)}
}
