# Intégrer Pesto 1.0

Pesto s'exécute sur Windows installé, avec Windows PowerShell 5.1 x64 élevé.
Le moteur silencieux n'utilise pas WPF. WinPE et PowerShell 7 ne sont pas des
cibles d'exécution des mutations. La distribution garde `Pesto.exe` et `wad/`.

## Préparer, examiner, exécuter

Activer `POLICY.UnattendedJoinEnabled` pour la jonction ; activer séparément
`POLICY.UnattendedOperationsEnabled` pour le renommage et le déplacement.
Les deux options sont désactivées par défaut. `POLICY.IncidentMode` suspend
les nouvelles mutations, avec les lectures toujours disponibles.

```powershell
# Le compte provient du coffre de votre orchestrateur : objet PSCredential en mémoire.
# Aucun mot de passe ne doit apparaître dans les arguments, variables distribuées ou logs.
$r = & C:\Pesto\wad\Invoke-Pesto.ps1 -Action Join -Credential $credentialDuCoffre `
    -Type P -SiteCode PA -ServiceCode INF -TargetOU $ouDeParis `
    -OutPlanPath C:\Plans\poste-42.json
if ($r.ExitCode -ne 0) { throw $r.Message }

# Après examen : même nom, nouveaux contrôles de configuration, machine, OU et disponibilité.
$r = & C:\Pesto\wad\Invoke-Pesto.ps1 -Action Join -Credential $credentialDuCoffre `
    -PlanPath C:\Plans\poste-42.json -IdempotencyKey 'campagne42/poste42/join' -Execute
$credentialDuCoffre = $null
exit $r.ExitCode
```

Un plan expire après 24 heures et ne réserve aucun nom. Son empreinte détecte
une modification accidentelle ; elle ne constitue pas une signature ni une
approbation. L'exécution relit les identités et l'état courant. Un nom devenu
occupé est refusé : aucun remplacement silencieux. Ne pas exporter un plan
dans un emplacement où un tiers non autorisé peut le modifier.

Le registre idempotent est local à la machine opérateur, sous
`%ProgramData%\GP\Automation`, avec droits administrateurs/SYSTEM. Il conserve
un marqueur avant d'appeler le moteur. Une même clé et une même demande
restituent le résultat enregistré. Une demande différente est refusée.
Une interruption sans résultat final retourne 97 : examiner les reçus, sans
effacer le marqueur pour forcer un nouvel essai. Ce registre ne remplace pas
la coordination entre plusieurs machines opératrices. Un refus 96 est lui aussi
conservé : après correction de sa cause et nouvel examen du plan, utiliser une
**nouvelle clé explicite** pour une nouvelle tentative. Ne pas effacer l’ancien
résultat ; réutiliser sa clé restitue le refus sans rejouer le moteur.

## Renommer, déplacer et inspecter

`-Action Rename`, `Move` et `RenameMove` utilisent les mêmes règles de site,
précontrôles, GUID, protection AD et reçus que le parcours unitaire graphique.
Fournir `-Computer`, `-NewName` pour renommer, et `-TargetOU` pour déplacer.
Même site : pas de déplacement arbitraire. Nouveau site : le changement de
nom correspondant et le déplacement restent coordonnés par le moteur.

`-Action Inspect -Computer NOM -AsJson` effectue une lecture Windows/AD,
sans exécuter ni clôturer un reçu. L'état de chaque observation reste distinct
de la réussite globale de lecture : examiner aussi `Observation.Errors`.

## Contrôler un scénario administré avant publication

Avant d'écrire `ScenarioJson` dans `HKLM\SOFTWARE\Policies\M4D\Pesto`, faire passer le
candidat par `integrations\Test-PestoManagedScenario.ps1`. Il confirme l'intégrité du
paquet, évalue le scénario avec le validateur de l'intégrateur puis avec le closure du
moteur, et refuse tant que les deux ne concordent pas. Il ne lit aucun secret, n'écrit
rien dans le registre et ne mute rien : sortie `0` si publiable, `96` sinon.

```powershell
& C:\Pesto\integrations\Test-PestoManagedScenario.ps1 -Installation 'C:\Pesto' `
    -ScenarioPath C:\temp\scenario-candidat.json -ValuesPath C:\temp\valeurs.json -AsJson
# Ou contrôler la valeur déjà publiée dans la stratégie ordinateur (session Windows) :
& C:\Pesto\integrations\Test-PestoManagedScenario.ps1 -Installation 'C:\Pesto' -FromRegistry -AsJson
# Ou contrôler des plans candidats réels avant de publier le scénario :
& C:\Pesto\integrations\Test-PestoManagedScenario.ps1 -Installation 'C:\Pesto' `
    -ScenarioPath C:\temp\scenario-candidat.json -PlanPath C:\temp\plans.json -AsJson
