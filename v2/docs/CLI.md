# CLI V2 — préparation explicite et exécution idempotente

La CLI est un chemin du même **Pesto.exe**. Elle démarre avant WinForms, le dialogue de compte, l’initialisation du profil et tout relais UAC. Elle ne lance aucun redémarrage. Elle utilise les adaptateurs réels et les mêmes politiques, mutex GP et reçus que l’interface ; les tests portables de ses contrats ne qualifient pas les commandes AD natives.

## Prérequis et configuration

Le processus doit **déjà** être administrateur local, y compris pour une lecture CLI. Il ne demande jamais une élévation. La configuration locale du canal PROD/DEV doit déjà exister dans le profil AppData de l’opérateur ; `--v1-root` peut désigner explicitement un dossier local de configuration V1. Ce dossier n’est pas migré par la CLI. `--operator-sid`, lorsqu’un lancement élevé l’emploie, est résolu dans le registre des profils Windows, sans accepter un chemin AppData arbitraire. Le profil d’origine et le compte effectif élevé restent deux identités distinctes, toutes deux liées au plan.

Les paramètres se préparent dans **Paramètres**, avec différences et confirmation :

- `unattendedJoinEnabled` active `POLICY.UnattendedJoinEnabled` pour la jonction locale non accompagnée ; elle exige aussi `--execute` pour tout envoi.
- `unattendedOperationsEnabled` active `POLICY.UnattendedOperationsEnabled` pour les autres mutations CLI ; `--execute` reste obligatoire.
- Les deux sont faux dans une configuration neuve. Les restrictions HKLM, le scénario, les exclusions et les contrôles de disponibilité restent applicables. Une option DEBUG active ferme les préparations automatisées réelles.

La jonction automatique exige une appartenance hors domaine réellement observée et un compte AD explicite. Comme V1, elle refuse une coordination partagée configurée/requise et la réservation AD automatique ; ces cas utilisent le parcours interactif. Les opérations distantes exigent un poste d’administration membre du domaine. Le renommage distant exige un compte AD explicite ; il n’extrait aucun mot de passe du jeton Windows.

Une transaction binaire interrompue doit être traitée explicitement avant la CLI. La CLI n’importe ni ne remplace une configuration distribuée, ne prend aucune décision Remplacer/Conserver et ne lance aucune récupération binaire à l’insu de l’opérateur.

## Actions et documents

| Action | Résultat sans `--execute` | Exécution |
|---|---|---|
| `inspect --computer NOM` | Lecture du poste ; cible locale par défaut | Jamais admise |
| `diagnose` | Diagnostic de l’adaptateur réel | Jamais admise |
| `join` | Nom calculé, OU et identité locale liés à un plan | Jonction de ce PC uniquement |
| `rename --computer NOM` | Aperçu puis plan, même OU | Renommage exact du plan |
| `move --computer NOM --target-ou "OU=…"` | Identité GUID et OU/GUID relus, nom conservé | Déplacement exact du plan |
| `renameMove --computer NOM` | Nouveau nom et destination liés au plan | Renommage/déplacement exacts |
| `verify --receipt ID` | Même contrôle que **Interventions → Vérifier l’état** | Sans objet : aucune opération n’est envoyée |

La jonction calcule le nom depuis les facettes `--type P/S/V`, `--site-code` et `--service-code` et la convention configurée. Le renommage et le renommage/déplacement exigent `--new-name` exact, conforme à cette convention et relu dans l’inventaire de disponibilité ; les facettes ne remplacent pas ce nom explicite. `--target-ou` doit être un DN d’OU complet dans le domaine configuré. Les options inconnues, répétées, contradictoires et les arguments de secret sont refusés.

`--out-plan C:\PestoPlans\operation.json` exporte un **nouveau** fichier ; aucun document existant n’est écrasé. Le dossier doit exister. Le document est borné à 64 Kio et à 24 heures. Il lie action, noms, GUID, OU source/cible, DC exact, profil, SID effectif, MachineGuid, configuration exacte et intention Entra. Son champ `Integrity` détecte une altération ; il ne constitue pas une autorisation à lui seul.

