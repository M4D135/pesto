#requires -Version 5.1
# Analyses de l'instantané uniquement. Aucun appel AD ni réparation.

function Get-PestoCapacityRows {
    param([object[]]$Computers,[object[]]$Catalogue,[string[]]$ReservedNames,[string]$Prefix,$Cancellation)
    if($Prefix -notmatch (Get-PestoFacetPattern Prefix) -or @($Computers).Count -gt 200000 -or @($Catalogue).Count -gt 10000 -or @($ReservedNames).Count -gt 10000){throw 'Périmètre de capacité invalide ou trop volumineux.'}
    $groups=@{};$count=0
    foreach($entry in $Catalogue){
        if($entry.Site -notmatch (Get-PestoFacetPattern Site) -or $entry.Service -notmatch (Get-PestoFacetPattern Service)){continue}
        foreach($type in @((Get-PestoActiveNamingConvention).Types.ToCharArray()|ForEach-Object{[string]$_})){
            $base=New-PestoNameSeries -Type $type -Prefix $Prefix -Site $entry.Site -Service $entry.Service
            $groups[$base]=[pscustomobject]@{InAD=@{};Prepared=@{};Configured=$true}
        }
    }
    foreach($computer in $Computers){
        if(($count++ % 128) -eq 0 -and $Cancellation.Cancelled){throw 'Analyse annulée.'}
        $part=ConvertTo-PestoNameParts ([string]$computer.Name) $Prefix
        if(-not $part){continue}
        if(-not $groups.ContainsKey($part.Base)){$groups[$part.Base]=[pscustomobject]@{InAD=@{};Prepared=@{};Configured=$false}}
        $groups[$part.Base].InAD[$part.Number]=$true
    }
    foreach($name in $ReservedNames){
        $part=ConvertTo-PestoNameParts $name $Prefix;if(-not $part){continue}
        if(-not $groups.ContainsKey($part.Base)){$groups[$part.Base]=[pscustomobject]@{InAD=@{};Prepared=@{};Configured=$false}}
        $groups[$part.Base].Prepared[$part.Number]=$true
    }
    foreach($base in @($groups.Keys|Sort-Object)){
        if($Cancellation.Cancelled){throw 'Analyse annulée.'}
        $g=$groups[$base];$part=ConvertTo-PestoNameParts (New-PestoNameFromSeries $base 1) $Prefix
        $prepared=0;foreach($number in $g.Prepared.Keys){if(-not $g.InAD.ContainsKey($number)){$prepared++}}
        [pscustomobject]@{Site=$part.Site;Service=$part.Service;Type=$part.Label;Origine=$(if($g.Configured){'Catalogue configuré'}else{'Observé / préparé'});Capacite=(Get-PestoNameMaximumNumber);Occupes=$g.InAD.Count;Prepares=$prepared;Libres=((Get-PestoNameMaximumNumber)-$g.InAD.Count-$prepared)}
    }
}

function Get-PestoSiteReviewMap {
    param([object[]]$Metadata,[object[]]$Tags)
    if(@($Metadata).Count -gt 10000 -or @($Tags).Count -gt 2000){throw 'Catalogue de sites trop volumineux.'}
    foreach($site in $Metadata){
        $name=[string]$site.Name
        # Même priorité aux motifs exacts que dans la préparation ; aucun repli deviné ici.
        $exact=@($Tags|Where-Object{[string]$_.Site -ieq $name})
        $found=if($exact.Count){$exact}else{@($Tags|Where-Object{$_.Site -and $name -like [string]$_.Site})}
        $codes=@($found|ForEach-Object{([string]$_.Tag).ToUpperInvariant()}|Where-Object{$_ -match (Get-PestoFacetPattern Site)}|Sort-Object -Unique)
        if($codes.Count -eq 1 -and $site.DN -and $site.Root){
            $guid=[Guid]::Empty
            if([Guid]::TryParse([string]$site.Guid,[ref]$guid) -and $guid -ne [Guid]::Empty){
                [pscustomobject]@{Org=[string]$site.Org;Name=$name;Code=$codes[0];DN=[string]$site.DN;Root=[string]$site.Root;Guid=$guid.ToString()}
            }
        }
    }
}

