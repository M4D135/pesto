# Séquence AD native préparée — 25 octobre 2026

**Préparation seulement. Aucun appel Windows/AD exécuté par ce lot.** L’orchestrateur libère la GUI avant une action, lance une seule demande, lit son code de sortie et ses preuves, puis décide de l’étape suivante. Aucune boucle, tâche planifiée, reprise, mutation de DC, service, compte partagé ou redémarrage implicite.

## Identité relue

- VM BIOS `9b2ad4f0-0506-4f58-aed2-c43ac1973516` ; membre `labo.local`, rôle 1.
- Nom d’origine `P111301VA765158`, GUID AD `b4797c9c-d790-4797-bf71-424a57acb36e`, UAC 4096, protection false.
- Paris : `OU=Paris,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local`.
- Lyon : même suffixe avec `OU=Lyon`.
- V1 : `C:\PestoQual_20261018\candidate-final\PROD\wad`, cfg SHA256 `B33C77125445A8A1EE9ED4EDC24F8AF03007ACAB64C73672EB72D43145E51379`.
- Nommage : type P / site VA / service 765, tirage aléatoire actif. Le nom de retour ne peut donc pas être garanti par un nouvel aperçu produit.

Preuves relues dans `v2/logs/qualification/` : `codex-canary-before-20261025.json` (SHA256 `30939a4e9044a80e024a5c2a11ffb3bf9e055601f4d12681326ac646a5920a46`) et `codex-ad-read-green-20261025.json` (`1d3461f126681345709404a44408d94d3f959e964d6235f593f3caa3a932ba75`). Ce sont des lectures, pas des mutations qualifiées.

## Lancement

Publier/copier le **répertoire complet** `v2/artifacts/ad-harness` vers `C:\Temp\PestoAdQualification-20261025`, y compris `requests`. Le harnais est distinct du pack GUI.

L’orchestrateur ouvre une console élevée par UAC sous `labadmin`, sans mot de passe en argument/fichier de requête. Chaque demande `explicitCredential:true` ouvre CredUI pour `LABO\tech.pesto`. Le secret reste en mémoire et entre processus par DPAPI CurrentUser/stdin. Ne jamais remplacer ce choix par le compte local élevé pour les lectures AD.

Depuis cette console, chaque ligne ci-dessous est une invocation **séparée**. Ne pas coller la séquence entière ; vérifier les preuves entre les lignes. Afficher `$LASTEXITCODE` après chaque invocation. Codes : 0 lecture/préparation/succès confirmé ; 10 redémarrage requis ; 20 refus/incertain/vérification insuffisante ; 2 garde ou incident. Tout 20/2 arrête la séquence.

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\00-inspect-paris.json'
```

Inspection initiale : même GUID, Paris, UAC4096, protection false, nom actif/configuré original, domaine et canal sécurisé. Les preuves sortent dans un nouveau sous-dossier de `C:\Users\Public\pesto-v2-ad-native`.

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\01-negative-paris.json'
```

Attendre quatre refus sans envoi : join distant, rename sans aperçu, OU étrangère, confirmation incorrecte.

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\02-move-lyon-prepare.json'
```

Préparation seule. Contrôler le GUID/source Paris/cible Lyon et le plan de retour. Puis, seulement après cette revue :

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\03-move-lyon-execute.json'
```

Attendu : un reçu move code30/succeeded, même GUID, Lyon, protection false. Lire le reçu durable et le snapshot indépendant.

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\04-inspect-lyon.json'
```

Cette nouvelle inspection précède obligatoirement le retour. Si l’OU ou le GUID diffère, ne pas corriger les JSON pour contourner la garde.

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\05-move-paris-execute.json'
```

Retour par **nouveau plan** moteur. Puis inspection indépendante :

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\06-inspect-return-paris.json'
```

Uniquement après retour Paris confirmé :

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\07-rename-va765-execute.json'
```

Le harnais appelle names.preview, relit la disponibilité du nom, puis prépare et envoie une seule fois. Conserver le `newName` **observé** et le `receiptId` exact du reçu code20/pendingRestart ; ne pas les calculer. L’orchestrateur redémarre ensuite uniquement la VM identifiée, manuellement et séparément.

Copier les deux fichiers `.template.json` vers de nouveaux JSON et remplacer `expectedComputer`/`computer` par ce `newName`, et `receiptId` par l’identifiant observé. Conserver les autres champs. Les placeholders rendent les modèles inutilisables tant qu’ils ne sont pas renseignés.

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\08-reconcile-after-reboot.json'
```

Il faut `verified:true`, status succeeded, restartRequired false, identité machine/AD/GUID/OU/canal et boot postérieur prouvés. Une réponse insuffisante ne lève aucune barrière. Sans cela le cleanup refusera.

## Retour explicite au nom d’origine, harnais seulement

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\09-restore-original-name.json'
```

