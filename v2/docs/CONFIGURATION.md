# Configuration du profil et distribution personnalisée

La configuration active V2 est un `cfg.json` compatible avec le moteur Pesto, stocké dans le profil local de l’opérateur. Le pack peut fournir une configuration de départ, mais n’est jamais le dossier de travail de l’opérateur. Le profil d’origine est résolu par son SID et le registre système HKLM avant l’élévation UAC, puis de la même manière après le relais vers le compte administrateur. Un LocalAppData redirigé vers un autre chemin est refusé avant toute initialisation : ce cas n’est pas pris en charge, et Pesto ne bascule pas silencieusement vers un autre cfg.json.

## Ouvrir les paramètres sans connexion AD

`Pesto.exe --settings` ouvre directement **Paramètres** et **Aide**, dans le même exécutable, sans demander de compte AD ni construire d’adaptateur d’annuaire ou de mutation. Cette entrée permet de configurer le profil, importer ou exporter une configuration valide et préparer un pack personnalisé sans connexion à un domaine. Elle suit les règles d’initialisation du profil décrites plus bas ; elle ne constitue pas une autorisation de remplacer un fichier existant invalide.

La même fenêtre locale s’ouvre lorsque la configuration est absente ou invalide, ou lorsque l’opérateur annule le choix de compte ou la saisie des identifiants AD. Sa bannière indique **Configuration locale — annuaire non connecté** ; les capacités métier sont indisponibles. Enregistrer une configuration ne connecte pas cette fenêtre à AD : une reconnexion explicite reste nécessaire. La démonstration peut être ouverte depuis **Paramètres → Interface et démonstration**, dans sa fenêtre isolée en conservant ce contexte. Le choix **Animations** (complètes, réduites, suivre Windows) est aussi réservé aux Paramètres et s’applique immédiatement, séparément pour la simulation et la session réelle.

Les API métier sont refusées même si l’interface est contournée. L’ouverture du parcours ODJ depuis cette fenêtre et les actions **Inspecter / Préparer / Appliquer** de coordination sont également refusées. L’état de coordination affiche seulement les paramètres locaux, sans sonder le partage. L’entrée séparée `--offline-join` conserve son propre contrat. Les actions de maintenance explicitement demandées, notamment l’inspection d’une mise à jour, gardent leurs contrôles et peuvent accéder à leur source choisie ; le libellé « configuration locale » ne transforme pas ces actions en simulation.

### Identité Windows et choix de compte

Pour un lancement réel avec une configuration valide, le choix initial repose sur l’appartenance locale du poste au domaine :

| Lancement | Authentification initiale |
|---|---|
| Poste membre du domaine, sans option de compte | Identité Windows effective du processus après UAC ; aucun second dialogue de choix de compte systématique |
| Poste membre du domaine, `Pesto.exe --choose-account` | Fenêtre de connexion Pesto : **Continuer avec le compte Windows**, ou compte AD et mot de passe dans les champs natifs |
| Poste en groupe de travail | Fenêtre de connexion Pesto, saisie native d’un compte AD ; aucun succès de connexion supposé à partir de la configuration |
| `Pesto.exe --settings` | Aucune authentification AD ; paramètres locaux uniquement |

**Reconnecter** et **Changer de compte AD…** ferment la session puis relancent Pesto avec `--choose-account`, en conservant le SID du profil d’origine. Changer l’identité utilisée pour AD ne change donc pas le propriétaire de la configuration. Les identifiants saisis restent dans le fournisseur natif de la session, sans être transmis au WebView ni exportés.

Le repli local décrit ici concerne l’annulation du dialogue de compte AD. L’annulation de l’élévation UAC termine le lancement concerné ; `--settings` permet ensuite d’ouvrir les paramètres. Une transaction binaire déjà interrompue est traitée avant l’initialisation de configuration, y compris lors d’une demande d’ouverture des paramètres.

## Paramètres sans installation V1

La page Paramètres permet de préparer puis confirmer les paramètres du domaine unique, la racine des OU gérées, le préfixe, le motif de nommage, le tirage des noms et les sites. Les sites configurés comportent un identifiant, un libellé, un code de largeur compatible avec la convention et une OU complète du domaine. Le moteur ne rend un site disponible qu’après relecture de son OU dans l’annuaire. En préproduction, l’OU de préproduction et le code de service de préproduction sont également requis.

