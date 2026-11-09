# Pesto 17.0-RC23

## Contenu de cette continuation

Cette version candidate repart du DEV RC22 reçu. Elle ajoute la reprise vérifiée des jonctions locales, l’import conservateur de leurs anciens reçus, un bouton principal adaptatif pour une seule machine, la fiche d’observation intégrée et des mesures de workers en mémoire. Elle ne prétend pas terminer les 90 améliorations.

## Installation

```text
PROD/
  Pesto.exe
  wad/
    Pesto-*.ps1 / *.xaml / *.cs
    cfg.json
    package.json
    ... ressources AD et icône
    support/
      DEBLOQUER_TOUT.cmd
```

DEV contient la même application plus sources, tests, démos, compilation et documentation. Aucun de ces outils ni le déblocage ne sont une dépendance de lancement de PROD.

1. Examiner l’issue des opérations actives ou incertaines. Fermer Pesto normalement et sauvegarder le dossier et les reçus.
2. Conserver le même dossier d’installation. Remplacer ensemble Pesto.exe, les composants applicatifs et wad/package.json. Ne pas remplacer votre wad/cfg.json opérationnel, vos préférences, journaux et reçus. Les fichiers neufs contiennent un modèle non configuré, pas votre domaine.
3. Débloquer le pack si nécessaire depuis wad/support/DEBLOQUER_TOUT.cmd après contrôle de provenance. Ce script vise tout le dossier Pesto, pas seulement support.
4. Lancer Pesto.exe --check, puis réaliser la recette dans une copie DEV sur VM. Le contrôle d’intégrité ne vérifie ni les droits AD ni le comportement UAC.

La version doit indiquer 17.0-RC23. Le moteur et les empreintes incorporées ont changé : remplacer uniquement un PS1 est insuffisant. L’EXE demeure un lanceur PowerShell/WPF, pas un EXE autonome à déplacer sans wad.

## Jonction : ce qui est maintenant conservé

Avant Add-Computer, la RC23 enregistre l’identité Windows réellement lue, son nom actif/configuré, son domaine ou groupe de travail et le démarrage initial. Le plan approuvé reste distinct. La demande native est consignée immédiatement avant la commande, puis son retour accepté/refusé lorsqu’il est confirmé. Une panne de persistance empêche de poursuivre normalement.

L’état AD initial non collecté n’est pas inventé. Le GUID d’un compte précréé peut être lié dès la préparation ; pour un nouveau compte, le GUID observé est lié seulement pendant la résolution explicite. Le plan historique n’est pas réécrit pour s’aligner sur l’état courant.

Un résultat tardif ou un retour incomplet reste incertain. Une jonction précédemment demandée n’est jamais réexécutée depuis la fiche de vérification.

## Vérifier après redémarrage

Sur la page Ajouter au domaine, « Vérifier dans AD » ouvre la fiche intégrée du reçu. Le même parcours se trouve dans Historique > Interventions > Vérifier l’état du poste.

La lecture exige le PC d’origine et compare séparément : identité Windows ; nom actif et configuré ; domaine ; démarrage postérieur à la préparation ; GUID/nom/emplacement AD ; identité de l’OU lorsqu’elle avait été conservée ; canal sécurisé local. Les différentes sources doivent être fraîches.

« Conserver cette lecture » enregistre l’observation sans déclarer de réussite. « Consigner la vérification » demande une confirmation et recontrôle les conditions avant de mettre à jour le reçu central puis le reçu local concordant. L’absence de preuve ne débloque pas l’opération. Un ancien reçu local d’une autre opération n’est jamais remplacé.

La simple lecture « Vérifier l’état » de la page de jonction ne certifie plus AD et ne lève pas le verrou. Elle oriente vers l’observation complète. Un affichage de réussite historique est explicitement identifié comme historique.

Entra reste séparé : un nom, une OU et un canal sécurisé conformes ne sont pas présentés comme une certification de réinscription cloud ni de SSO de l’utilisateur.

## Anciens reçus de jonction