Cette action **n’est pas une API produit**. Sous le mutex GP, elle lit aussi directement `GP\Join\receipt.json` et `GP\Operations\direct.json`, puis les relit immédiatement avant le processus natif ; fichiers invalides, liens/jonctions, phases non terminales ou accès illisible refusent le retour. Un acquittement ne vaut que selon le validateur strict V1 partagé. Elle exige la confirmation distincte `RESTORE ORIGINAL NAME P111301VA765158`, le plan de retour, le compte AD natif explicite et le reçu rename Pesto déjà réconcilié depuis ce nom d’origine vers le nom courant. Elle refuse tout historique illisible/incomplet ou reçu encore non résolu.

Gardes indépendantes avant l’appel : BIOS et GUID constants, poste membre local labo.local rôle1, élévation, canal sain, nom actif/configuré/AD identique au nom confirmé de cette qualification, OU Paris, protection false, UAC4096, nom original libre. Le script constant refait les gardes immédiatement avant son unique `Rename-Computer -NewName P111301VA765158 -DomainCredential ...`, sans ComputerName distant et sans Restart.

Avant le processus natif : mutex global GP ; création exclusive et flush du reçu `C:\ProgramData\GP\Qualification\RestoreName\<receiptId>.json` sous ACL SYSTEM/Administrateurs, chemins sans jonction. Le fichier reste conservé et bloque toute nouvelle tentative avec le même reçu, quel que soit l’OutputRoot. Il est complété PendingRestart seulement si même GUID/Paris/protection/UAC, nouveau nom AD et nom Windows configuré original sont relus. Sinon Uncertain/Refused : arrêt, pas de rejeu ni suppression du marqueur.

Correction du 26 octobre : les interventions historiques V1 `pendingRestart` ne sont pas assimilées aux deux barrières actives GP. Elles restent inchangées et sont consignées séparément seulement si leur origine V1 et identifiant sont stricts, leur date précède le boot observé et le reçu courant vérifié, et ni leur ancien ni leur nouveau nom ne correspondent au nom actuel. La validation exacte du canari et du reçu réconcilié précède cette distinction. Un reçu V2 en attente, une opération envoyée/incertaine/partielle, un historique ambigu, un reçu V1 courant ou une barrière brute non terminale restent bloquants. Aucun historique n’est acquitté ou réécrit pour permettre le retour.

Après code10, l’orchestrateur redémarre manuellement uniquement cette VM, puis :

```powershell
& 'C:\Temp\PestoAdQualification-20261025\Pesto.AdQualification.exe' 'C:\Temp\PestoAdQualification-20261025\requests\10-inspect-restored-after-reboot.json'
```

Vérifier nom actif/configuré original, GUID original, Paris, UAC4096/protection false, domaine/canal et boot nouveau. Conserver cette preuve à côté du reçu cleanup (qui garde son observation antérieure PendingRestart ; aucun JSON n’est édité pour simuler la preuve finale).

## Retour de la campagne renameMove du 28 octobre 2026

Cette séquence concerne seulement le reçu `receipt-50a635a9b3ee46138c9fc231bcff83af` : le canari original a été renommé en `P111301LY765715` et déplacé à Lyon, puis le reçu a été réconcilié après redémarrage. Le retour C14 ne pouvait pas s'appliquer : il exigeait un renommage simple en VA et une OU déjà revenue à Paris. Les refus antérieurs restent des refus, sans mutation ni succès rétroactif.

L'orchestrateur doit relire l'état courant et les deux barrières GP avant de préparer `11-return-lyon-to-paris-prepare.json`. Cette demande a `execute:false` : elle ne déplace rien. Après revue du plan, créer une demande distincte d'exécution avec confirmation `EXECUTE PESTO CANARY`. Le produit exécute seulement le déplacement de Lyon vers Paris, même GUID et même nom LY, sans redémarrage. Recueillir le nouvel identifiant de reçu `move`, son statut réussi et la preuve indépendante Paris/protection false.

Remplacer ensuite le seul placeholder `returnMoveReceiptId` des modèles `12-restore-recorded-renamemove-prepare.template.json` et `13-restore-recorded-renamemove-execute.template.json` par cet identifiant observé. Les modèles sont refusés tant que le placeholder subsiste. La préparation 12 ne réserve aucun marqueur et ne lance aucune commande native. L'exécution 13 reste une action séparée, après revue des preuves.

