# Extensions livrées — 18 octobre 2026

Les points 109, 111, 114 et 117 ont des parcours exécutables dans le moteur. Leur
validation porte sur des tests locaux de contrats et de comportement, avec doubles
AD/Windows. Aucun test VM ni qualification de domaine réel n'a été effectué.
Le produit cible toujours Windows PowerShell 5.1 x64 et .NET Framework 4.7.2.

## 111 — Scénarios administrés

`POLICY.Scenario` accepte un objet fermé. Exemple :

```json
{"Schema":1,"Name":"Portables Paris","Required":["Type","ServiceCode"],
 "Allowed":{"Type":["P"],"SiteCode":["PA"]},"Locked":{"ServiceCode":"INF"}}
```

Champs : `Type`, `SiteCode`, `ServiceCode`, `TargetOU`. Les valeurs autorisées sont
des listes, les valeurs verrouillées des chaînes uniques. Une valeur verrouillée
contradictoire avec une liste autorisée est refusée. Les facettes sont extraites du
nom réellement demandé ; le moteur ne fait pas confiance aux seules étiquettes du
formulaire. Le bouton **Scénario administré…** affiche ces contraintes ; la préparation
refuse de produire un nom hors scénario. Les réglages locaux préservent le scénario.

Pour imposer ce scénario depuis la politique ordinateur, enregistrer le même JSON
comme valeur REG_SZ `ScenarioJson` sous `HKLM\SOFTWARE\Policies\M4D\Pesto`.
Cette valeur remplace le scénario local. Le moteur relit la politique avant la
mutation. Les droits AD et les autres exclusions restent obligatoires.

### Ce qui est branché, et ce qui ne l'est pas

Le validateur fait autorité dans `wad/Pesto-Policy.ps1` : `ConvertTo-PestoScenario`
ferme l'objet (`Schema`, `Name`, `Required`, `Allowed`, `Locked`), `Assert-PestoScenarioValues`
contrôle les valeurs et `Get-PestoPlanScenarioValues` dérive les facettes du nom
**réellement demandé**, jamais des étiquettes du formulaire. Trois parcours du produit
l'appellent :

- `Show-PestoScenarioFields` (`wad/Pesto-Preparation.ps1`, branché sur le bouton
  `PrepScenario`) affiche Obligatoire, Valeurs autorisees et Valeur verrouillee ;
- `Update-NameList` (`wad/Pesto-Core.ps1`) contrôle les facettes du nom généré pendant
  la préparation ;
- `Assert-PestoOperationPolicy` (`wad/Pesto-Policy.ps1`, ligne 58) contrôle le scénario
  **avant toute lecture AD** ; il est appelé par le parcours extensions
  (`wad/Pesto-Extensions.ps1`, lignes 73 et 189), la préparation à distance
  (`Pesto-Enterprise.ps1`), la reprise (`Pesto-Recovery.ps1`), la sécurité
  (`Pesto-Safety.ps1`) et la jonction (`Pesto-Join.ps1`).

### Le contrôle avant publication du `ScenarioJson`

`Test-PestoScenarioInput` (`integrations/Pesto.Optional.psm1`) est un validateur
consultatif : rien dans le moteur n'en dépend, et il est **plus strict** que lui sur les
valeurs (champs inconnus, blancs, longueur, caractères de contrôle). Il ne peut donc pas
servir de porte de refus dans `Invoke-PestoDeployment.ps1` sans bloquer des opérations
que le moteur admet. Il est en revanche branché dans un consommateur réel, le point
d'entrée `integrations/Test-PestoManagedScenario.ps1`, qui évalue un scénario candidat
avec le validateur intégrateur **puis** avec `ConvertTo-PestoScenario`, et refuse tant
que les deux ne se concordent pas. Sortie fermée : `0` publiable, `96` refusé ; aucune
écriture de registre, aucune lecture AD, aucune mutation.

```powershell
& "$Installation\integrations\Test-PestoManagedScenario.ps1" -Installation 'C:\Program Files\M4D\Pesto' `
    -ScenarioPath 'C:\temp\scenario-candidat.json' -ValuesPath 'C:\temp\valeurs.json' -AsJson
```

La branche `-FromRegistry` relit `ScenarioJson` dans la stratégie ordinateur telle que
le moteur la lira ; hors Windows elle rend un refus ferme et jamais un faux « publiable ».

**Défaut trouvé et corrigé le 24 octobre 2026.** La documentation affirmait le validateur
« aligné sur le moteur » ; il ne l'était pas. Sur un corpus systématique de 8 064 formes
(`Schema`, `Name`, `Required`, `Allowed`, `Locked` croisés absents, nuls, vides, peuplés,
hors champ, vectoriels, chaîne), 444 formes passaient le validateur intégrateur et
étaient refusées par `ConvertTo-PestoScenario` : `Allowed` ou `Locked` absent ou nul,
`Required` donné comme chaîne, `Name` non chaîne ou porteur d'un caractère de contrôle.
Publiées telles quelles, ces formes font échouer la lecture de `ScenarioJson` sur tous
les postes visés, donc après la GPO. La forme acceptée est maintenant un sous-ensemble
de celle du moteur, et deux gardes non redondantes l'empêchent de revenir :

- `Run-OptionalIntegrationsTests.ps1` rejoue le différentiel sur les 8 064 formes (et non
  plus sept cas choisis) ; la suite rend 8/9 et sort 1 si l'alignement est défait ;
- `Run-ManagedScenario111FormMutationTests.ps1` frappe les gardes du formulaire sur des
  copies hors sac, jambe du moteur décrochée pour celles que le moteur masquerait, plus la
  paire « moteur durci / jambe décrochée » qui prouve que la jambe du moteur porte ;
  134/134, témoin conforme passe.

**Jambe des plans, ajoutée le 24 octobre 2026.** Un scénario administré ne se juge pas sur
des valeurs recopiées à la main : à l'exécution, `Assert-PestoOperationPolicy` dérive les
champs du scénario du **nom réellement demandé** (`Get-PestoPlanScenarioValues`, puis
`ConvertTo-PestoNameParts`) et de l'emplacement du plan. Le point d'entrée accepte donc
`-PlanPath`, un tableau JSON de plans, et rejoue cette dérivation avant publication. Chaque
plan est passé à la garde du moteur puis au validateur de l'intégrateur ; le désaccord est
un refus (`Garde du moteur affaiblie sur un plan candidat.`), jamais un avertissement. Les
messages restent fermés — ni le nom du scénario ni le contenu d'un plan ne sortent du
rapport — et un plan porteur d'`Objet_GUID` est refusé avant tout appel AD.

Deux défauts réels sont sortis de là :

- la garde de valeurs du moteur, `Assert-PestoScenarioValues` (`wad/Pesto-Policy.ps1`), ne
  regarde que le vide pour un champ obligatoire : `TargetOU` laissé blanc, porteur d'un
  caractère de contrôle ou long de 5 000 caractères la traverse, alors que le validateur de
  l'intégrateur la refuse. Publiée, une telle valeur part en écriture d'emplacement sur les
  postes visés. Le correctif touche un fichier **scellé** et exige de régénérer `Pesto.exe`,
  impossible sur Spark (ni `clang` ni `lld-link`) : la garde est **consignée**, et c'est le
  point d'entrée qui refuse ;
- le point d'entrée ne consultait pas du tout cette garde : un scénario publiable au regard
  du formulaire pouvait être refusé par le moteur au premier effet.

Les deux sont tenus par :

- `Run-ManagedScenario111PlanTests.ps1`, 19/19 : le point d'entrée est rejoué comme vrai
  processus enfant sur un paquet reconstruit, plans conformes, valeur interdite dérivée du
  nom, champ obligatoire blanc, caractère de contrôle, valeur trop longue, verrou, champ de
  plan non admis, `Objet_GUID`, fichier de plans volumineux ou surabondant ;
- `Run-ManagedScenario111PlanMutations.ps1`, 170/170 : onze mutations (jambe du moteur
  décrochée, garde du formulaire affaiblie, dérivation du nom remplacée, forme, taille et
  nombre de plans non bornés, garde d'identité éteinte, et côté module liste autorisée,
  obligatoire aveugle aux blancs, contrôle des caractères de contrôle éteint), chacune tuée
  — seules ou en paire quand l'autre jambe masque la mutation — plus un test différentiel
  systématique de 100 formes (5 scénarios × 4 noms × 5 emplacements) qui confronte le
  verdict publié du point d'entrée au verdict des deux gardes appelées en direct, avec
  contrôle de non-vacuité (58 refus du moteur, 22 formes que le moteur accepte et que le
  formulaire refuse, 20 acceptées par les deux, 0 divergence, 0 fuite).

## 117 — Approbation distincte des campagnes

La valeur REG_SZ `CampaignApprovalJson`, dans la même clé HKLM, définit les campagnes
concernées et les signataires autorisés :

```json
{"Schema":1,"Campaigns":["PARIS-2026"],"Signers":[
 {"CertificateSHA256":"empreinte-sha256-du-certificat-DER-en-64-hex-minuscules",
  "Sid":"S-1-5-21-111-222-333-1001"}]}