La préparation d’un renommage distant peut créer une tâche temporaire de **diagnostic** Windows/Entra, contrôlée et journalisée. Elle ne renomme pas le poste et ne lance pas `/leave`. Un état Entra inconnu bloque la préparation. Un retrait hybride exige `HybridOnly`, un plan qui l’annonce, puis l’option distincte `--confirm-entra-leave` à l’exécution.

Exemple de lecture et de préparation d’un déplacement, avec le compte courant autorisé :

```powershell
# Depuis une console Windows déjà élevée ; valeurs d’exemple à adapter.
& 'C:\Pesto\Pesto.exe' --cli inspect --computer P111301PAINF009 | Out-String
& 'C:\Pesto\Pesto.exe' --cli move --computer P111301PAINF009 `
  --target-ou 'OU=Lyon,OU=Postes,DC=exemple,DC=local' `
  --out-plan 'C:\PestoPlans\move-001.json' | Out-String
```

Après lecture du plan exporté, l’ordre explicite d’exécution est distinct :

```powershell
& 'C:\Pesto\Pesto.exe' --cli move `
  --plan 'C:\PestoPlans\move-001.json' `
  --idempotency-key 'campagne-2026/move-001' --execute | Out-String
```

La CLI reconstruit un plan natif frais, compare l’intention exacte et relit configuration/politiques après les attentes. Un nom pris, un objet remplacé, une autre OU, un DC différent ou une autorisation expirée impose une nouvelle préparation ; aucune cible alternative n’est choisie après confirmation.

## Compte AD via entrée standard protégée

La jonction et le renommage distant utilisent `--credential-stdin`. L’entrée doit être un **pipe redirigé fermé**, limité à 32 Kio, contenant exclusivement :

```json
{"userName":"EXEMPLE\\operateur","blob":"BASE64_DPAPI_CURRENTUSER"}
```

`blob` est la protection DPAPI **CurrentUser**, sans entropie optionnelle, des octets UTF-16LE du mot de passe, sans terminateur nul. Elle doit être produite sous le compte Windows qui exécutera Pesto. Ni ce JSON, ni le blob, ni le mot de passe ne vont dans les arguments, variables d’environnement, paramètres, manifestes ou fichiers de plan. L’orchestrateur conserve le secret en mémoire, écrit l’enveloppe dans `Process.StandardInput`, puis ferme le pipe. Pesto refuse une entrée interactive, une propriété supplémentaire ou une enveloppe illisible. Aucun dialogue de secours n’apparaît.

Exemple de construction en mémoire sous Windows PowerShell 5.1, à intégrer dans l’orchestrateur qui possède déjà un `SecureString` :

```powershell
# $adUser et $securePassword proviennent du canal de secrets de l’orchestrateur.
# Aucun fichier n’est créé. Ne pas tracer $envelope ni les buffers.
Add-Type -AssemblyName System.Security
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$plain = $null
$protected = $null
try {
    $length = [Runtime.InteropServices.Marshal]::ReadInt32($bstr, -4)
    $plain = New-Object byte[] $length
    [Runtime.InteropServices.Marshal]::Copy($bstr, $plain, 0, $length)
    $protected = [Security.Cryptography.ProtectedData]::Protect(
        $plain, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $envelope = @{ userName = $adUser; blob = [Convert]::ToBase64String($protected) } |
        ConvertTo-Json -Compress

    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = 'C:\Pesto\Pesto.exe'
    # Arguments publics seulement ; ici une PREPARATION, sans --execute.
    $start.Arguments = '--cli rename --computer P111301PAINF009 --new-name P111301PAINF010 --out-plan "C:\PestoPlans\rename-001.json" --credential-stdin'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($envelope)
    $process.StandardInput.Close()
    $envelope = $null
    $process.WaitForExit()
    $result = $stdout.GetAwaiter().GetResult() | ConvertFrom-Json
    $exitCode = $process.ExitCode
    $errorText = $stderr.GetAwaiter().GetResult()
    $process.Dispose()
    # Exploiter $result.State / $result.ExitCode / $result.OperationId sans inventer de succès.
} finally {
    if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
    if ($protected) { [Array]::Clear($protected, 0, $protected.Length) }
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
```