Une configuration V1 peut être choisie explicitement à l’import. Le fichier V1 choisi demeure intact. Les anciennes correspondances `TAGS`/`OUSite` restent utilisables ; un import ne les remplace pas par des OU inventées. Les paramètres V1 inconnus ou propres à une session ne deviennent pas des paramètres diffusables.

Les motifs `TAGS` acceptent `*`, `?`, les ensembles et plages `[ABC]` / `[A-C]`, et l’échappement PowerShell par accent grave. Un motif mal formé est refusé. Sans correspondance, une OU enfant observée reprend le suffixe alphabétique du nom, de la largeur du code de site ; le repli ne s’applique jamais à PREPROD ni à ses alias. Les motifs explicites restent prioritaires.

Si `V2DirectorySites` et la découverte V1 coexistent, Paramètres affiche les lignes explicites. Les enregistrer sans les modifier conserve intégralement `TAGS`, `OUSite` et `V2DirectorySites`. Une modification partielle de ces lignes est refusée lorsque le modèle comporte des règles non affichées : son remplacement passe par l’import de configuration complète. Le périmètre `CONF[0].OUScanNoms`, absent du formulaire, est également conservé. Un référentiel de services peut utiliser les codes des sites explicites aussi bien que ceux de `TAGS`.

La création d’une configuration neuve positionne explicitement `EntraPolicy=Disabled`, `DsregLeaveOnMove=false`, `ClearProtectionOnMove=false` et `AllowHybridRepair=false`. Les politiques déjà configurées dans un import valide sont préservées. Aucun enregistrement ne lance de mutation AD, de retrait Entra ou de redémarrage.

### Politiques métier et coordination

Le même aperçu confirmé permet de régler les politiques suivantes. Les cases sont des booléens JSON stricts ; l’absence d’un champ conserve la valeur déjà configurée.

| Paramètre de l’interface | Clé persistée | Effet à l’exécution |
|---|---|---|
| Racine de coordination | `POLICY.CoordinationRoot` | Dossier/partage de coordination du domaine unique ; aucune inspection distante lors du simple chargement de la page |
| Coordination obligatoire | `POLICY.CoordinationRequired` | Refus avant mutation lorsque les verrous ou le marqueur ne peuvent pas être prouvés |
| Réserver le compte AD avant jonction | `POLICY.ReserveNamesInAD` | Création après confirmation de jonction, avec GUID, marqueur et reçu durable ; reprise ou retrait via des plans séparés |
| Audit Windows | `POLICY.AuditEventLogEnabled` | Projection minimale du reçu durable dans Application/Pesto ; source déjà installée requise, tentative bornée sans rejeu métier |
| Bloquer la jonction en cas de dérive horaire | `POLICY.BlockJoinOnClockSkew` | Mesure vers le DC exact ; dérive absolue connue ≥ 300 secondes bloquante ; inconnu signalé sans correction d’horloge |
| Groupes AD exclus | `POLICY.ExcludedGroupGuids` | Jusqu’à 200 GUID distincts, non nuls ; appartenance directe ou imbriquée exclue, lecture indéterminée bloquante |
| Autoriser la jonction avec un compte précréé | `POLICY.AllowPrecreatedJoin` | Sélection explicite et aperçu du compte par GUID/OU ; aucune création de compte, aucun contournement des règles Windows de réutilisation |
| Autoriser la jonction hors ligne locale | `POLICY.AllowOfflineJoin` | Ouvre le parcours local ODJ : import protégé, préparation, confirmation du nom actuel, application unique puis observation après redémarrage |
| Autoriser la jonction par CLI | `POLICY.UnattendedJoinEnabled` | Autorise la préparation et l’exécution par le parcours CLI ; un plan exporté, `--execute`, une clé d’idempotence et les gardes natives restent nécessaires |
| Autoriser renommage et déplacement par CLI | `POLICY.UnattendedOperationsEnabled` | Autorise ces actions par le parcours CLI, sous les restrictions HKLM, l’identité explicite, les preuves du plan et l’éventuel accord de campagne |
| Politique Entra avant renommage | `CONF[0].EntraPolicy` | `Disabled` refuse un renommage hybride ; `HybridOnly` permet sa préparation avec diagnostic et consentement distinct au retrait |