```

`"*"` impose une campagne et un accord pour toute opération concernée par ce moteur.
La confiance vient exclusivement de HKLM, jamais du plan ou du certificat joint à
l'accord. Une modification locale de `cfg.json` ne supprime pas cette obligation.
Une suppression du certificat de cette liste révoque son autorisation.

Depuis une session Windows de l'approbateur, importer `Pesto.Engine.psd1`, lire les
plans préparés, puis appeler :

```powershell
$accord = New-PestoCampaignApproval -Plans $plans -Certificate $certificat -Minutes 60
```

La clé privée reste chez l'approbateur. RSA SHA-256, au moins 2048 bits, signe le
payload exact ; le certificat et la signature sont publics. L'accord lie campagne,
SID, échéance (24 heures maximum), domaine, machine opératrice, configuration,
identités source/destination et effets demandés (y compris le diff d'attributs ou
l'empreinte du blob ODJ). Les horodatages de préparation et les facettes redondantes
ne remplacent pas cette identité des effets. L'exécution du plan garde sa propre
validation d'intégrité et d'expiration.

Transmettre l'objet accord avec `-Approval` à `Invoke-PestoCommand`,
`Invoke-PestoUnattendedOperation`, `Invoke-PestoUnattendedJoin` ou au parcours
extensions. Le SID exécutant doit différer du SID signataire associé au certificat.
La signature, la politique actuelle et l'expiration sont revérifiées au passage
vers les effets. Ce mécanisme ne crée ni service de tickets ni serveur d'approbation.

### Défaut connu : la garde de taille de clé ne mesure rien hors Windows

Les deux gardes de `wad/Pesto-Policy.ps1` mesurent la clé avec `$key.KeySize`
(ligne 348 pour la clé privée à la signature, ligne 368 pour la clé publique à la
vérification). Sous un PowerShell hors Windows,
`RSACertificateExtensions::GetRSAPrivateKey` rend un `RSAOpenSsl` dont `KeySize`
n'a qu'un accesseur **en écriture** (`CanRead=False`) : la garde lève
`Cannot get property value because "KeySize" is a write-only property.` au lieu de
refuser une clé de 1024 bits, et le test ne peut plus distinguer « clé trop courte »
d'une erreur de liaison. Le correctif consisterait à mesurer
`ExportParameters($false).Modulus` (octets de poids fort, zéros de tête exclus) dans
une fonction `Get-PestoRsaKeyBits` partagée par les deux gardes, et à l'ajouter à
`$script:PestoWorkerCoreNames`. Il n'est **pas** appliqué ici : ces lignes vivent dans
le moteur scellé et le changement exige de régénérer `Pesto.exe`
(`Build-PestoEngineModule.ps1` puis `build_native.py`), impossible sur Spark sans
installer une chaîne de compilation. La qualification de cette garde reste donc à
faire sur Windows PowerShell 5.1, où `KeySize` est lisible.

Bilan rejoué le 26 octobre 2026 (`proofs/CAMPAIGN_APPROVAL_117_KEYSIZE_20261026.json`) :
le défaut est **fermé** — rien n'est jamais accepté, l'opération avorte ; ce n'est pas
une ouverture, c'est un diagnostic erroné qui rend les quatorze cas injouables hors
Windows, y compris ceux qui ne touchent pas la taille de clé, puisque le script
avorte dès `New-PestoCampaignApproval`. Aucune préparation de clé côté fixture n'y
échappe : `RSA.Create`, `RSACryptoServiceProvider`, import PFX et `CopyWithPrivateKey`
ont été sondés, et la jambe de vérification reconstruit de toute façon le certificat
depuis `RawData` avant `GetRSAPublicKey`, qui rend toujours un `RSAOpenSsl` non Windows.
Le correctif a été **validé hors dépôt** : les deux fichiers corrigés, la construction
du moteur passe (740 → 741 fonctions, fermeture 165 → 166) et les quatorze cas passent
14/14. L'étape `PestoWorkerCoreNames` n'est pas décorative — sans elle, la construction
refuse par `Compléter PestoWorkerCoreNames pour le worker GUI : Get-PestoRsaKeyBits`.
Ce qui bloque n'est pas la reproductibilité des artefacts générés, vérifiée ici par
`Build-PestoEngineModule.ps1 -Check`, mais le rebâtiment natif : `clang`, `lld-link` et
`llvm-rc` sont absents de Spark et `last-build.json` atteste un outillage Homebrew
macOS. Corriger `wad/Pesto-Policy.ps1` sans rebâtir `Pesto.exe` ferait passer
`verify_native_binding` au rouge sur 23 tests Python (`test_rc19`, `test_rc21`,
`test_rc22`, `test_rc23`, `test_names_loading`, `test_spark_t061`) et ferait refuser le
chargement de PowerShell par le lanceur ; le dépôt n'a donc pas été patché.

### Les quatorze cas sont désormais joués sur Spark

`Run-CampaignApproval117Tests.ps1` n'est plus déclarée `Windows51` mais `Portable`,
et elle joue **15/15** sur Spark. La suite sonde d'abord l'hôte : si
`GetRSAPublicKey` y rend bien un `RSAOpenSsl` dont `KeySize` est en écriture seule,
elle installe un `ScriptProperty` `KeySize` sur
`System.Security.Cryptography.RSAOpenSsl` qui mesure
`ExportParameters($false).Modulus`, et le retire dans son bloc `finally`. Sous
Windows PowerShell 5.1 la sonde répond « lisible », rien n'est installé, et la garde
du produit lit `KeySize` exactement comme avant. L'adaptateur n'est donc ni un mock
de la garde ni une valeur de confort : il rend seulement lisible la propriété que le
correctif produit devra mesurer. La ligne de résumé nomme la source ayant mesuré
(`host KeySize` ou `fixture modulus`), ce qui rend l'état visible dans le banc.

Deux contrôles empêchent cet adaptateur d'être un tampon :

- le cas `Key size is measured from the modulus, never frozen` lit la taille par
  l'accesseur même de la garde, sur les deux jambes (clé privée et clé publique),
  pour une clé de 2048 bits et une clé de 1024 bits, et exige qu'elle suive le
  module : `2048`, `1024`, et deux valeurs distinctes ;
- `Run-CampaignApproval117MutationTests.ps1` (portable, **20/20** sur Spark) rejoue
  la suite sur une copie hors sac des cinq modules qu'elle point-source et de la
  suite elle-même — `cfg.json` n'est jamais copié, l'original scellé n'est jamais
  touché — et tue quatre mutants : retirer la taille de la garde de signature, la
  retirer de la garde de vérification, figer le mesureur de fixture au plancher
  (2048), le figer sous le plancher. Les deux premiers font échouer le cas de la clé
  faible, les deux suivants le cas de mesure ; la copie témoin passe.

Preuve rejouée le 26 octobre 2026
(`proofs/CAMPAIGN_APPROVAL_117_SPARK_QUALIFICATION_20261026.json`).

Les trois suites sont enrôlées et réellement jouées : le banc portable complet rend
**76 réussies, 0 en échec, 20 ignorées** sur 96 suites déclarées
(`tests/results/20261026_050054_033581/summary.json`), contre 74/0/21 sur 95 avant le
point, où `Run-CampaignApproval117Tests.ps1` figurait en SKIP — « Plateforme Windows51 :
Windows PowerShell 5.1 requis ». Ce qui reste bloqué n'est pas le jeu des cas mais la
correction de la garde dans le moteur scellé : elle attend la machine qui peut rebâtir
`Pesto.exe`.

## 114 — Attributs AD explicites

L'entrée `Invoke-PestoExtensionCommand` est exportée par `Pesto.Engine.psd1` ;
`wad/Invoke-PestoExtension.ps1` fournit le lanceur en processus séparé.

```powershell
# Dans une session Windows PowerShell 5.1 élevée, avec le module du pack importé :
$r = Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action Attributes `
    -ObjectGuid $guid -Attributes ([pscustomobject]@{description='Atelier';location='Paris'}) `
    -OutPlanPath C:\Plans\attributs.json

$r = Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action Attributes `
    -PlanPath C:\Plans\attributs.json -IdempotencyKey 'PARIS-2026/attributs-01' `
    -Approval $accord -Execute