Pour l’exécution ultérieure, l’orchestrateur fournit de nouveau un pipe protégé et remplace les arguments publics par `--cli rename --plan "C:\PestoPlans\rename-001.json" --idempotency-key "campagne-2026/rename-001" --execute --credential-stdin`. Un retrait Entra prévu nécessite en plus son option séparée. Le repli interactif par tâche après refus du renommage direct reste désactivé dans ce chemin non accompagné.

## Vérifier un reçu en attente

Un reçu `PendingRestart` ou incertain bloque toute nouvelle mutation du poste tant qu’il n’est pas vérifié. Après le redémarrage, `--cli verify --receipt receipt-…` relit l’identité AD, le nom, le placement et l’état Windows, comme le bouton **Vérifier l’état**. Le reçu passe à `Verified` seulement si toutes les preuves concordent ; sinon il garde son statut et sa barrière, avec la raison. Codes : `0` vérifié, `3010` redémarrage encore attendu, `97` incertain, `96` refus. Aucune opération n’est rejouée et aucun journal idempotent n’est écrit. L’action exige `POLICY.UnattendedOperationsEnabled` ou `UnattendedJoinEnabled`, sans interdiction HKLM, et un processus déjà administrateur ; elle n’accepte ni plan, ni compte, ni option d’exécution.

```powershell
& 'C:\Pesto\Pesto.exe' --cli verify --receipt receipt-0123456789abcdef0123456789abcdef | Out-String
```

## Résultats, preuves et reprises

La sortie standard est un document JSON aux propriétés PascalCase (`Schema`, `Mode`, `State`, `ExitCode`, `EngineCode`, `RestartRequired`, `MutationStarted`, `OperationId`, `Utc`, `Message`, `Plan`, `Metadata`, `Observation` selon le résultat).

| Code processus | Signification |
|---|---|
| `0` | Lecture/préparation terminée, ou mutation vérifiée ; distinguer `State=Observed/Prepared/Verified` |
| `3010` | Commande acceptée et reçu durable en attente de redémarrage ; aucun redémarrage lancé |
| `96` | Refus, aucune nouvelle commande métier admise |
| `97` | Résultat incertain, partiel, interrompu ou preuve finale insuffisante ; aucun rejeu implicite |

La clé d’idempotence est liée à l’intention, aux identités et au plan. Le journal sous `%ProgramData%\GP\V2\automation` écrit une intention durable **avant** la création des adaptateurs, les diagnostics distants et les acquisitions partagées. Une exécution déjà engagée ne devient pas une nouvelle mutation lors d’un nouvel appel. Les clés historiques V1 reconnues restent bloquantes. Une preuve illisible ou absente conserve l’incertitude. Les résultats `0/3010` d’une mutation doivent correspondre aux octets exacts et aux faits du reçu durable ; une reprise locale ne contacte pas le domaine pour réinventer cette preuve.

`--metadata` admet uniquement les chaînes publiques `Campaign`, `Sequence`, `Stage`, `DeploymentBuild`, `Orchestrator`, de 120 caractères au plus. Si la GPO exige un accord de campagne, `--approval` fournit une enveloppe `PestoCampaignApproval` validée avec le certificat RSA épinglé dans HKLM, le SID d’un approbateur distinct et l’empreinte du plan entier. Le champ `PlanHashes` doit contenir l’`Integrity` du plan **V2** (`AutomationCampaignApproval.PlanHash` expose la même valeur). Un ancien accord portant un hash de plan V1 n’est pas transférable. La création d’accord relève de l’outillage de campagne externe ; aucune clé privée ni signature de l’application n’est ajoutée à Pesto.

Les contrôles Windows réels sur poste joint/hors domaine, DPAPI sous le compte d’exécution, UAC avec autre compte, AD/SMB et reprise après interruption sont à lire dans le rapport de qualification courant. Une compilation ou une fixture CLI ne prouve pas ces comportements natifs.