Un profil neuf désactive explicitement la jonction précréée et la politique Entra. Un import V1 dont `EntraPolicy` est absent ou vide conserve sa valeur effective V1 `HybridOnly` ; l’interface affiche cette valeur. Les anciens indicateurs `DsregLeaveOnMove` et `AllowHybridRepair` ne constituent pas une autorisation de retrait Entra. Le diagnostic doit prouver l’état AD/hybride, et la confirmation de renommage exige une case dédiée avant tout retrait. Si le retrait a eu lieu puis que le renommage échoue, le reçu conserve cet effet réel et ne prétend pas que rien n’a changé.

Les trois nouvelles cases `AllowOfflineJoin`, `UnattendedJoinEnabled` et `UnattendedOperationsEnabled` sont désactivées dans un profil neuf. Elles sont persistées sous leurs noms V1 exacts, conservées dans les aperçus, les différences, les imports, les exports et les packs personnalisés. Une valeur présente doit être un booléen JSON : les chaînes `"true"`, nombres, valeurs nulles et collections sont refusés. L’absence d’une option lors d’une édition conserve la politique existante ; elle ne la désactive pas silencieusement.

L’activation de `UnattendedJoinEnabled` ne désactive pas la jonction interactive, qui conserve aperçu du nom et confirmation. La CLI exige un processus déjà élevé et ne déclenche aucune invite UAC. Les restrictions machine `DisableUnattendedJoin`, `DisableUnattendedOperations` et `IncidentMode` restent prioritaires. La jonction CLI conserve les refus V1 pour la coordination partagée et `ReserveNamesInAD` ; ces parcours restent disponibles dans leur interface interactive explicite. Aucun de ces paramètres ne déclenche une opération au démarrage.

La jonction hors connexion possède une entrée dédiée dans le **même `Pesto.exe`**, `--offline-join`, et une fenêtre locale accessible depuis **Ajouter ce PC**. Le chargement de cette fenêtre, l’import du blob, sa préparation et son application n’utilisent pas la découverte de DC ni le backend AD ordinaire. Seul le bouton **Observer après redémarrage — accès AD** engage la lecture AD, après preuve locale d’un nouveau boot. `CoordinationRoot`, `CoordinationRequired` et les exclusions de groupes rendent l’admission ODJ indisponible : ils ne sont pas ignorés au prétexte de travailler hors connexion. Conformément au parcours V1, `BlockJoinOnClockSkew` n’impose pas de mesure vers un DC avant ODJ. Le [guide ODJ](OFFLINE-JOIN.md) détaille ces conditions.

**Inspecter la coordination** est une action explicite. **Préparer le dossier** produit un plan lié à la configuration et à la racine observées ; sa confirmation crée seulement le marqueur et les sous-dossiers attendus, jamais un partage ou des ACL. Le marqueur de domaine et les fichiers suivent le protocole V1. Un dossier existant incompatible est refusé. L’identité AD de session peut servir à l’accès SMB par impersonation temporaire ; aucune connexion réseau persistante ni aucun secret n’est écrit.

Les verrous de mutation sont exclusifs et sans expiration automatique. Une intention locale durable est enregistrée avant le premier accès d’écriture partagé. Un effet incertain conserve le verrou ; seuls les octets exacts possédés et un résultat durable autorisant la libération peuvent être supprimés. Un autre opérateur ou une autre version ne se voit jamais retirer son verrou par simple ancienneté.

Lorsque la coordination est active, un aperçu de nom peut acquérir un bail temporaire sous `reservations/<NOM>.json`. Sa durée est `POLICY.NameReservationMinutes` (5 à 240 minutes, 15 par défaut). Le plan expire au plus tard avec ce bail. Les écritures et renouvellements sont exclusifs, liés au profil d’opération, au nom et à l’empreinte de configuration ; une collision, un fichier inconnu ou une réponse perdue interdit de considérer le nom acquis. Aucun objet AD n’est créé par cet aperçu. La création AD éventuelle reste explicitement annoncée dans le plan de jonction confirmé.