function Get-PestoConformityRows {
    param([object[]]$Computers,[string]$Prefix,[object[]]$Tags,[object[]]$SiteMetadata=@(),[string]$PreprodOU='',$Cancellation)
    if(@($Computers).Count -gt 200000){throw 'Périmètre de conformité trop volumineux.'}
    $map=@(Get-PestoSiteReviewMap -Metadata $SiteMetadata -Tags $Tags);$count=0;$byCode=@{}
    foreach($site in $map){if(-not $byCode.ContainsKey($site.Code)){$byCode[$site.Code]=[Collections.Generic.List[object]]::new()};$byCode[$site.Code].Add($site)}
    foreach($pc in $Computers){
        if(($count++ % 128) -eq 0 -and $Cancellation.Cancelled){throw 'Analyse annulée.'}
        $name=[string]$pc.Name;$parts=ConvertTo-PestoNameParts $name $Prefix
        $state='Nom non conforme';$reason='La convention de nommage ne correspond pas.';$current='';$target=''
        if($parts){
            $state='Emplacement non vérifié';$reason='Aucune identité d’’OU observée ne permet de conclure.'
            try{
                $current=Get-PestoParentDN ([string]$pc.DistinguishedName)
                if($PreprodOU -and (Test-PestoDNWithinScope $current @($PreprodOU))){$state='Zone de préparation';$reason='Préproduction configurée : aucun déplacement proposé automatiquement.'}
                else{
                    $candidates=@(foreach($site in $byCode[$parts.Site]){if(Test-PestoDNWithinScope $current @($site.Root)){$site}})
                    if($candidates.Count -gt 1){$state='Destination ambiguë';$reason='Plusieurs OU du même périmètre portent ce code. Corrigez les règles avant toute préparation.'}
                    elseif($candidates.Count -eq 1){
                        $target=$candidates[0].DN
                        if(Test-PestoDNWithinScope $current @($target)){$state='Conforme au nom et au site';$reason='Objet dans le site attendu ou une sous-OU de ce site.'}
                        else{$state='Emplacement différent';$reason='Le code du nom et le site AD ne concordent pas dans l’’inventaire. Vérification ciblée requise.'}
                    }
                }
            }catch{$state='Emplacement non vérifié';$reason='DN absent ou format non pris en charge. Aucune conclusion sur l’’emplacement.'}
        }
        [pscustomobject]@{Poste=$name;Etat=$state;Detail=$reason;OU=$current;OUAttendues=$target;Guid=[string]$pc.ObjectGUID}
    }
}

function Get-PestoReviewSource {
    $names=@('ConvertTo-PestoNameParts','New-PestoComputerName','Split-PestoDistinguishedName','Get-PestoParentDN','Test-PestoDNWithinScope','Get-PestoCapacityRows','Get-PestoSiteReviewMap','Get-PestoConformityRows')
    return (@(foreach($name in $names){'function '+$name+' {'+(Get-Command $name -CommandType Function -ErrorAction Stop).Definition+'}'}) -join "`r`n")+(Get-PestoNamingContextSource)
}

function Invoke-PestoReviewWorker {
    param($Request,[string]$Source)
    $ErrorActionPreference='Stop';. ([scriptblock]::Create($Source))
    $clock=[Diagnostics.Stopwatch]::StartNew()
    if($Request.Kind -eq 'capacity'){
        $rows=@(Get-PestoCapacityRows -Computers $Request.Computers -Catalogue $Request.Catalogue -ReservedNames $Request.ReservedNames -Prefix $Request.Prefix -Cancellation $Request.Cancellation)
        $total=$rows.Count;$display=@($rows|Select-Object -First 1000)
        $text="$total combinaison(s) site/service/type observée(s) ou configurée(s).`r`n"+($display|Format-Table -AutoSize|Out-String -Width 220)
    }elseif($Request.Kind -eq 'conformity'){
        $rows=@(Get-PestoConformityRows -Computers $Request.Computers -Prefix $Request.Prefix -Tags $Request.Tags -SiteMetadata $Request.SiteMetadata -PreprodOU $Request.PreprodOU -Cancellation $Request.Cancellation)
        $total=$rows.Count;$summary=$rows|Group-Object Etat|Select-Object @{n='État';e={$_.Name}},Count|Format-Table -AutoSize|Out-String
        $display=@($rows|Where-Object{$_.Etat -ne 'Conforme au nom et au site'}|Select-Object -First 1000)
        $text="$total poste(s) analysé(s).`r`n"+$summary+($display|Format-List|Out-String -Width 200)
    }else{throw 'Analyse non reconnue.'}
    $text="Instantané : $($Request.InventoryUtc)`r`nPérimètre : $($Request.Scope)`r`n`r`n"+$text+"`r`nDétails limités aux 1 000 premières lignes ; compteurs calculés sur tout le périmètre indiqué. Données en cache, pas réservation AD. Aucune réparation ou nouvelle lecture réseau."
    if($text.Length -gt 230000){$text=$text.Substring(0,230000)+"`r`n[Détails tronqués pour la vue]"}
    return [pscustomobject]@{Text=$text;Count=$total;ElapsedMs=$clock.ElapsedMilliseconds;Rows=@($rows|Select-Object -First 10000);InventoryUtc=$Request.InventoryUtc;ConfigStamp=$Request.ConfigStamp}
}

