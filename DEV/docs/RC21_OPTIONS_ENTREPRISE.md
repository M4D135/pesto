# Options d’entreprise RC21

## Politique séparée de l’apparence

La clé de premier niveau `POLICY` du cfg contient des paramètres métier. Exemple volontairement inactif ; il n’est pas une configuration complète de domaine :

```json
{
  "Schema": 1,
  "ExcludedNames": [],
  "ExcludedOUs": [],
  "ExcludedGroupGuids": [],
  "CoordinationRoot": "",
  "CoordinationRequired": false,
  "AllowPasswordTaskFallback": false,
  "AllowPrecreatedJoin": false,
  "AllowOfflineJoin": false,
  "MaxReaders": 4,
  "ReadAttempts": 2,
  "MaxBatch": 200
}
```

Les booléens sont de vrais booléens JSON, pas « true » entre guillemets. MaxReaders : 1 à 8, ReadAttempts : 1 à 3, MaxBatch : 1 à 200. Ces limites sont locales au processus, pas une coordination de tous les consommateurs du domaine. Les exclusions de groupes utilisent les GUID et une lecture ciblée ; une lecture impossible ne doit pas devenir une autorisation.

La politique ne s’active pas par un favori ou un changement de thème. Une modification métier invalide les plans et impose le parcours de rechargement prévu. Les ACL sur le cfg et l’approbation du contenu relèvent du déploiement de l’organisation.

## Coordination optionnelle

Préparer un répertoire existant autorisé avec `tools\Initialize-Coordination.ps1 -Root ... -Domain ... -WhatIf`, puis seulement après examen appliquer la commande. Elle écrit un marqueur et un dossier `locks`. **Elle ne crée pas de partage et ne modifie pas les ACL.**

L’organisation doit vérifier : même domaine déclaré, ACL SMB et NTFS limitant les modifications aux opérateurs autorisés, disponibilité, intégrité et prise en charge correcte de la création exclusive. Aucune garantie interopérateurs n’existe si un opérateur utilise une autre copie sans cette configuration, un ancien outil ou un partage ne fournissant pas ces garanties.

Les clés portent sur l’identité AD et les noms source/cible, sans stockage de mot de passe. L’engagement utilise CreateNew exclusif ; il ne suppose pas qu’un verrou ancien est mort. Pas de durée d’expiration qui relance une écriture potentiellement active. Les reçus parent/enfant gardent leur identité ; résoudre ou nettoyer les fichiers manuellement n’est pas un bouton normal de reprise.

Les retenues personnelles de la page Noms ne sont pas une réservation partagée de plage. Elles ne modifient pas AD. Ne pas présenter la disponibilité affichée comme un droit exclusif.

## Compte ordinateur précréé

`AllowPrecreatedJoin=true` rend disponible le choix explicite sur la page de jonction. Le moteur lie le compte trouvé à son GUID et recontrôle cette identité avant engagement. Il ne modifie pas son propriétaire, n’utilise pas de jonction non sécurisée et ne supprime aucun objet existant pour faciliter l’opération.

Les droits de création/jonction et les règles de réutilisation restent appliqués par Windows et AD. La recette doit couvrir compte absent, prévu, recréé entre contrôle et engagement, propriétaire non autorisé et refus Netjoin. La présence de la case n’est pas une délégation supplémentaire.

## Repli à tâche utilisant un mot de passe

Le réglage reste faux par défaut. L’activer autorise un recours explicitement annoncé dans la confirmation. Un mot de passe est transmis au Planificateur via son API, pas récupéré dans l’UAC ni écrit dans une ligne de commande. Ce n’est pas équivalent à un pur jeton Windows ; la définition, l’état et le nettoyage de la tâche doivent être vérifiés.

Ne pas remplacer arbitrairement ce mode par S4U ni ajouter un coffre maison. Réduire cette autorisation aux postes et comptes qui en ont réellement besoin. La connexion intégrée en domaine reste le parcours normal ; aucun nouveau formulaire n’est automatiquement ajouté au lancement.

## Signature

`tools\Sign-PestoRelease.ps1` exige le thumbprint d’un certificat existant de signature de code avec clé privée, dates valides, et un serveur HTTPS d’horodatage autorisé. Il signe les scripts, reconstruit les empreintes intégrées puis l’EXE, signe l’EXE et met à jour le manifeste.

Il ne crée aucun certificat, n’installe aucune confiance et n’utilise aucun certificat inventé. L’EXE distribué ici est **non signé**, car aucun certificat de votre organisation n’a été fourni. Une erreur pendant cette procédure peut laisser le dossier DEV incomplet : travailler sur une copie et ne fabriquer les packs qu’après tous les contrôles. Ne pas utiliser une exclusion antivirus pour obtenir artificiellement un succès.

## Ce qui n’est pas activable

`AllowOfflineJoin=true` est refusé. Le transport djoin n’est pas implémenté : il exige un circuit autorisé de préparation, transfert, protection du blob et recette post-redémarrage. Aucun blob de jonction n’est stocké dans un favori, un rapport ou le cfg.

Les contrôles complets anti-course de liens physiques et d’ACL ne sont pas tous implémentés. La consultation, la signature et le manifeste ne doivent pas être présentés comme la preuve d’une absence de faille. Utiliser un dossier de code maîtrisé et les protections Windows de l’organisation.

## Références techniques

Ces références décrivent les mécanismes, pas une recette de Pesto :
- Microsoft, Add-Computer (Windows PowerShell 5.1) : https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-computer?view=powershell-5.1
- Microsoft, Netjoin hardening KB5020276 : https://support.microsoft.com/en-us/topic/kb5020276-netjoin-domain-join-hardening-changes-2b65a0f3-1f4c-42ef-ac0f-1caaf421baf8
- Microsoft, TASK_LOGON_TYPE : https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_logon_type
- Microsoft, about_Signing : https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-5.1