Le panneau **Réservations AD** charge d’abord les journaux locaux. Inspecter, préparer une reprise et préparer un retrait sont des actions distinctes. La reprise vérifie de nouveau le poste Windows, le GUID AD, l’OU et le marqueur Pesto ; le retrait exige un compte encore réservé, sans DNS/SPN ni jonction susceptible d’être en cours. Aucun nettoyage ou redémarrage n’est automatique.

L’audit EventLog ne contient que schéma, produit, identifiant d’opération, type, état, code de résultat, séquence et date. Il ne copie ni nom de poste, domaine, compte, chemin ni secret. L’échec d’une écriture d’audit ne modifie pas le résultat métier déjà durable.

## Exporter, importer, définir comme configuration par défaut

Une relecture ou la fin d’une opération conserve les modifications non enregistrées
du formulaire. **Relire** demande confirmation avant d’abandonner ce brouillon.
Pendant une préparation lente, Enregistrer reste indisponible ; une nouvelle saisie
invalide l’ancien aperçu. Quitter la page empêche une réponse tardive d’ouvrir une
confirmation ou de poursuivre une action. Les opérations déjà confirmées et envoyées
restent traitées par le moteur, sans annulation ni rejeu automatique.

- **Exporter** produit un document `pesto.configuration` validé, avec version et empreinte SHA-256 calculée sur sa configuration canonique. Une liste fermée de paramètres métier est copiée. Les mots de passe, identifiants de session, historique, reçus, caches, réglages de simulation et blobs ODJ ne sont pas exportés. Les politiques reconnues, dont les exclusions et le scénario structuré, sont conservées et validées ; une clé `POLICY` inconnue ou mal orthographiée refuse l’export/import au lieu de supprimer silencieusement une restriction.
- **Importer** affiche les différences et prépare un identifiant temporaire à usage unique. La confirmation applique uniquement le document préparé, si la configuration locale est toujours celle de l’aperçu.
- **Définir comme configuration par défaut** prépare un **nouveau pack personnalisé complet** depuis le pack courant vérifié. Le pack source demeure intact. La destination doit être nouvelle et extérieure au pack source. Avant d’ajouter les paramètres et de recalculer les sommes du pack personnalisé, la copie temporaire doit encore correspondre à l’empreinte exacte du pack source validé. Une modification concurrente refuse la préparation ; elle ne peut pas être légitimée par le recalcul des sommes. Le pack personnalisé final est de nouveau validé avant sa publication par renommage du dossier.

Le pack personnalisé contient `wad/defaults/configuration.json`. Son manifeste porte `distribution=custom`, `official=false`, `configurationVersion` et `configurationFingerprint`. Ses empreintes sont recalculées et vérifiées. Il ne devient jamais une release officielle du dépôt GitHub.

Le document distribué a la forme suivante ; l’interface le produit sans édition manuelle :

```json
{
  "schema": 1,
  "kind": "pesto.configuration",
  "version": "entreprise.2026.10.25",
  "fingerprint": "empreinte-sha256-du-contenu-canonique",
  "configuration": {}
}
```

L’objet `configuration` doit être un document Pesto valide ; l’exemple vide ci-dessus décrit seulement l’enveloppe. Le validateur vérifie son contenu complet et l’empreinte, et refuse les champs non diffusables ajoutés à une enveloppe.

## Premier lancement et choix conservés

Sur un profil neuf, les paramètres distribués valides sont importés automatiquement dans le dossier du profil. Sur un profil existant dont la configuration est valide, une configuration distribuée différente produit un choix **Remplacer / Conserver**, accompagné des différences. Remplacer exige une confirmation et conserve une sauvegarde datée de l’ancien fichier. Conserver ne modifie pas le fichier actif. Une configuration existante invalide interrompt ce mécanisme avant même la lecture des valeurs distribuées ou d’une source V1 : elle exige le parcours de récupération explicite ci-dessous.

Le choix est mémorisé dans le profil pour le triplet **identité du profil, version, empreinte**. Une nouvelle empreinte portant la même version demande un nouveau choix. Deux profils utilisant le même pack possèdent des configurations et des décisions indépendantes. Le pack partagé n’est pas modifié au démarrage.

