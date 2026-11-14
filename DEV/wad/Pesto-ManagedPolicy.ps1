#requires -Version 5.1
# GPO : restrictions ordinateur uniquement. Aucune écriture de registre.
function Get-PestoManagedPolicy {
    $values=[ordered]@{}
    if([Environment]::OSVersion.Platform -eq 'Win32NT'){
        $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Policies\M4D\Pesto',$false)
        if($key){
            try{
                if('ScenarioJson' -cin $key.GetValueNames()){
                    if($key.GetValueKind('ScenarioJson') -ne [Microsoft.Win32.RegistryValueKind]::String){throw 'Scenario GPO invalide.'}
                    $json=[string]$key.GetValue('ScenarioJson');if($json.Length -gt 65536){throw 'Scenario GPO trop volumineux.'}
                    $values['Scenario']=ConvertTo-PestoScenario ($json|ConvertFrom-Json -ErrorAction Stop)
                }
                foreach($name in @('IncidentMode','DisableUnattendedJoin','DisableUnattendedOperations','MaxBatch')){
                    if($name -cnotin $key.GetValueNames()){continue}
                    if($key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::DWord){throw ('Stratégie administrée invalide : '+$name)}
                    $value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    if($value -isnot [int] -or ($name -eq 'MaxBatch' -and ($value -lt 1 -or $value -gt 200)) -or ($name -ne 'MaxBatch' -and $value -notin @(0,1))){throw ('Valeur de stratégie invalide : '+$name)}
                    $values[$name]=$value
                }
            }finally{$key.Dispose()}
        }
    }
    return [pscustomobject]@{Source='HKLM\Software\Policies\M4D\Pesto';Values=[pscustomobject]$values;Configured=($values.Count -gt 0)}
}

function Merge-PestoManagedPolicy {
    param([Parameter(Mandatory=$true)]$Policy,$Managed=$null)
    if($null -eq $Managed){$Managed=Get-PestoManagedPolicy}
    $copy=[ordered]@{};foreach($property in $Policy.PSObject.Properties){$copy[$property.Name]=$property.Value}
    $v=$Managed.Values
    foreach($name in @('IncidentMode','DisableUnattendedJoin','DisableUnattendedOperations')){
        if($null -ne $v.PSObject.Properties[$name] -and ($v.$name -isnot [int] -or $v.$name -notin @(0,1))){throw ('Stratégie invalide : '+$name)}
    }
    # Une GPO restrictive peut bloquer, jamais activer une fonction désactivée dans cfg.json.
    if($v.IncidentMode -eq 1){$copy['IncidentMode']=$true}
    if($v.DisableUnattendedJoin -eq 1){$copy['UnattendedJoinEnabled']=$false}
    if($v.DisableUnattendedOperations -eq 1){$copy['UnattendedOperationsEnabled']=$false}
    if($null -ne $v.PSObject.Properties['MaxBatch']){
        if($v.MaxBatch -isnot [int] -or $v.MaxBatch -lt 1 -or $v.MaxBatch -gt 200){throw 'Limite de lot administrée invalide.'}
        $copy['MaxBatch']=[Math]::Min([int]$Policy.MaxBatch,[int]$v.MaxBatch)
    }
    if($v.PSObject.Properties['Scenario']){$copy['Scenario']=ConvertTo-PestoScenario $v.Scenario}
    return [pscustomobject]$copy
}

function Get-PestoManagedPolicySummary {
    $policy=Get-PestoManagedPolicy
    if(-not $policy.Configured){return 'Paramètres locaux (aucune restriction GPO Pesto).'}
    $items=@(foreach($p in $policy.Values.PSObject.Properties){$p.Name+' = '+[string]$p.Value})
    return 'Restrictions ordinateur : '+($items -join ' ; ')+'. Origine : '+$policy.Source+'. Les choix locaux ne peuvent pas les assouplir.'
}