Dans Interventions > Importer un ancien état, sélectionner explicitement le fichier local hérité :

```text
%ProgramData%\GP\Join\receipt.json
```

La prévisualisation vérifie schéma, types, dates, identité du PC et domaine. Seules les phases non résolues sont reprises. Le compte historique n’est pas exporté dans le nouveau reçu central. Le fichier choisi n’est ni effacé ni déplacé.

Lorsqu’un reçu central concordant existe déjà sans les preuves de jonction, elles peuvent y être ajoutées sans changer son plan ni le déclarer résolu. Les preuves manquantes restent manquantes. Aucun balayage automatique de tous les profils Windows n’est effectué.

**Compatibilité :** la RC23 utilise le schéma central 3 pour ces preuves. Elle lit les schémas 1 et 2 existants ; RC22 et versions antérieures ne comprennent pas le schéma 3. Ne pas rétrograder en supprimant ces fichiers. Le stockage historique GP est conservé volontairement.

## Une machine : une action principale qui suit l’étape

Le bouton principal affiche successivement « Lire ce poste », « Compléter le formulaire », puis « Vérifier puis renommer » ou « Vérifier puis déplacer ». Compléter place le focus sur le prochain choix requis sans écrire dans Windows/AD. Le clic recalcule l’état ; un ancien libellé ne peut pas autoriser une action.

Le dernier bouton utilise le précontrôle existant, présente l’impact et attend la confirmation. La reprise de déplacement annonce explicitement « déplacer seulement ». « Vérifier seulement » reste une commande secondaire. Entrée dans le champ du nom reste une lecture, pas une exécution.

Busy, verrous, configuration à appliquer et mode consultation restent contrôlés. Aucune case de redémarrage ou autorisation n’est mémorisée par ce nouveau parcours.

## Fiche intégrée et mesures

La fiche État du poste est hébergée dans la fenêtre principale. Elle démarre sa lecture une seule fois, permet de relire, puis libère le travail de lecture à la fermeture. Échap ferme le panneau, les erreurs/confirmations restent dans le thème, le contexte précédent reste conservé.

Actions / Ctrl+K > Performance observée rassemble les 200 derniers échantillons de calcul et de workers. Durée supervisée, temps d’attente d’un créneau et temps de travail sont distingués. L’agrégat indique nombre d’échantillons, moyenne, P95, maximum et issues du worker.

« Returned » signifie que le worker a renvoyé une réponse, pas que l’opération Windows a réussi. Les mesures ne sont pas une télémétrie cloud ni une preuve d’accélération. Les erreurs de mesure sont comptées et ne modifient pas les callbacks métier.

## Comportements conservés

Jonction sans file, renommage unitaire direct, lots séparés, connexion Windows intégrée après UAC en domaine, login compact non maximisable, thèmes indépendants de cfg, noms disponibles paginés avec état de chargement. Même site : renommage seul ; site différent : déplacement après renommage confirmé. Aucun reboot ni /leave ajouté par la vérification de jonction.

## Mise à jour avec l’outil DEV

Depuis le nouveau DEV distinct de l’installation :

```powershell
python .\tools\update_installation.py --destination 'C:\Outils\Pesto'
python .\tools\update_installation.py --destination 'C:\Outils\Pesto' --apply
```

Le premier appel prévisualise. La mise à jour conserve les configurations et états et peut récupérer les interruptions de copie prévues ; elle n’annule pas une action AD. Recopier wad/support séparément si nécessaire : le helper est hors du manifeste applicatif. En présence d’un verrou ou d’une interruption, suivre le guide RC22 de --recover, sans effacement manuel du verrou.

## Validation

Voir RC23_VALIDATION.md et RC23_RECETTE_WINDOWS.md. Tests Python/C et compilation exécutés ici ; Windows PowerShell 5.1, WPF, UAC, CLR C#, ACL/registre/partage et opérations réelles AD/Entra non exécutés. Binaire non signé. PROD désigne le contenu à distribuer après recette, pas une certification de production.