L’entrée explicite `Pesto.exe --offline-join` est plus limitée : elle peut initialiser uniquement un profil dont le `cfg.json` est absent, depuis les valeurs distribuées locales valides du pack. Elle ne propose ni n’applique de remplacement à un profil existant. Ouvrir la fenêtre ODJ depuis Pesto normal réutilise la configuration déjà sélectionnée, avec un profil WebView distinct. Le choix **Remplacer / Conserver** d’une nouvelle configuration distribuée reste dans le lancement normal. Les mêmes contrôles du SID d’origine, du chemin HKLM et des redirections s’appliquent avant et après UAC ; aucun chemin de profil libre n’est accepté au relais élevé.

Un document préparé expire après quinze minutes et ne s’applique qu’une fois. Une modification concurrente du fichier invalide l’aperçu. Les remplacements utilisent un fichier temporaire sur le même volume, un flush durable, un remplacement atomique et une sauvegarde unique. Les écritures de l’ancien point d’entrée `settings.save`, lorsqu’il est disponible dans une session AD, utilisent le même verrou de configuration. Cet ancien point d’entrée est refusé en configuration locale ; les éditions passent par l’aperçu confirmé de configuration. Aucun verrou métier GP n’est retiré.

## Récupérer explicitement une configuration invalide

Le statut distingue `missing`, `valid` et `invalid`. `configured=true` signifie que le document a été validé, pas seulement qu’un fichier existe. Un fichier invalide ou illisible donne `configured=false`, `configurationExists=true`, `configurationState=invalid` et `fingerprint=null`. Le diagnostic n’affiche ni contenu brut, ni valeurs inconnues, ni message détaillé du parseur. Le formulaire ne présente pas des valeurs par défaut comme une configuration active.

Dans cet état, l’édition ordinaire, l’export, la fabrication d’un pack par défaut et l’import de référentiels restent indisponibles. **Importer** reste accessible :

1. Choisir par le dialogue natif une configuration complète valide, V1 compatible ou enveloppe `pesto.configuration`.
2. Vérifier l’aperçu **Remplacer la configuration invalide**. Il annonce explicitement le remplacement du fichier non interprétable, sans en exposer le contenu, et présente la configuration candidate validée.
3. Confirmer **Sauvegarder et remplacer**. Le moteur exige que les octets du fichier existant correspondent toujours à ceux de l’aperçu ; il sauvegarde ces octets exacts puis publie le nouveau document par remplacement atomique. Le résultat indique la sauvegarde. Après réparation, les actions de configuration redeviennent disponibles ; la session reste locale jusqu’à la reconnexion explicite.

Un JSON mal formé ou un encodage invalide peut ainsi être remplacé sans perdre l’original. Si les octets ne peuvent pas être lus exactement — droits insuffisants, lien ou type de fichier refusé, taille supérieure à 1 Mio — aucun plan de remplacement n’est créé. Il faut d’abord rétablir cet accès ; aucun fichier distribué ne sert de remplacement automatique.

Deux empreintes ont des fonctions distinctes. L’empreinte exposée par les exports et les différences porte sur la configuration métier canonique. La garde de concurrence interne porte sur le **SHA-256 des octets originaux**, y compris le marqueur d’encodage BOM. Retirer seulement ce marqueur après l’aperçu suffit à refuser l’application, même si le texte décodé paraît identique. La lecture accepte UTF-8 avec ou sans BOM et UTF-16/UTF-32 avec leur BOM ; un décodage invalide n’est pas corrigé silencieusement. La sauvegarde conserve le fichier original, tandis que le nouveau document validé est écrit en UTF-8. Un plan déjà appliqué, expiré ou devenu concurrent exige un nouvel aperçu ; aucun remplacement n’est rejoué automatiquement.

## Référentiels sites et services

L’import d’un référentiel est distinct de l’import d’une configuration complète. Il ajoute ou met à jour des correspondances de sites et des couples site/service. Il ne crée pas d’OU ni d’objet AD. Les motifs de sites sont ensuite rapprochés des OU réellement observées. Les libellés des services importés sont utilisés dans la liste des services du moteur réel.

Format d’import :

```json
{
  "schema": 1,
  "kind": "pesto.references",
  "version": "2026.10.25",
  "sites": [
    { "pattern": "Marseille*", "code": "MA" }
  ],
  "services": [
    { "site": "MA", "code": "001", "name": "Accueil" }
  ]
}
```