function Start-PestoInventoryReview {
    param($PanelState,$Request)
    $PanelState.Body.Text='Analyse locale en cours. Fermer ce panneau annule uniquement cette lecture du cache.'
    $context=[pscustomobject]@{Panel=$PanelState;Request=$Request}
    $ok=Start-PestoAsyncOperation -Name 'InventoryReview' -ScriptBlock ${function:Invoke-PestoReviewWorker} -ArgumentList @($Request,(Get-PestoReviewSource)) -TimeoutSec 90 -CallbackContext $context `
        -OnSuccess {param($r,$c) Complete-PestoInventoryReview -Result $r -Context $c} `
        -OnError {param($e,$c) Complete-PestoInventoryReview -Failure $e -Context $c}
    if(-not $ok){$PanelState.Body.Text='Analyse non lancée. Une autre lecture est encore active ; réessayez après sa fin.'}
}

function Complete-PestoInventoryReview {
    param($Result,$Failure,$Context)
    if(-not $script:PestoPanelStack -or -not $script:PestoPanelStack.Contains($Context.Panel)){return}
    $panel=$Context.Panel
    if($Failure){$panel.Body.Text='Analyse interrompue : '+(Protect-PestoLogText $Failure.Exception.Message);return}
    if(-not $Result -or [string]$Result.InventoryUtc -cne [string]$script:InventoryUtc -or $Result.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or -not $script:InventoryLoaded){$panel.Body.Text='Le contexte a changé pendant le calcul. Relancez l’’analyse du nouvel inventaire.';return}
    $panel.Body.Text=$Result.Text
    $panel.Result.Data=$Result;$panel.Accept.IsEnabled=$true
    $panel.Hint.Text='Analyse terminée en '+$Result.ElapsedMs+' ms. Ce temps concerne le calcul local, pas une lecture AD.'
    Add-PestoPerformanceSample -Name ('Review-'+$Context.Request.Kind) -Milliseconds $Result.ElapsedMs -Count $Result.Count
}

function Show-PestoInventoryReview {
    param([ValidateSet('capacity','conformity')][string]$Kind)
    if(-not $script:InventoryLoaded){throw 'Chargez volontairement l’’inventaire depuis Noms avant cette analyse.'}
    $reserved=@(foreach($row in @($script:table.Rows)){if($row -and [string]$row.Nouveau_Nom){[string]$row.Nouveau_Nom}})
    $reserved+=@(Read-PestoNameReservations)
    $request=[pscustomobject]@{Kind=$Kind;Computers=@($script:ComputersNoms);Catalogue=@($script:CFG.NameCatalogue);Tags=@($script:CFG.TAGS);SiteMetadata=@($script:SiteMetadata);PreprodOU=[string]$script:OU['PREPROD'];ReservedNames=$reserved;Prefix=$script:PREFIXE;InventoryUtc=$script:InventoryUtc;Scope=$script:OU_SCAN;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG);Cancellation=[hashtable]::Synchronized(@{Cancelled=$false})}
    $view=Show-PestoPanel -Title $(if($Kind -eq 'capacity'){'Capacité du périmètre de nommage'}else{'Conformité des noms et des sites'}) -Body 'Préparation du calcul…' -Work $request -AcceptText 'Explorer le tableau'
    if($view.Accepted -and $view.Data){Show-PestoReviewTable -Kind $Kind -Result $view.Data}
}