```

Attributs autorisés : `description`, `location`, `managedBy`. Une chaîne vide efface
l'attribut. Une référence `managedBy` non vide est liée à un GUID du même domaine.
Le plan exporte un diff avant/après. À l'exécution, le moteur relit GUID, nom,
emplacement, valeurs initiales et référence `managedBy`. Il vérifie scénario,
exclusions, rôle de la cible, approbation et reçus antérieurs. Un changement concurrent
refuse la commande. Les ACL AD décident en dernier ressort des droits d'écriture.

Un seul `Set-ADObject` applique remplacement et effacement. L'intention `Attributes`
et le diff sont enregistrés avant cet appel. La relecture par GUID doit confirmer
chaque valeur. Une interruption reste incertaine, sans reprise automatique.
`-Action AttributeObserve -OperationId $id` relit les effets et peut réconcilier le
reçu ; elle n'envoie aucune écriture AD. Un nouveau plan ne contourne pas un reçu
incertain sur la même cible.

Ce qui est attesté localement (24 octobre 2026) : `Run-ExtensionEffectsTests.ps1` joue
cinquante-sept cas contre le moteur scellé, dont la forme et la taille des valeurs, le
caractère de contrôle, `managedBy` sans DN, le diff vide, l'attribut hors des trois
autorisés, le doublon, le quatrième changement, le champ de plan ou de diff illicite, la
référence épinglée sur un GUID ou absente, la cible hors périmètre OU, dans un autre
domaine, au GUID divergent, déplacée ou renommée, le plan expiré, à l'empreinte de
configuration, à la machine ou au domaine étrangers, la valeur avant obsolète, l'écriture
non relue, la persistance d'effet en échec, `IncidentMode`, `ExcludedNames`,
`ExcludedOUs`, le rôle contrôleur de domaine, l'approbation de campagne, l'observation en
lecture seule, le reçu d'un autre domaine et le reçu sans intention.
`Run-AttributeEffects114MutationTests.ps1` frappe ces gardes sur trente-deux mutations
du moteur copié hors sac (cent trente et une assertions) : un mutant qui survit est une
garde inopérante, et trois cas qui en survivaient ont été corrigés pour exiger le message
de la garde qui doit refuser, pas celui d'un contrôle aval.

Le point d'entrée public est joué pour de vrai depuis le 24 octobre 2026 :
`Run-AttributeEntry114Tests.ps1` n'appelle plus les fonctions internes mais seulement
`Invoke-PestoExtensionCommand`, sur trente-quatre cas — verrou du mutex d'entrée, résolution du
`cfg.json` posé à côté du runtime quand `-ConfigPath` est omis (vérifiée dans les deux sens :
absent, l'entrée refuse ; présent, elle prépare), refus de combiner plan et changements directs,
exigence `PlanPath` + `IdempotencyKey` sans `OutPlanPath`, garde d'exécution de
`AttributeObserve`, aller-retour réel du plan sur disque (`Export-PestoPortablePlan` en
`CreateNew`, jamais de remplacement silencieux, puis `Read-PestoAutomationJson` et
`Assert-PestoAttributePlan`, dates normalisées en UTC `o` avant empreinte) et registre idempotent
réel (`Invoke-PestoIdempotentExecution` : grammaire ASCII de la clé, empreinte de charge, machine
opérateur, rejeu d'un `Completed` marqué `Replayed`, refus de rejeu d'une tentative incertaine,
enregistrement `Started` avant la première écriture AD). Les gardes du contexte sont jouées par le
même chemin : drapeaux `DEBUG`, politique d'automatisation, poste hors domaine, `PSCredential` fourni
en mémoire, contrôleur découvert confronté au domaine configuré, session en consultation.
`Run-AttributeEntry114MutationTests.ps1` frappe ces gardes sur trente mutations du moteur copié hors
sac (cent trente assertions), dont une paire : la session en consultation doit être supprimée des
deux jambes à la fois, sinon l'une masque l'autre et le mutant survit.

L'évaluation du diff avant remise est jouée pour de vrai depuis le 24 octobre 2026 :
`integrations/Test-PestoAttributeDiff.ps1` est le consommateur qui confronte l'aperçu de l'intégrateur
(`New-PestoAttributeProposal`) aux gardes du moteur lui-même (`Get-PestoAttributeChanges`,
`Assert-PestoAttributeChanges`). Les deux jambes doivent tomber d'accord sur le même diff, ligne par
ligne, et être jugées identiquement par la garde du moteur : un aperçu que le plan refuserait plus tard
n'est pas une évaluation, c'est une revue que l'opérateur approuve et que la remise du fichier ne tiendra
pas. Cette confrontation n'existait nulle part — `New-PestoAttributeProposal` n'avait aucun consommateur
dans le produit et ses gardes étaient plus faibles que celles du moteur : un diff vide était accepté,
deux demandes homonymes se fondaient en une seule ligne, et les lignes produites n'avaient pas le champ
`ReferenceGuid` que `Assert-PestoAttributeChanges` exige. L'aperçu rend donc aujourd'hui la forme fermée
attendue, refuse le diff vide et le doublon, et `New-PestoAuditExport` accepte enfin le mode `Attributes`
que le moteur rend lui-même, sans quoi le résultat de l'extension ne pouvait être exporté.
`Run-AttributeDiff114PreflightTests.ps1` joue ce consommateur en processus enfant sur vingt et un cas — diff
accepté avec les attributs nommés, référence `managedBy` laissée à épingler par l'étape du plan, diff vide
refusé, quatrième changement, membre dupliqué refusé sur le texte (Windows PowerShell 5.1 conserve les
membres homonymes, PowerShell 7 ne garde que le dernier : la même demande serait vue comme deux changements
par une jambe et comme un doublon illicite par l'autre), attribut hors des trois autorisés refusé sans que
son nom sorte du contrôle, `managedBy` sans DN, valeur trop longue, caractère de contrôle, aperçu qui omet
le champ de référence ou réécrit la valeur avant, documents relatif, vide, trop gros ou non structuré,
installation relative, paquet non vérifié, identité absente ou nulle, rapport jamais remplacé en silence et
jamais porteur des valeurs candidates. `Run-AttributeDiff114PreflightMutationTests.ps1` frappe ces gardes
sur quinze mutations du consommateur et de son aperçu (soixante-quatre assertions) : la confrontation des
deux jambes, la garde du moteur appliquée aux lignes de l'aperçu, la comparaison ligne à ligne, la fermeture
du texte des refus, le refus des membres homonymes, la taille lue, l'intégrité du paquet, l'identité de
l'objet, le `CreateNew` du rapport, le code de sortie, et les gardes de l'aperçu qui n'ont pas d'équivalent
dans le moteur. Seule l'intégrité du paquet est doublée, sans quoi rien ne serait jouable hors Windows.

Ce qui ne l'est pas : `Get-ADObject`, `Set-ADObject`, DPAPI et `djoin` sont des doubles
locaux. Les droits réels d'écriture, le comportement du rôle contrôleur de domaine, la
résolution effective de la référence `managedBy` par le répertoire et la persistance du
reçu sur un vrai système de fichiers restent à qualifier sur Windows PowerShell 5.1 avec
AD réel. Sont aussi doublées, donc non attestées, les portes qui exigent Windows : garde de
plateforme, intégrité du paquet (`Pesto.exe` factice), socle commun, import du module
ActiveDirectory, ACL du dossier de reçus, `MachineGuid` du registre et magasins `ProgramData`.
La contention du mutex nommé `Global\GP_PostMutation_v1` n'est pas rejouable sur Spark : deux
instances locales de `[Threading.Mutex]` se voient toutes deux accordées hors Windows, si bien que
le refus « Une mutation Pesto est deja en cours. » reste à qualifier sur la plateforme cible — il
n'a volontairement ni fixture ni mutant. Les tests VM et labo n'ont **pas** été lancés dans cette session : ils restent
interdits par les règles de travail, malgré la mention du catalogue.

## 109 — Jonction hors connexion distincte

Activer explicitement `POLICY.AllowOfflineJoin`. La machine cible doit être un poste
Windows installé, élevé, hors domaine, sans renommage en attente. WinPE, les images
Windows hors ligne, la coordination réseau et les exclusions de groupes nécessitant
AD ne sont pas pris en charge par ce parcours. Aucune jonction en ligne de secours
n'est lancée.

L'administrateur de provisionnement fournit un fichier djoin pour **le nom actuel
exact de cette machine**, ainsi que le GUID du compte et son OU. Pesto consomme ce
blob opaque ; les métadonnées déclarées ne sont confirmées dans AD qu'à l'observation
après redémarrage. Il ne crée pas le compte de provisionnement dans cette étape.

```powershell
$r = Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action OfflineImport `
    -BlobPath C:\Provisionnement\poste.odj -ObjectGuid $guid -TargetOU $ou -Execute
# Faire approuver $r.Plan si la politique de campagne l'exige.
Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action OfflineApply `
    -BlobId $r.BlobId -Approval $accord -Execute