Les largeurs des codes viennent de la convention active. Les clés des sites sont les motifs, sans distinction de casse ; celles des services sont les couples site/code. Une entrée répétée est refusée. Une réimportation du même référentiel n’ajoute pas de doublon.

L’aperçu sépare les ajouts, les éléments inchangés et les conflits. Pour chaque conflit, un choix explicite **Conserver la valeur locale / Remplacer par la valeur importée** est requis. Une résolution manquante ou supplémentaire refuse toute application. La fusion du catalogue et de ses libellés se fait dans le même fichier de configuration, par un remplacement atomique unique avec sauvegarde. Une modification concurrente annule l’application entière. Aucun URI ou téléchargement n’est accepté dans le document de référentiel.

Les fichiers sélectionnés par les dialogues d’import sont lus en un instantané borné à 1 Mio. Le décodage UTF-8 est strict ; les BOM UTF-8, UTF-16 et UTF-32 sont reconnus. Un octet invalide provoque un refus, sans remplacement silencieux de caractères. Les lectures et écritures de fichiers se déroulent hors du fil de la fenêtre ; l’export utilise un fichier temporaire puis un remplacement atomique.

## Isolation et qualification

Les services de configuration refusent les opérations réelles en démonstration, contrôle de santé et reprise binaire, y compris par appel direct à leurs API. Le refus précède l’inspection de chemins externes. L’installation ou le rollback des binaires ne rétablit pas un ancien `cfg.json` de l’opérateur.

Les suites portables couvrent documents, empreintes, décisions par profil, sauvegardes, conflits, concurrence, modes isolés et conservation des options ODJ/CLI. La campagne [C8](VALIDATION-C8-20261026.md), source `483a8a3`, ajoute le refus des encodages invalides lors de l’import natif. Elle passe 29 tests ProfileConfiguration et trois ConfigurationOnly sur fixtures.

Les packs PROD et DEV passent chacun **14 contrôles natifs** avec le même EXE : export/import par les dialogues Windows et comparaison exacte, absence de temporaire d’export résiduel, refus d’encodage invalide, annulations, construction et validation d’un pack personnalisé complet, conservation de l’EXE et de la source, import sur profil neuf et préservation d’un profil existant. Ces profils sont temporaires ; le contrôle des temporaires d’export porte uniquement sur les fichiers frères de sa destination, pas sur le cache WebView2 actif.

La coexistence locale/démo et les quatre transactions entre compilations distinctes conservent leur portée isolée. La sélection positive du dossier de pack, le parcours complet du bouton, la récupération native d’un cfg invalide, le profil opérateur réel, UAC sous une autre identité, ACL/DPAPI, djoin et AD restent des qualifications séparées. Le pack exact `fd522bd` passe également les 14 contrôles en VM ; le résultat courant est dans le [rapport C9](VALIDATION-C9-20261026.md) ; la [checklist Windows](QUALIFICATION-WINDOWS.md) détaille les preuves encore nécessaires.

La fenêtre de saisie du compte AD utilise des champs Windows natifs, séparés de WebView2. Le mot de passe masqué est protégé en mémoire par DPAPI CurrentUser, sans chaîne de caractères .NET en clair lors de la saisie. Fermer la fenêtre, annuler ou choisir le compte Windows efface le champ. Aucun champ de connexion n’est exposé au navigateur. La saisie prépare le compte de session ; seule la lecture effective de l’annuaire établit la connexion. Cette saisie reste postérieure à l’UAC et n’apparaît pas au démarrage normal d’un poste joint.

Depuis la version 2.0.2, le démarrage normal non élevé demande l’UAC immédiatement, comme en V1 : aucune fenêtre ne la précède. Seule l’intégrité du pack est contrôlée avant la demande ; aucun backend AD, import de configuration ni champ de mot de passe n’existe avant le consentement. Si l’UAC est annulée ou échoue, une boîte Windows native propose **Réessayer** ou **Fermer** ; rien n’est relancé sans ce choix. Le processus élevé est vérifié par son vrai jeton Windows et conserve le SID du profil opérateur initial. Après élévation, un poste joint utilise automatiquement le compte Windows effectif ; hors domaine, la fenêtre native de saisie AD décrite ci-dessus s’ouvre. `--settings`, la simulation et les entrées de maintenance gardent leurs parcours isolés sans ce lancement UAC.