```

`-PlanPath` prend un tableau JSON de plans (`Nom_du_PC`, `Nouveau_Nom`, `OU_Actuelle`,
`OU_Destination`, `Objet_GUID`). Les valeurs du scénario n'y sont pas recopiées à la main :
elles sont dérivées du nom demandé par `Get-PestoPlanScenarioValues`, exactement comme le
moteur le fera à l'exécution. Chaque plan est passé à la garde `Assert-PestoOperationPolicy`
du moteur, puis au validateur de l'intégrateur ; le plan est refusé dès que l'une des deux
dissonne, et le scénario n'est plus publiable. Un plan porteur d'`Objet_GUID` est refusé
avant tout appel AD. Les messages restent fermés : ni le nom du scénario ni le contenu d'un
plan ne sortent du rapport.

**Limite consignée, pas corrigée.** La garde de valeurs du moteur, `Assert-PestoScenarioValues`
(`wad/Pesto-Policy.ps1`), ne regarde que le vide pour un champ obligatoire : une valeur
laissée blanche, un caractère de contrôle ou une valeur de plusieurs milliers de caractères
la traversent, alors que le validateur de l'intégrateur les refuse. Le point d'entrée publie
donc au refus, avec `Garde du moteur affaiblie sur un plan candidat.`. Corriger la garde du
moteur touche un fichier scellé et exige de régénérer `Pesto.exe`.

`-ReportPath` écrit un rapport JSON une seule fois et refuse d'écraser. Ce contrôle est
consultatif : il n'ajoute aucune porte de refus au moteur, qui garde seul autorité sur
les droits AD et les autres exclusions.

## Adaptateur d'orchestrateur

Copier `Invoke-PestoDeployment.ps1` dans le contenu du déploiement avec le
pack PROD. Le paramètre `-Installation` pointe vers ce pack. Aucun produit
d'orchestration n'est installé par Pesto.

| Hôte | Préparation du contexte | Traitement attendu |
|---|---|---|
| ConfigMgr | Étape PowerShell x64 sur Windows installé ; compte fourni en mémoire ; métadonnées explicitement choisies | 0 = étape terminée ; 3010 = redémarrage à orchestrer ; 97 = intervention requise, aucun retry automatique |
| PSADT | Appeler depuis la phase de déploiement et transmettre un PSCredential du coffre approuvé | Conserver le résultat JSON et le code exact avant la sortie du toolkit |
| PDQ | Étape PowerShell avec compte de déploiement autorisé, installation déjà copiée | Reprendre la même clé ; ne pas configurer de rejeu automatique après 97 |
| DeployR | Étape Windows avec paramètres typés explicites | Renseigner Campaign/Sequence/Stage/DeploymentBuild ; décider du redémarrage dans la séquence |
| FirstBoot | Appeler sous SYSTEM, réseau et résolution du domaine disponibles | Fournir le compte AD depuis le mécanisme sécurisé de la séquence ; aucun mot de passe stocké dans SetupComplete |

`-Execute` exige une clé idempotente dans l'adaptateur. Les métadonnées sont
limitées à une liste fermée et à 120 caractères par valeur. L'adaptateur
n'exporte jamais l'ensemble des variables d'une séquence.

Le kit FirstBoot est appelé par la séquence existante ; il ne crée ni service,
ni tâche planifiée, ni ouverture de session automatique. Un manque de réseau
avant mutation retourne un refus. Une étape qui attend le réseau doit être
bornée par l'orchestrateur et distincte de l'étape de mutation.

## Contrat de retour

| Code | Sens | Action |
|---:|---|---|
| 0 | Préparation effectuée, lecture retournée ou déplacement confirmé selon `Mode`/`State` | Examiner le résultat ; 0 en préparation ne signifie aucune mutation |
| 3010 | Commande acceptée ; redémarrage nécessaire | Redémarrer à l'étape choisie ; ne pas rejouer |
| 96 | Refus avant lancement | Corriger la cause puis préparer de nouveau |
| 97 | Issue incertaine ou résultat final non conservé | Examiner poste et reçus ; aucune répétition automatique |
| Autre | Code métier du moteur, conservé | Lire `EngineCode`, `State` et `Message` |

Les champs de base `Schema`, `Mode`, `State`, `ExitCode`, `MutationStarted`,
`RestartRequired` et `Message` gardent leur sens. Les ajouts sont optionnels ;
un consommateur ne doit pas interpréter une propriété inconnue comme une
permission d'exécuter. Aucun changement incompatible sans nouveau schéma.

## Qualification

Les tests de contrats utilisent des doubles Windows/AD. La qualification de
chaque produit/version de ConfigMgr, PSADT, PDQ ou DeployR nécessite une vraie
séquence dans cet outil : compte, réseau, code 3010, coupure et restitution de
la même clé. Un exemple exploitable ne prouve pas cette qualification.

Sources : [PSADT](https://psappdeploytoolkit.com/docs/4.1.x/usage/customizing-deployments),
[DeployR](https://documentation.2pintsoftware.com/deployr/reference/task-sequence-variables.md),
[permissions de jonction Microsoft](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/active-directory-domain-join-permissions).