# Après le redémarrage volontaire et le retour réseau :
Invoke-PestoExtensionCommand -RuntimeRoot $wad -Action OfflineObserve -BlobId $r.BlobId
```

Le secret est chiffré par DPAPI LocalMachine dans ProgramData, avec une ACL limitée
à SYSTEM et aux administrateurs. Il ne figure ni dans le plan ni dans l'audit.
L'import ne supprime pas le fichier source : l'opérateur doit en gérer la protection
et la suppression selon sa procédure. Aucun transport ou stockage cloud n'est créé.
L'application expire après 24 heures ; cela **n'invalide pas le secret du compte AD**.

L'intention durable précède `djoin /requestodj /localos`. Un fichier plaintext
éphémère est nécessaire à djoin, dans le même dossier protégé ; il est supprimé en
fin de tentative avec la copie chiffrée. Après une coupure brutale, un résidu protégé
peut subsister et doit être retiré par l'administrateur après examen du reçu.
L'identifiant du blob empêche un nouvel import ou une nouvelle application silencieuse.
Le code 3010 signifie seulement qu'un redémarrage est requis. L'observation vérifie
le nouveau démarrage, la machine, le nom, le domaine, le GUID, l'OU et le canal sécurisé
avant de clôturer le reçu. Aucun redémarrage ni `-Repair` automatique.

Ce parcours n'était jouable que par `Run-ExtensionEffectsTests.ps1`, qui appelle
`Import-PestoOfflineBlob`, `Invoke-PestoOfflineApply` et `Get-PestoOfflineObservation`
en direct : `Invoke-PestoExtensionCommand`, seule forme sous laquelle l'opérateur joue
l'extension (`OfflineImport`, `OfflineApply`, `OfflineObserve`), n'était exécutée par
aucune suite. `Run-OfflineJoin109EntryTests.ps1` (quarante-huit cas) n'appelle donc
qu'`Invoke-PestoExtensionCommand` : la lecture et la validation de la configuration,
`ConvertTo-PestoPolicy`, les drapeaux `DEBUG`, `AllowOfflineJoin`, le mode incident et la
session en consultation, l'incompatibilité de coordination et d'exclusion de groupes,
l'exigence `-Execute` de l'import et de l'application, le refus d'observer en exécution,
l'aiguillage du switch, l'empreinte SHA-256 du blob, le scellement du plan, l'intention
durable avant l'appel natif, `Assert-PestoOperationPolicy`, l'approbation de campagne et
la clôture du reçu d'intervention sont joués pour de vrai. `Run-OfflineJoin109EntryMutationTests.ps1`
frappe trente-deux mutations du moteur copié hors sac, dont une paire sur la session en
consultation ; un mutant n'est tué que s'il fait échouer exactement le cas attendu avec un
code de sortie non nul, et la copie témoin doit passer. Restent doublées, donc non
attestées, les portes qui exigent Windows : plateforme, intégrité du paquet, socle commun,
module ActiveDirectory, contrôleur découvert, `Get-ADComputer`, canal sécurisé, DPAPI,
`djoin`, ACL des reçus, `MachineGuid` du registre et magasins `ProgramData`. La contention
du mutex nommé `Global\GP_PostMutation_v1` n'est pas rejouable sur Spark et n'a
volontairement ni fixture ni mutant. Les tests VM et labo n'ont **pas** été lancés dans
cette session : ils restent interdits par les règles de travail, malgré la mention du catalogue.

Le transport lui-même du blob secret restait dans l'angle mort : les deux suites ci-dessus **remplacent** `Invoke-PestoOfflineNative` par un double avant de jouer le point d'entrée, si bien qu'aucune ne l'exécute. Sa seule preuve était trois contrôles de texte sur sa définition (`$nativeSource.Contains('/requestodj')`, `'/loadfile'`, `'/localos'`). Un sondage — dix réécritures du transport appliquées au moteur copié, rejouées contre `Run-OfflineJoin109EntryTests.ps1` — le mesure : neuf sur dix laissent la suite à 48/48 (chemin du blob rendu non cité, racine système non citée, binaire cherché dans le `PATH` au lieu de `System32`, relecture du blob abandonnée, délai et `Kill` supprimés, sortie native publiée à l'appelant, coquille réintroduite, fenêtre rendue visible, stdout héritée) ; seule la disparition d'un des trois littéraux recherchés est vue. Aucune des trente-deux mutations ci-dessus ne frappait cette fonction. `Run-OfflineJoin109NativeTests.ps1` (vingt cas) juge donc ces gardes sur **l'arbre syntaxique du moteur scellé**, parsé par le vrai analyseur PowerShell : les quatre switches et leur ordre, la citation des deux chemins, le binaire résolu sous la racine système, les deux relectures de chemin avant toute création de processus, la garde d'injection, l'absence de coquille et de fenêtre, la redirection des deux sorties natives et leur non-publication, le délai qui borne, tue et prévient « aucun rejeu », le code de sortie rendu plutôt que la sortie, la libération du processus dans son `finally`, l'absence de rappel de la jonction en ligne et d'écriture du blob, l'unicité du lancement et l'unique paramètre. Elle joue **pour de vrai** ce que Spark peut jouer : `Assert-PestoPlainPath` exécutée sur les formes de chemin que le transport lui remet (blob sous lien, `System32` sous lien, chemins clairs acceptés) et l'échec bruyant du transport réel sur une plateforme sans racine Windows, qui ne doit jamais rendre un code de succès. `Run-OfflineJoin109NativeMutationTests.ps1` frappe vingt-deux mutations de ces gardes sur une copie hors sac du moteur, la copie témoin devant passer.

Deux limites sont ici assumées plutôt que masquées. Le **contrat effectif** de `djoin /requestodj /loadfile /windowspath /localos` ne s'observe que sur la cible : sous Linux `[Environment]::GetFolderPath('Windows')` est vide et `Join-Path` refuse la chaîne vide, donc la fonction du produit meurt avant sa première garde — la faire « tourner » ici aurait exigé de substituer la réponse de la plateforme, ce qui n'aurait attesté que de la substitution. Et le produit n'a **pas** été modifié pour ce sous-lot : séparer le transport en trois pièces nommées (construction de la ligne, lancement, couture) l'aurait rendu exécutable sous Linux et aurait permis d'y frapper un délai réellement joué, mais `wad/Pesto-Extensions.ps1` est un composant scellé dont `Pesto.exe` porte l'empreinte et `tools/launcher/build_native.py` exige `clang` et `lld-link`, absents de Spark ; toucher le moteur ici aurait laissé un paquet que `refresh_manifest.py --check` refuse et que le lanceur refuserait de démarrer sur Windows. Le refactor reste à faire sur une machine outillée, avec reconstruction ordonnée (`Build-PestoEngineModule.ps1`, `build_native.py`, `refresh_manifest.py`).

La **jambe d'observation** était le second angle mort, et le plus exposé : c'est elle qui décide si un blob appliqué est clos ou non. Les deux suites ci-dessus **remplacent** `Write-PestoJoinReceipt` par un double (avec `-Depth 14` ou `-Depth 12` là où le produit écrit `-Depth 8`) et n'appellent jamais `Get-PestoOfflineObservation` sur un reçu réconcilié : le seul cas « observation » d'`Run-ExtensionEffectsTests.ps1` échoue pour un motif qui n'est pas la garde jugée, et les cas d'entrée s'arrêtent avant l'observation. Un sondage — douze réécritures des gardes d'observation appliquées au moteur copié, chacune rejouée contre les **deux** suites existantes — le mesure : **dix laissent les deux suites vertes** (drapeau de poste joint, comparaison de domaine, de nom de poste, d'identité de machine, de renommage en attente, de redémarrage — et son affaiblissement en `-ge` —, comparaison de GUID de l'annuaire, deux des trois contrôles croisés du reçu d'intervention) ; les deux autres ne sont vues que par la suite du point d'entrée, à 47/1, et **aucune des douze** n'est vue par `Run-ExtensionEffectsTests.ps1`, qui reste à 57/57 sur les douze — soit vingt-deux des vingt-quatre rejets verts. `Run-OfflineJoin109ObserveTests.ps1` (vingt et un cas) juge donc chaque condition **une par une** par le point d'entrée `Invoke-PestoExtensionCommand -Action OfflineObserve`, le reçu étant écrit, relu et clôturé par les **vraies** fonctions durables (`Write-PestoJoinReceipt`, `Write-PestoAtomicText`, `Read-PestoAutomationJson`, `Read-PestoOfflineRecord`, `Start-PestoIntervention`, `Write-PestoIntervention`, `Read-PestoIntervention`, `Complete-PestoIntervention`) : poste non joint, joint à un autre domaine, nom différent du plan, identité de machine changée, renommage en attente, démarrage identique ou antérieur au démarrage enregistré, objet d'annuaire au GUID différent, renommé ou sorti de l'OU planifiée, canal sécurisé non vérifié, contrôleur découvert pour le domaine planifié et adressé aux deux contrôles, refus d'un reçu qui nomme un autre poste ou un autre domaine ou ne porte pas d'intention de jonction hors connexion, refus d'observer un blob encore à `Imported`, session en consultation qui rapporte sans rien clore, seconde observation qui ne rappelle pas l'appel natif, et absence de publication du matériel du blob. Tout cas incertain doit rendre `Uncertain`, le code 97, `IdentityConfirmed` et `SecureChannel` à faux, `TargetReadOnly` et `ReplayAllowed` à vrai, et **zéro** appel AD, contrôleur, canal ou import. Seuls restent doublés les transports qui exigent Windows : `Import-PestoADModule`, `Get-DomainController`, `Get-ADComputer`, `Test-ComputerSecureChannel`, et l'écriture ACL du reçu par `Write-PestoJoinReceipt` (`Get-Acl` et `Set-Acl` sont absents de ce runtime et les types `DirectorySecurity`, `FileSystemAccessRule`, `SecurityIdentifier` y lèvent). `Run-OfflineJoin109ObserveMutationTests.ps1` frappe trente et une mutations de ces gardes sur une copie hors sac du moteur ; une seule réécriture s'est révélée **équivalente** et n'est pas comptée comme mutant — retirer `$localMatches` de la décision finale ne change rien puisque la jambe d'annuaire n'est jouée que si cette confrontation a réussi — et elle est remplacée par un mutant observable, le redémarrage comparé à l'heure d'écriture de l'enregistrement plutôt qu'au démarrage enregistré. Une mesure incidente vaut pour le mutex resté sans fixture ni mutant : deux lanceurs de harnais lancés en parallèle se sont heurtés au refus du produit « Une mutation Pesto est déjà en cours. », ce qui prouve que la porte `Global\GP_PostMutation_v1` de `Invoke-PestoExtensionCommand` est bien honorée entre processus même hors Windows ; les suites de ce point doivent donc être jouées strictement à la suite, jamais en parallèle.

L'**import du blob secret** restait le troisième angle mort, et le seul des trois qui écrive un secret sur le disque : aucune suite ne juge `Import-PestoOfflineBlob` condition par condition. Les trois suites existantes n'amènent le blob à `Imported` que pour se mettre en état — `Run-OfflineJoin109EntryTests.ps1` ne l'importe qu'une fois et **remplace** `Write-PestoJoinReceipt` par un double (`-Depth 12` là où le produit écrit `-Depth 8`), si bien que le reçu durable écrit à l'import n'a jamais été celui du produit ; `Run-OfflineJoin109ObserveTests.ps1` importe sans contrôler l'import ; `Run-OfflineJoin109NativeTests.ps1` juge le transport sur l'arbre syntaxique. Un sondage — seize réécritures de ces gardes appliquées au moteur copié, chacune rejouée contre les **trois** suites existantes — sépare le couvert du non couvert : **douze sont vues**, presque toutes par la suite du point d'entrée (poste joint 11/48, renommage en attente 8/48, administration 24/48, rôle de domaine 3/48, GUID vide 30/48, périmètre d'OU 5/48, domaine de l'OU 38/48, taille minimale, maximale et conteneur 47/48, empreinte du plan 47/48, domaine du plan 24/48) ; **quatre laissent les trois suites à 48/48, 21/21 et 20/20** : le rejeu qui ne regarde plus le côté secret, la relecture du chemin clair du secret avant son écriture, l'empreinte propre du reçu et l'identité de machine du plan. Ces quatre-là sont rejouées contre `Run-OfflineJoin109BlobTests.ps1` (soixante-huit cas), qui les fait rougir — c'est la mesure, pas l'intention, qui autorise à dire que le sous-lot ferme l'angle. Chaque cas ne viole **qu'une** condition et doit entendre le message de la garde qui refuse, car la même forme est souvent refusée plus loin par une autre garde ; tout refus doit en plus ne laisser **aucune trace** : zéro appel DPAPI, zéro écriture de reçu, magasin vide. Sont jouées pour de vrai `Get-PestoBytesHash`, `Get-PestoOfflinePaths`, `New-PestoPortablePlan`, le scellement par `Get-PestoStableHash` et `ConvertTo-PestoCanonicalValue`, `Write-PestoAtomicText`, `Read-PestoAutomationJson`, `Read-PestoOfflineRecord` et `Assert-PestoPlainPath`, sur de vrais fichiers dans un sac temporaire ; restent doublés `Protect-PestoOfflineBytes` et `Unprotect-PestoOfflineBytes` (DPAPI), `Get-PestoJoinLocalStatus`, l'écriture ACL du reçu, les magasins `ProgramData`, la plateforme, l'intégrité du paquet et le socle commun. `Run-OfflineJoin109BlobMutationTests.ps1` frappe quarante et une mutations de ces gardes sur copie hors sac du moteur, témoin passant. Un piège a été trouvé et corrigé en cours de route : `ConvertFrom-Json` convertit les instants ISO en `DateTime`, que `ConvertTo-PestoCanonicalValue` laisse passer tels quels, si bien que le scellement recompté par la suite divergeait du scellement du produit une exécution sur six ; la suite ne reconvertit plus que les `DateTime` vers leur forme ISO scellée — convertir tout en chaîne aurait fait hacher `"1"` là où le produit hache `1`.

La **ligne d'arguments remise à `djoin.exe`** restait le quatrième angle mort, et le seul où voyage l'aiguillage du secret : `Run-OfflineJoin109NativeTests.ps1` ne jugeait cette ligne que par ses **chaînes littérales**. Un sondage — quatre réécritures du transport appliquées au moteur copié, chacune rejouée contre la suite du transport — le mesure : **deux laissent la suite à 20/20** alors qu'elles permutent les deux opérandes de la concaténation, envoyant le blob clair sous `/windowspath` et la racine système sous `/loadfile`, ou remettent à djoin le chemin de `djoin.exe` à la place du blob ; seule l'apparition d'un cinquième switch est vue. La ligne d'arguments n'avait donc **jamais été calculée par personne** : ses morceaux de texte étaient contrôlés, son assemblage jamais — et le contrat djoin est précisément là, dans l'aiguillage des deux chemins sur leurs deux switchs. `Run-OfflineJoin109NativeLineTests.ps1` (vingt-quatre cas) la **calcule pour de vrai** : l'expression de concaténation est retirée de l'arbre syntaxique scellé et exécutée par le vrai interpréteur PowerShell, avec pour seules entrées les deux chemins que le produit lui remet, par paramètres nommés ; le texte jugé est celui du produit, la suite ne réécrit aucune chaîne djoin et ne fait que compter les champs rendus. La forme de l'expression est jugée avant son résultat — cinq opérandes en alternance, quatre concaténations, aucun nœud inattendu, ce qui refuse notamment qu'une chaîne interpolable remplace la concaténation — puis le résultat : les quatre switches dans l'ordre, chaque chemin cite de son côté, le blob sous `/loadfile` et jamais sous `/windowspath`, la racine sous `/windowspath` et jamais sous `/loadfile`, six champs et pas un de plus sur cinquante-deux formes de chemins acceptées, aucune trace d'identité ni de mot de passe, et aucune dépendance à un état ambiant. Les quatre refus de la garde d'injection sont joués **pour de vrai**, statement complet avec sa condition et son `throw`, sur des chemins réellement porteurs de citation double, retour chariot et saut de ligne ; la garde est en plus montrée **portante** — contournée, une citation dans le chemin du blob ne rend plus les six champs du contrat et `/localos` ne parvient plus à djoin. Ce que cela atteste est borné et dit : la chaîne exacte remise à `ProcessStartInfo.Arguments`, et le fait qu'un chemin hostile ne l'atteint jamais ; non la façon dont `djoin.exe` la décode, qui ne s'observe que sur la plateforme cible. `Run-OfflineJoin109NativeLineMutationTests.ps1` frappe dix-huit mutations sur copie hors sac du moteur, témoin passant : aiguillage des deux chemins, chemin du binaire remis comme blob, double interpolation, cinquième switch, `/localos` retiré, deux citations de chemin retirées, switch `/loadfile` renommé, switches permutés, chaîne interpolable, ligne non remise à l'objet de lancement, garde neutre, garde aveugle au blob, garde aveugle à la racine, garde aveugle aux retours chariot, garde aveugle à la citation de la racine, et garde déplacée après la ligne. Les vingt-deux mutations du harnais de transport existant ne frappaient **aucune** de ces gardes.

La **jambe d'application** restait le cinquième angle mort, et le seul qui rende le secret irréversible : aucune suite ne juge `Invoke-PestoOfflineApply` condition par condition. `Run-ExtensionEffectsTests.ps1` ne la joue que par cinq cas portant sur le rendu d'ensemble ; `Run-OfflineJoin109EntryTests.ps1` **remplace** `Write-PestoJoinReceipt` par un double (`-Depth 12` là où le produit écrit `-Depth 8`) et `Invoke-PestoOfflineNative` par un double ; `Run-OfflineJoin109ObserveTests.ps1` applique un blob pour se mettre en état sans contrôler l'application. Un sondage — dix-huit réécritures des gardes d'application appliquées au moteur copié, chacune rejouée contre les **trois** suites qui jouent déjà cette jambe — le mesure : **six laissent les trois suites à 57/57, 48/48 et 21/21** (le poste joint depuis l'import, le renommage en attente, l'administration perdue, le rôle de domaine apparu, la porte du registre local des opérations en cours, et l'effacement des tampons clairs) ; les douze autres ne sont vues que par la suite du point d'entrée, et sur sept d'entre elles `Run-ExtensionEffectsTests.ps1` reste à 57/57. `Run-OfflineJoin109ApplyTests.ps1` (cinquante et un cas) juge donc chaque condition **une par une** par le point d'entrée `Invoke-PestoExtensionCommand -Action OfflineApply -Execute`, le reçu étant écrit, relu et clôturé par les **vraies** fonctions durables (`Write-PestoJoinReceipt`, `Write-PestoAtomicText`, `Read-PestoAutomationJson`, `Read-PestoOfflineRecord`, `Start-PestoIntervention`, `Write-PestoIntervention`, `Read-PestoIntervention`, `Complete-PestoIntervention`) : refus de rejeu sur les quatre états non `Imported` **et** sur la seconde application réelle d'un blob fraîchement appliqué, les huit conditions du contexte revérifiées à l'application (poste joint, renommage en attente, administration, rôle de domaine, nom du poste, identité de machine, marqueur de configuration, fenêtre du plan), les trois portes (politique d'opération, registre local, approbation de campagne, objet d'approbation non structuré compris), les quatre contrôles du secret (chemin clair sous lien, plafond de deux megaoctets, déprotection unique sur les octets du fichier, empreinte contre le plan scellé), l'ordre de l'irréversibilité — reçu à `Requested` **et** `OfflineJoin='Requested'` dans le registre d'intervention, relus sur disque **à l'instant** où le transport natif est appelé —, le contenu octet à octet du fichier remis à djoin, la destruction des deux fichiers, et la décision rendue (`0` → 3010 et `PendingRestart`, tout autre code → 97 et `Uncertain`, le 3010 rendu par djoin lui-même non confondu avec un succès, délai natif → `Uncertain` sans rejeu). Tout refus doit en plus ne laisser **aucune trace** : zéro appel natif, zéro déprotection, zéro appel d'annuaire, de contrôleur ou de canal sécurisé, registre d'intervention vide, magasin exactement à deux fichiers, secret protégé intact, reçu encore à `Imported`. Sont jouées pour de vrai `Read-PestoOfflineRecord` avec `Assert-PestoClosedObject` et le recomptage du scellement, `Get-PestoOfflinePaths`, `Get-PestoBytesHash`, `Assert-PestoPlainPath` sur les deux chemins, `Assert-PestoOperationPolicy`, `Assert-PestoCampaignApproval`, les quatre fonctions du registre d'intervention, `Write-PestoAtomicText` et l'ouverture `CreateNew` du fichier transitoire ; restent doublés `Unprotect-PestoOfflineBytes` (DPAPI), `Invoke-PestoOfflineNative` (djoin), `Get-PestoJoinLocalStatus`, `Assert-PestoStoredMutationReady`, l'écriture ACL du reçu, les magasins `ProgramData`, la plateforme, l'intégrité du paquet et le socle commun. `Run-OfflineJoin109ApplyMutationTests.ps1` frappe trente-trois mutations de ces gardes sur copie hors sac du moteur, témoin passant ; une seule réécriture s'est révélée **équivalente** et n'est pas comptée comme mutant — retirer `Assert-PestoPlainPath $paths.Plain` avant l'ouverture ne change rien puisque `[IO.FileMode]::CreateNew` refuse déjà l'ouverture d'un lien, quel que soit le sort de sa cible, et que le `finally` rejoue la même garde avant de détruire le fichier (mesuré : la suite reste à 51/51) — et elle est remplacée par deux mutants observables sur la même ligne, le fichier laissé vide et le fichier écrit depuis le matériel protégé au lieu du blob. Le contre-sondage ferme l'angle : rejouées une par une contre la nouvelle suite, les dix-huit réécritures du sondage la font rougir, avec un code de sortie non nul à chaque fois.

La **protection du blob secret** restait le sixième angle mort, et le seul qui décide si la cible pourra relire ce qu'on lui a confié : `Protect-PestoOfflineBytes` et `Unprotect-PestoOfflineBytes`, les deux seules fonctions du moteur qui touchent DPAPI, sont remplacées par un **double** qui xor les octets avec une cle de fixture dans les **quatre** suites qui jouent ce parcours (`Run-OfflineJoin109BlobTests.ps1` lignes 122 et 134) : aucune ne les exécute. Leur seul jugement était un cas sur l'arbre scellé de `Protect` seul (`Run-OfflineJoin109BlobTests.ps1` lignes 627-629 : un appel `Protect`, une lecture `LocalMachine`, zéro lecture `CurrentUser`) et deux contrôles de texte de `Run-OfflineJoin109EntryTests.ps1` (`$protectSource.Contains('ProtectedData') -and $protectSource.Contains('LocalMachine')`). Un sondage — onze réécritures de cette jambe appliquées au moteur copié, chacune rejouée contre les **quatre** suites (copie témoin verte : 48, 68, 51 et 57) — le mesure : **neuf laissent les quatre suites vertes** — ajouter une entropie à la protection, en ajouter à la déprotection, rendre l'un ou l'autre tableau sans la virgule qui empêche sa décomposition, ne plus charger `System.Security` d'un côté ou de l'autre, protéger une autre valeur que le matériel, déchiffrer une autre valeur que le secret, et déchiffrer en re-protégeant. Seules les deux portées sont vues : protéger pour l'opérateur fait rougir BlobTests (67/1) et EntryTests (47/1) ; déchiffrer pour l'opérateur n'est vu que par EntryTests, et seulement parce que le mot `LocalMachine` disparaît de la définition — là encore, c'est une comparaison de chaînes qui tient lieu de garde. C'est pourtant cette portée qui décide si le compte SYSTEM qui rejouera la jonction pourra relire le secret : protégé pour `CurrentUser`, le blob passe l'import sans plainte et l'application échoue des mois plus tard, sur la cible, devant l'opérateur. `Run-OfflineJoin109SecretTests.ps1` (trente cas) juge donc les deux fonctions **nœud par nœud** dans l'arbre du moteur scellé parsé par le vrai analyseur PowerShell : receveur `TypeExpressionAst` sur `[Security.Cryptography.ProtectedData]`, méthode, trois arguments dans l'ordre, portée, entropie, énoncé `Add-Type` placé **avant** l'appel, virgule `ArrayLiteralAst` portant le résultat, absence de seconde commande, contrainte `[byte[]]` du paramètre, et absence de la méthode de l'autre moitié — comptée en `InvokeMemberExpressionAst`, car compter des `MemberExpressionAst` laissait passer un second appel, le comptage tombant à zéro par construction. Elle joue **pour de vrai** ce que Spark peut jouer : le nœud de portée que le produit écrit **vaut** 1 (`LocalMachine`) pendant que `CurrentUser` vaut 0, le nœud d'entropie évalué ne rend rien, l'énoncé `Add-Type` du produit charge réellement l'assemblage, la virgule est montrée **portante** par l'interpréteur, et les deux fonctions scellées **refusent réellement** sur cette plateforme avec « not supported on this platform » au lieu de rendre un faux secret — ce que la suite exige, la disponibilité de DPAPI étant mesurée et non supposée. Sont jugés enfin les **sept** usages que le produit fait de la jambe : protection unique à l'import sur `$bytes` et jamais de déprotection, déprotection unique à l'application sur `$secret` et jamais de re-protection, empreinte calculée après le déchiffrement et sur le matériel déchiffré. `Run-OfflineJoin109SecretMutationTests.ps1` frappe vingt-sept mutations de ces gardes sur copie hors sac du moteur, témoin passant (222/222). Le contre-sondage ferme l'angle : rejouées une par une contre la nouvelle suite, les onze réécritures du sondage la font rougir, avec un code de sortie non nul à chaque fois (de 29/1 à 22/8), la copie témoin restant à 30/30. Deux défauts du banc ont été trouvés en route et corrigés, et ils valent d'être écrits : trois contrôles comparaient une **collection** à une chaîne avec `-cne`, ce qui, la collection étant vide, ne rend rien et laisse passer le test — la réécriture « l'import protège une autre valeur que le matériel » restait à 30/30 ; et neuf scénarios du harnais parenthésaient mal leur concaténation, la virgule liant plus fort que `+`, si bien que `Mutate-Runtime` recevait quatre éléments au lieu de deux et que le mutant n'était pas celui annoncé. Le harnais refuse désormais une liste qui ne tombe pas par paires, une réécriture sans effet sur le moteur, et un mutant que l'analyseur ne lit plus. Ce que le sous-lot n'atteste pas reste écrit : DPAPI n'est jamais réellement joué, donc la portée `LocalMachine` n'est attestée que comme valeur de l'enuméré et comme texte du nœud, non comme le fait que la clef machine du SYSTEM déchiffrera le blob sur la cible — cela ne s'observe que sur Windows réel, que les règles de cette session interdisent.

Références Microsoft : [djoin](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/ff793312%28v%3Dws.11%29),
[contrat et sensibilité du blob ODJ](https://learn.microsoft.com/en-us/windows/win32/api/lmjoin/nf-lmjoin-netrequestofflinedomainjoin).

## Tests locaux

- `Run-ManagedExtensionsTests.ps1` : quatorze cas de scénario administré jouables hors
  Windows — facettes du nom réellement demandé, casse des listes autorisées et des
  verrous, `Required` sans liste autorisée, payloads `ScenarioJson` que le moteur doit
  refuser, aller-retour politique GPO et contrôle avant tout effet. Les cas
  d'approbation de campagne (signature X509, fournisseurs crypto de l'hôte) sont passés
  dans `Run-CampaignApproval117Tests.ps1`, désormais déclarée `Portable` : ses quinze cas
  sont joués sur Spark, la taille de clé y étant mesurée par un adaptateur de fixture
  quand l'hôte la rend en écriture seule (voir plus haut). La garde du produit, elle,
  reste à corriger dans le moteur scellé.
- `Run-CampaignApproval117WeakKeyTests.ps1` : cinq cas portables qui jouent l'invariant
  de sécurité de cette approbation indépendamment de l'état de la garde — une clé de
  1024 bits ne produit jamais d'accord et n'en fait jamais accepter un, même signé
  valablement et portant la bonne empreinte de plan, sur la jambe du plan comme sur
  celle de l'effet exporté. Deux témoins anti-vacuité (campagne non sélectionnée
  acceptée, certificat non épinglé refusé par son message) prouvent que le refus obtenu
  n'est pas un refus par défaut. Banc de mutations rejoué sur copie hors dépôt après y
  avoir appliqué le correctif proposé : retirer la taille des deux gardes, comme figer
  le mesureur à 2048, fait échouer les deux cas visés (3/2). Le mutant qui ignore le
  sens de lecture du module survit ici, faute de jambe positive dans cette suite ;
  cette jambe est jouée par `Run-CampaignApproval117Tests.ps1`, où un accord signé par
  une vraie clé de 2048 bits est accepté.
- `Run-CampaignApproval117MutationTests.ps1` : quatre mutations jouées sur une copie hors
  sac de `wad/Pesto-Policy.ps1` et des quatre autres modules que la suite 117
  point-source, chacune devant faire échouer exactement le contrôle visé avec un code de
  sortie non nul — garde de taille retirée de la jambe de signature, garde de taille
  retirée de la jambe de vérification, mesureur de fixture figé au plancher, mesureur
  figé sous le plancher. Le témoin doit passer ; `cfg.json` n'est jamais copié.
- `Run-ManagedScenario111MutationTests.ps1` : neuf mutations du moteur scellé copié dans
  un dossier temporaire, chacune devant faire échouer exactement le contrôle visé avec
  un code de sortie non nul — gardes `Required`, `Allowed` et `Locked` neutralisées,
  comparaisons rendues insensibles à la casse, verrou hors `Allowed` accepté, facettes
  lues sur le nom actuel au lieu du nom demandé, scénario administré ignoré, et contrôle
  décroché du passage aux effets. Le témoin doit passer.
- `Run-ManagedScenarioPreflight111Tests.ps1` : le point d'entrée
  `Test-PestoManagedScenario.ps1` est joué comme vrai processus enfant sur un paquet
  reconstruit dans un dossier temporaire, avec les modules réels du moteur et du
  validateur ; seule l'intégrité du paquet est doublée. Vingt et un cas : scénario
  publiable, les formes que le moteur refuse, valeurs hors listes, verrou modifié,
  champ obligatoire blanc, champ non admis sans fuite de son nom, candidats illisibles,
  installation relative, double source, intégrité refusée, défaillance de dépendance
  sans détail brut, `-FromRegistry` hors Windows, rapport écrit une seule fois, et
  aucune écriture dans l'installation.
- `Run-ManagedScenario111FormMutationTests.ps1` : cent trente-quatre assertions qui
  frappent les gardes du formulaire sur des copies hors sac. Les gardes de forme étant
  redondantes avec le moteur, elles sont frappées jambe du moteur décrochée ; les gardes
  de valeurs sont frappées à sec, le moteur ne les assurant pas. La paire « moteur durci
  / jambe décrochée » établit que la consultation du moteur n'est pas décorative.
- `Run-ManagedScenario111PlanTests.ps1` : dix-neuf cas de la jambe plans du même point
  d'entrée, joué en processus enfant sur un paquet reconstruit — plans conformes publiés,
  valeur interdite dérivée du nom, champ obligatoire blanc, caractère de contrôle, valeur
  trop longue, verrou, champ de plan non admis sans fuite de son nom, `Objet_GUID` refusé
  avant tout appel AD, fichier de plans illisible, vide, surdimensionné ou surabondant.
- `Run-ManagedScenario111PlanMutations.ps1` : cent soixante-dix assertions — onze mutations
  tuées de la jambe plans (garde du moteur décrochée, garde du formulaire affaiblie,
  dérivation du nom remplacée, forme, taille et nombre de plans non bornés, garde d'identité
  éteinte, et côté module liste autorisée, obligatoire aveugle aux blancs et contrôle des
  caractères de contrôle éteints), chacune frappée seule quand l'autre jambe ne la masque
  pas et en paire quand aucune ne doit rester, plus le test différentiel de cent formes qui
  confronte le verdict publié aux deux gardes appelées en direct, avec contrôle de non-vacuité.
- `Run-ExtensionEffectsTests.ps1` : cinquante-sept cas des attributs AD contre le moteur
  scellé — diff, forme et taille des valeurs, `managedBy` épinglé sur son GUID, refus sur
  état modifié, cible hors périmètre OU ou hors domaine, plan expiré ou étranger,
  intention durable, écriture unique, relecture, reprise par observation, refus de rejeu,
  politique moteur, approbation de campagne et échec de persistance.
  Le cycle de vie et le schema des recus sont ceux du produit.
  Les transports AD, DPAPI, djoin et ACL sont des doubles ; ce n'est pas une recette Windows.
- `Run-OfflineJoin109EntryTests.ps1` : quarante-huit cas du parcours hors connexion joués
  **uniquement** par `Invoke-PestoExtensionCommand` — politique `AllowOfflineJoin`, mode
  incident, session en consultation, drapeaux `DEBUG`, coordination et exclusions de groupes
  incompatibles, exigence `-Execute` de l'import et de l'application, refus d'observer en
  exécution, état local du poste (déjà joint, renommage en attente, non élevé, rôle
  contrôleur de domaine), GUID et OU provisionnés, taille du blob, import unique, garde du
  reçu ODJ et empreinte du plan, contexte d'application et échéance de vingt-quatre heures,
  court-circuit d'une demande déjà enregistrée, taille du secret, contrôle du blob déchiffré,
  création exclusive du fichier transitoire, intention durable avant `djoin`, nettoyage du
  clair et du secret, observation (reboot, nom, GUID, OU, canal sécurisé, reçu d'intervention
  incohérent, reçu clos une seule fois et jamais en consultation), et vérification que le
  contrat `djoin /requestodj /loadfile /localos` ne charrie aucun secret. Les compteurs
  d'appels prouvent qu'aucune lecture d'annuaire n'a lieu quand elle est interdite.
- `Run-OfflineJoin109EntryMutationTests.ps1` : trente-deux mutations du moteur scellé copié
  dans un dossier temporaire, chacune devant faire échouer exactement le contrôle de sa garde
  avec un code de sortie non nul, témoin passant. Frappées : les deux sens de l'ouverture du
  contexte en consultation, l'exigence `-Execute`, l'aiguillage du switch vers l'import et
  l'application, la grammaire de l'identifiant de blob, l'état local du poste, le GUID et l'OU
  provisionnés, la taille du blob, l'import unique, la garde du reçu, l'empreinte et le sceau
  du plan, le contexte d'application et l'échéance, le court-circuit de rejeu, la taille du
  secret, la comparaison du blob déchiffré, la création exclusive du fichier transitoire,
  l'intention durable avant l'appel natif, le nettoyage des fichiers, la garde de blob non
  appliqué, le canal sécurisé, l'identité dans l'annuaire, la cohérence du reçu d'intervention,
  `Assert-PestoOperationPolicy` et l'approbation de campagne avant `djoin`. La session en
  consultation est frappée en paire : supprimée à un seul des deux endroits, l'autre jambe
  masquerait la mutation.
- `Run-OfflineJoin109NativeTests.ps1` : vingt cas sur le transport scellé du blob secret, jugés par
  le vrai analyseur PowerShell (ligne de commande et ordre des quatre switches, citation des deux
  chemins, gardes de chemin antérieures à toute création de processus, absence de coquille et de
  fenêtre, redirection et non-publication des deux sorties natives, délai qui borne et tue, code de
  sortie rendu, libération dans le `finally`, unicité du lancement, unique paramètre), plus trois
  exécutions réelles de `Assert-PestoPlainPath` sur les formes de chemin que le transport lui remet et
  l'échec réel du transport sur une plateforme sans racine Windows. Aucun `djoin`, aucun Windows,
  aucune VM.
- `Run-OfflineJoin109NativeMutationTests.ps1` : vingt-deux mutations du transport sur copie hors sac
  du moteur, chacune devant faire échouer exactement le contrôle visé avec un code de sortie non nul,
  témoin passant. Frappées : un des quatre switches, la citation de chacun des deux chemins, le binaire
  hors `System32`, la suppression de chacune des trois gardes, la coquille, la fenêtre, la sortie native
  héritée puis rendue puis publiée, le délai absent puis dérisoire puis sans `Kill`, le message du
  dépassement, la libération hors `finally`, le rappel de la jonction en ligne, l'écriture du blob
  clair, l'appel encadré par une boucle et l'ajout d'un paramètre de secret.
- `Run-OfflineJoin109ObserveTests.ps1` : vingt et un cas de la jambe d'observation, joués un par un
  par `Invoke-PestoExtensionCommand -Action OfflineObserve` sur le moteur scellé, le reçu étant écrit,
  relu et clôturé par les vraies fonctions durables (`Write-PestoJoinReceipt`, `Write-PestoAtomicText`,
  `Read-PestoAutomationJson`, `Read-PestoOfflineRecord`, `Start-PestoIntervention`,
  `Write-PestoIntervention`, `Read-PestoIntervention`, `Complete-PestoIntervention`) : confrontation
  réconciliée qui clos le reçu, poste non joint, joint à un autre domaine, nom différent du plan,
  identité de machine changée, renommage en attente, démarrage identique puis antérieur au démarrage
  enregistré, objet d'annuaire au GUID différent, renommé, sorti de l'OU planifiée, canal sécurisé non
  vérifié, contrôleur découvert pour le domaine planifié et adressé aux deux contrôles, refus d'un reçu
  nommant un autre poste ou un autre domaine ou sans intention de jonction hors connexion, refus
  d'observer un blob encore à `Imported`, session en consultation qui ne clos rien, seconde observation
  qui ne rappelle pas l'appel natif, absence de publication du matériel du blob. Chaque cas incertain
  exige `Uncertain`, le code 97, les deux drapeaux à faux, la lecture seule et le refus de rejeu, et
  zéro appel AD, contrôleur, canal ou import. `Import-PestoADModule`, `Get-DomainController`,
  `Get-ADComputer`, `Test-ComputerSecureChannel` et l'écriture ACL du reçu restent des doubles locaux.
- `Run-OfflineJoin109ObserveMutationTests.ps1` : trente et une mutations de ces gardes sur copie hors
  sac du moteur, chacune devant faire échouer exactement le contrôle visé avec un code de sortie non
  nul, témoin passant. Frappées : chacune des six conditions de la confrontation locale et son
  affaiblissement en `-ge`, les trois comparaisons de l'objet d'annuaire, la décision qui n'exige plus
  que deux jambes, la jambe d'annuaire jouée à tort, l'import du module, l'adressage du canal et de la
  relecture AD, la découverte du contrôleur, les trois contrôles croisés du reçu d'intervention, la
  session en consultation, la clôture durable du reçu, l'état, la phase, le code de résultat et le
  vérificateur du reçu, le code de sortie, la mention en lecture seule, le rejeu annoncé et le refus
  d'un blob jamais appliqué. Une réécriture équivalente (retirer `$localMatches` de la décision, sans
  effet puisque la jambe d'annuaire n'est jouée qu'après sa réussite) est écartée et documentée plutôt
  que comptée comme mutant tué.
- `Run-OfflineJoin109BlobTests.ps1` : soixante-huit cas de l'**import du blob secret**, joués un par un
  par `Invoke-PestoExtensionCommand -Action OfflineImport -Execute` sur le moteur scellé, chaque cas ne
  violant qu'une seule garde et devant entendre le message de cette garde : éligibilité locale (poste déjà
  joint, renommage en attente, opérateur non administrateur, contrôleur de domaine, contrôleur de domaine
  de repli, rôle interopérable, poste autonome et serveur membre acceptés), compte provisionné (GUID vide,
  GUID vide malgré une OU par ailleurs valide, OU hors du périmètre configuré, OU d'une autre forêt,
  configuration dont les OU quittent le domaine configuré, GUID et OU valides acceptés), forme du matériel
  (dossier remis comme blob, blob vide, un octet au-dessus du plafond d'un mégaoctet, plafond exactement
  atteint et blob d'un octet acceptés, blob remis sous lien symbolique puis sous jonction), rejeu (même
  blob importé deux fois, rejeu refusé quand seul le secret protégé reste sur disque, quand seul le reçu
  d'état y reste, blob différent importé sans gêner le premier), secret (DPAPI demandé une seule fois sur
  les octets du fichier et non son chemin, fichier protégé qui rend le blob à la décodation, rien dans le
  magasin ne porte le blob en clair ni le secret dans le reçu, la source de l'opérateur n'est jamais
  supprimée, le résultat rendu à l'opérateur ne porte jamais le matériel, échec de protection sans reçu ni
  secret persistés), reçu et plan scellés (schéma durable fermé, demande non encore appliquée, scellement
  vérifié indépendamment du produit, plan de jonction hors connexion pour le domaine configuré, identité de
  la machine qui a demandé l'import, les trois chemins du magasin), identifiant (majuscules, un caractère
  de moins ou de trop, lettre non hexadécimale, vide, évasion hors du magasin, fichier d'un autre magasin,
  identifiant valide rendant les trois chemins) et relecture du reçu (schéma, mode, identifiant, état,
  empreinte, champ en trop ou manquant du reçu et du plan, scellement altéré, `Action`, `Purpose`, domaine
  et identité de machine re-scellés, nom de poste impossible, renommage caché, conteneur plutôt qu'OU,
  schéma du plan). Tout refus doit en plus ne laisser **aucune trace** : zéro appel DPAPI, zéro écriture de
  reçu, magasin vide. Sont jouées pour de vrai `Get-PestoBytesHash`, `Get-PestoOfflinePaths`,
  `New-PestoPortablePlan`, `Get-PestoStableHash` avec `ConvertTo-PestoCanonicalValue`,
  `Write-PestoAtomicText`, `Read-PestoAutomationJson`, `Read-PestoOfflineRecord` et
  `Assert-PestoPlainPath` ; restent doublés `Protect-PestoOfflineBytes` et `Unprotect-PestoOfflineBytes`
  (DPAPI), `Get-PestoJoinLocalStatus`, l'écriture ACL du reçu, les magasins `ProgramData`, la plateforme,
  l'intégrité du paquet et le socle commun.
- `Run-OfflineJoin109BlobMutationTests.ps1` : quarante et une mutations de ces gardes sur copie hors sac du
  moteur, chacune devant faire échouer exactement le contrôle de sa garde avec un code de sortie non nul,
  témoin passant. Frappées : les quatre conditions d'éligibilité locale, les trois du compte provisionné,
  les trois de forme du matériel, les deux du rejeu, la relecture du chemin clair du secret avant écriture,
  le scellement du plan à l'import, la portée machine de la protection, la mention du matériel du blob dans
  le reçu, et les gardes de relecture (schéma, mode, identifiant, état, deux empreintes, deux objets fermés,
  cible, `Action`, `Purpose`, domaine, identité de machine).
- `Run-OfflineJoin109NativeLineTests.ps1` : vingt-quatre cas de la **ligne d'arguments réellement calculée**
  par le transport du blob secret. L'expression de concaténation est retirée de l'arbre syntaxique scellé et
  exécutée par le vrai interpréteur PowerShell, avec pour seules entrées les deux chemins remis par le produit :
  forme de l'expression (cinq opérandes en alternance, quatre concaténations, aucun nœud inattendu), résultat
  exact (les quatre switches dans l'ordre, les deux chemins cités chacun des deux côtés), aiguillage (blob sous
  `/loadfile` et jamais sous `/windowspath`, racine sous `/windowspath` et jamais sous `/loadfile`, chaque chemin
  interpolé une seule fois), six champs et pas un de plus sur cinquante-deux formes de chemins acceptées, absence
  d'identité et de mot de passe, indépendance de tout état ambiant. Les quatre refus de la garde d'injection sont
  réellement exécutés, statement complet avec condition et `throw`, sur citation double, retour chariot et saut de
  ligne ; la garde est montrée portante, contournée elle laisse une citation détruire la ligne et `/localos`
  disparaître. Atteste la chaîne remise à `ProcessStartInfo.Arguments`, non le décodage par `djoin.exe`.
- `Run-OfflineJoin109NativeLineMutationTests.ps1` : dix-huit mutations de cette ligne sur copie hors sac du
  moteur, chacune devant faire échouer exactement le contrôle de sa garde avec un code de sortie non nul, témoin
  passant. Frappées : permutation des deux chemins entre `/loadfile` et `/windowspath`, chemin du binaire remis
  comme blob, racine remplacée par le blob, double interpolation du blob, cinquième switch ajouté, `/localos`
  retiré, citation du blob retirée, citation de la racine retirée, `/loadfile` renommé, switches permutés, chaîne
  interpolable substituée à la concaténation, ligne non remise à l'objet de lancement, garde neutre, garde aveugle
  au blob, garde aveugle à la racine, garde aveugle aux retours chariot du blob, garde aveugle à la citation de la
  racine, garde déplacée après la construction de la ligne.
- `Run-OfflineJoin109ApplyTests.ps1` : cinquante et un cas de la **jambe d'application du blob secret**, joués un
  par un par `Invoke-PestoExtensionCommand -Action OfflineApply -Execute` contre le moteur scellé, le reçu durable et
  le registre d'intervention étant écrits, relus et clôturés par les vraies fonctions du produit. Refus de rejeu sur
  les quatre états non `Imported` et sur la seconde application réelle ; les huit conditions du contexte revérifiées
  (poste joint, renommage en attente, administration, rôle de domaine, nom du poste, identité de machine, marqueur de
  configuration, fenêtre du plan) ; les trois portes (politique d'opération, registre local des opérations en cours,
  approbation de campagne, objet d'approbation non structuré) ; les quatre contrôles du secret (chemin clair sous
  lien, plafond de deux megaoctets, déprotection unique sur les octets du fichier, empreinte contre le plan scellé) ;
  l'ordre de l'irréversibilité, le reçu à `Requested` et `OfflineJoin='Requested'` dans le registre étant relus sur
  disque à l'instant où le transport natif est appelé ; le contenu octet à octet du fichier remis à djoin ; la
  destruction des deux fichiers et l'effacement des deux tampons ; la décision rendue selon le code natif (0 → 3010
  et `PendingRestart`, autre code → 97 et `Uncertain`, 3010 de djoin non confondu avec un succès, délai natif →
  `Uncertain` sans rejeu). Tout refus doit en plus ne laisser aucune trace : zéro appel natif, zéro déprotection,
  zéro appel d'annuaire, de contrôleur ou de canal, registre vide, magasin à deux fichiers, secret intact, reçu
  encore à `Imported`. DPAPI, djoin, ACL, AD, registre local et magasins restent des doubles : ce n'est pas une
  recette Windows.
- `Run-OfflineJoin109ApplyMutationTests.ps1` : trente-trois mutations de ces gardes sur copie hors sac du moteur,
  chacune devant faire échouer exactement le contrôle de sa garde avec un code de sortie non nul, témoin passant.
  Frappées : rejeu accepté et rejeu annoncé rejouable, les huit conditions du contexte une par une, les trois portes,
  chemin du secret sous lien et plafond de taille, empreinte contre le plan, contenu du fichier remis à djoin (vide,
  écrit depuis le matériel protégé) et ouverture `CreateNew` rendue `Create`, intention durable et registre écrits
  après l'appel natif, destructions retirées, tampons non effacés, état, code rendu et redémarrage décidés sans le
  code natif, effet rendu identique à une jonction en ligne. La réécriture qui retirait `Assert-PestoPlainPath
  $paths.Plain` avant l'ouverture est mesurée équivalente (la suite reste à 51/51, `CreateNew` refusant déjà un lien)
  et n'est pas comptée comme mutant. Le sac du harnais est posé à côté du dépôt et non dans le répertoire
  temporaire système : `Write-PestoAtomicText` flush chaque reçu sur le disque et ce répertoire est mesuré quatorze
  fois plus lent sur cette machine (dix mille dossiers hérités des campagnes précédentes), ce qui faisait dépasser
  au harnais le délai de 900 s de la campagne portable — 18 min 54 s avec le sac dans `/tmp`, 6 min 33 s à côté du
  dépôt ; à défaut d'écriture à cet endroit, le harnais retombe sur le répertoire temporaire système.
- `Run-OfflineJoin109SecretTests.ps1` : trente cas qui jugent `Protect-PestoOfflineBytes` et `Unprotect-PestoOfflineBytes` dans l'arbre syntaxique du moteur scellé, parsé par le vrai analyseur PowerShell — receveur, méthode, ordre et nature des trois arguments, portée, entropie, énoncé `Add-Type` avant l'appel, virgule portant le résultat, absence de seconde commande, contrainte de type du paramètre, absence de la méthode de l'autre moitié, et les sept usages que le produit en fait à l'import et à l'application. La portée et l'entropie sont réellement évaluées par l'interpréteur (1 contre 0, rien), l'énoncé `Add-Type` réellement exécuté, et les deux fonctions réellement refusées sur cette plateforme avec « not supported on this platform » : aucun DPAPI simulé, aucun faux secret rendu.
- `Run-OfflineJoin109SecretMutationTests.ps1` : vingt-sept mutations de ces gardes sur copie hors sac du moteur, chacune devant faire échouer exactement le contrôle de sa garde avec un code de sortie non nul, témoin passant (222/222). Frappées : portée machine des deux moitiés, absence d'entropie des deux côtés, ordre des trois arguments, méthode appelée (déchiffrer n'est pas re-protéger), chargement de l'assemblage avant l'appel, virgule qui empêche le tableau de se décomposer, nature du matériel remis, contrainte de type du paramètre, absence de toute publication, et les sept usages du produit. Le harnais se contrôle lui-même : liste de réécriture par paires, réécriture réellement changée, moteur mutant lisible par l'analyseur — trois défauts qu'il a lui-même révélés en cours de route.
- `Run-AttributeEffects114MutationTests.ps1` : cent trente et une assertions — trente-deux
  mutations du moteur scellé copié dans un dossier temporaire, chacune devant faire échouer
  exactement le contrôle de sa garde avec un code de sortie non nul (validation des valeurs,
  DN de `managedBy`, diff vide ou dupliqué, attribut hors liste, référence inattendue ou
  absente, périmètre OU, domaine et GUID de la cible, intégrité, expiration, empreinte de
  configuration, machine et domaine du plan, valeur avant obsolète, cible déplacée,
  référence remplacée, relecture après écriture, politique moteur, approbation de campagne,
  ordre de persistance du reçu, reçu confirmé en session en lecture seule, liste d'attributs
  élargie, observation qui ne compare plus ou annonce un rejeu). Le témoin doit passer.
- `Run-OptionalIntegrationsTests.ps1` : validateur consultatif du formulaire aligné sur
  le moteur par un test différentiel, plus attributs, export audit et modèles GPO XML.
- Le manifeste et le lanceur natif couvrent les deux nouveaux scripts et le moteur généré.