Le retour accepte uniquement le nom LY715 et le reçu renameMove exact ci-dessus. Il exige également un reçu ultérieur `move` confirmé de Lyon vers Paris pour le même nom/GUID, sans redémarrage requis. **Avant tout appel à l'adaptateur**, les deux fichiers bruts sont ouverts en lecture bornée, sur chemins sans lien ni jonction : identifiants, type/code/phase, GUID/machine/domaine/DC, noms/OU, état local et ordre des dates sont contrôlés. Tout état Entra autre qu'absent, `NotRequested` ou `Skipped` est refusé ; une preuve Entra liée ou une activité en cours est également refusée. Ainsi un mauvais identifiant retour ne peut pas déclencher l'inspection Entra implicite de `ReadReconciliation`, même en préparation. Les handles Windows restent ouverts sans partage écriture/suppression jusqu'à la fin du retour.

Les deux reçus sont ensuite relus par l'adaptateur natif : domaine, identité machine, canal, noms actif/configuré, GUID, Paris et protection doivent être confirmés. Le reçu renameMove doit prouver un boot ultérieur à son boot initial. Les empreintes sont liées aux fichiers bruts validés et relues juste avant le seul appel natif, sous mutex GP. La dernière lecture des barrières V1 suit ces observations, immédiatement avant le lancement natif. Une dérive ou une lecture incomplète interdit l'appel.

Le script natif conserve ses gardes et fait uniquement `Rename-Computer` vers `P111301VA765158` ; il ne déplace aucun objet. Son marqueur durable est lié au reçu renameMove, distinct du marqueur C14. Aucun marqueur ni historique n'est supprimé, acquitté ou réécrit pour obtenir l'autorisation. Après code 10, redémarrer séparément la seule VM puis exécuter une nouvelle inspection, avec contrôle indépendant du SID original en plus du GUID, de Paris, des noms et du canal. Un refus ou résultat incertain arrête la séquence ; aucune répétition automatique.

Ce complément ne qualifie pas la jonction avec création d'un nouveau compte et n'autorise aucune sortie du domaine.

## Jonction / workgroup : préparation et point d’arrêt

Le poste est actuellement joint et le compte original existe. La lecture actuelle permet de qualifier le refus « déjà joint », sans sortir du domaine. **Aucune demande exécutable de sortie/jonction n’est fournie dans ce lot.**

Une jonction positive Pesto calcule un nom libre puis Add-Computer ; elle peut créer un nouvel objet AD/GUID. Pour préserver le GUID original b479…, il ne suffit pas de renommer ce nouvel objet vers le nom initial : l’ancien objet existe, et le compte machine original peut avoir été désactivé lors de la sortie. Le cleanup restoreName refuse précisément un nouveau GUID et ne constitue pas un retour de jonction.

Avant toute sortie, l’orchestrateur doit démontrer par lectures et configuration déjà autorisées : accès local labadmin utilisable après reboot ; droit de sortie/jonction de **cette VM** ; état, OU, protection, SID/GUID et droit de réutilisation du compte machine original ; absence de barrières ; DNS/DC/heure et accès AD explicite depuis workgroup ; plan de retour capable de réassocier la VM à l’objet original sans supprimer/recréer cet objet ni toucher tech.pesto/labadmin ou un compte partagé. Aucun reset de compte utilisateur, restauration de VM/DC ou changement de topologie n’est une solution de repli de ce protocole.

Si ces préconditions sont démontrées, écrire séparément les demandes concrètes bornées et leur retour : sortie manuelle autorisée de la seule VM, reboot, état workgroup constaté, nom local temporaire libre (ancien nom AD occupé ⇒ join.alreadyJoined attendu), préparation names.preview avec compte AD explicite, une jonction, reboot, réconciliation et preuve du nouveau GUID. Puis retour distinct au compte machine original selon la procédure démontrée ; inspection finale du GUID b479… obligatoire. Ne pas avancer jusqu’à cette étape tant que la réutilisation exacte de l’identité originale n’est pas concrètement démontrée. La jonction positive reste **non qualifiée** dans ce lot préparatoire.

## Validation de développement de ce lot

Tests purs isolés : 28/28 gardes de retour et 20/20 contrôles des deux barrières V1 brutes (VM/GUID/domain/member/DC/élévation/canal/nom/OU/protection/UAC/collision/reçu/confirmation). Log `logs/ad-harness-v1-guards-20261025.log`. Ce test n’appelle aucune API Windows et ne prouve pas Rename-Computer.

Publication harnais seulement, sans recompilation App/Core :

```sh
DOTNET_SYSTEM_NET_DISABLEIPV6=true ~/.dotnet/dotnet publish v2/tools/qualification/ad-harness/Pesto.AdQualification.csproj -c Release -r win-x64 --self-contained true --no-restore -p:BuildProjectReferences=false -p:UseSharedCompilation=false -o v2/artifacts/ad-harness
```
