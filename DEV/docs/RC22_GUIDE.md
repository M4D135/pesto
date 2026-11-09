# Pesto 17.0-RC22

## Statut

Version candidate complète, moteur PowerShell/WPF et lanceur Windows x64 recompilé.
Les 90 points ne sont pas tous clos. Le tableau RC22_90_POINTS.md décrit les limites restantes.
Les tests exécutés ici sont des tests de fichiers et de code C sous Linux ; la recette Windows reste obligatoire.

## Contenu des packs

```text
PROD/
  Pesto.exe
  wad/
    Pesto-*.ps1 / *.xaml / *.cs
    cfg.json
    package.json
    ... ressources Active Directory et icône
    support/
      DEBLOQUER_TOUT.cmd

DEV/
  Pesto.exe
  TESTER.cmd
  TEST_RC22.cmd
  FABRIQUER_PACKS.cmd
  ... autres outils de développement
  tools/
  tests/
  docs/
  wad/
    ... même application, avec support et maintenance
```

Le support, les tests, les démos et la documentation ne sont pas des dépendances obligatoires de PROD.
L'EXE n'est pas autonome : conserver wad à côté. Le fichier de configuration fourni reste volontairement non configuré.

## Changements de cette version

### Résultats et identité

Un code entier inconnu reste incertain. Un précontrôle échoué après un effet déjà engagé ne devient pas « non lancé ».
Un déplacement confirmé suivi d'un échec conserve l'effet partiel dans le reçu et ne libère pas la coordination comme un simple refus.
Restaurer un brouillon exige maintenant que le GUID fraîchement lu corresponde au GUID du brouillon lorsqu'il y est renseigné : un autre objet de même nom n'est pas substitué.
La fonction historique de décomposition des noms utilise l'analyseur canonique ; les générateurs non migrés restent suivis comme partiels.

### Avant / Prévu / Observé

Avant un nouveau renommage, une photographie bornée Windows/AD est inscrite dans le reçu.
Un déplacement seul conserve sa photographie AD. Le déplacement suivant un renommage ne remplace jamais cette photographie initiale.
Le plan confirmé reste séparé de ces observations. Les reçus de jonction et anciens reçus sans photographie n'obtiennent pas de valeurs inventées.

Dans Interventions, le détail et la fiche de vérification affichent nom actif/configuré, domaine, identité Windows, nom/GUID/OU AD, protection et informations de santé effectivement disponibles.
Chaque ligne garde la date de sa source. Une lecture absente reste inconnue ; une protection false n'est pas assimilée à une absence de donnée.
La comparaison explique la situation mais n'autorise pas une mutation ni ne certifie l'inscription Entra ou le SSO.

« Conserver cette lecture » mémorise une observation récente dans le reçu, après contrôle du plan et des identités.
Ce bouton ne change ni la phase de résultat, ni les effets, ni les verrous. La commande distincte de vérification/résolution conserve ses contrôles habituels.
Les exceptions brutes, identifiants de connexion et mots de passe sont exclus de la photographie.

**Schéma de reçu 2 :** les nouveaux reçus et ceux enrichis portent ce schéma. La RC22 lit les schémas 1 et 2.
Une RC21 ne sait pas lire un reçu RC22 de schéma 2. Ne pas revenir à une ancienne application en supprimant ou modifiant ces reçus.
Le retour de code après mise à jour interrompue décrit plus bas n'est pas une migration inverse des données ni une annulation Windows/AD.

### Capacité du périmètre et conformité des emplacements

Actions / Ctrl+K → « Capacité de nommage » analyse toutes les combinaisons site/service/type déclarées dans NameCatalogue ou effectivement observées/préparées dans l'instantané chargé.
Les combinaisons déclarées encore vides sont incluses, sans inventer un produit cartésien entre tous les sites et tous les services.
Les doublons ne gonflent pas l'occupation ; une réservation personnelle ou de file déjà occupée dans AD n'est pas comptée deux fois.
Il ne s'agit pas d'une réservation AD ni d'un inventaire de tout le domaine hors du périmètre chargé.

« Contrôler noms et emplacements » confronte les segments du nom aux OU réelles lues avec les sites.
Le DN réel et son GUID sont conservés ; un libellé lisible n'est jamais utilisé pour reconstruire un DN de mutation.
Les sous-OU du site sont acceptées. La zone de préproduction est distinguée. Une destination ambiguë, des métadonnées absentes ou un DN non interprétable produisent un état explicite, pas une correction automatique.
Le code de site est associé par les TAGS explicites ou un motif non ambigu. Un ancien repli implicite par suffixe n'est pas deviné par cette analyse : renseigner le TAGS si nécessaire.

Les deux analyses s'exécutent dans un worker sur le cache déjà chargé. Elles ne contactent pas AD, ne pingent pas le parc et ne modifient aucun poste.
Fermer le panneau demande leur annulation. Une réponse de l'ancien inventaire ou d'une ancienne configuration est rejetée.
Les compteurs portent sur tout le périmètre analysé ; les détails affichés sont limités à 1 000 lignes et 230 000 caractères, avec mention explicite.
La durée du calcul local est ajoutée aux mesures de la session, sans prétendre mesurer le transport AD.

### Palette et tableaux

Ctrl+K et Actions proposent une recherche locale multi-mots, insensible à la casse et aux accents, sur les intitulés et descriptions.
Flèches pour choisir, Entrée pour ouvrir le choix, Échap pour fermer. Taper ne déclenche aucune requête ni opération.
Aucun résultat désactive « Ouvrir » ; le contexte et le focus sont rétablis à la fermeture.

Actions → « Mémoriser les colonnes » conserve largeur et ordre des grilles File, Noms et Interventions.
Le centre Interventions possède aussi son bouton dédié. Les colonnes d'identité restent au début.
La signature des colonnes, les valeurs numériques et leurs bornes sont contrôlées avant restauration ; un schéma incompatible est ignoré.
Les sélections, cases cochées, filtres, colonnes masquées, confirmations et droits ne sont pas mémorisés.
« Réinitialiser les colonnes » rétablit seulement la présentation. Les autres grilles ponctuelles restent inchangées.

### Chaînes PowerShell

Des apostrophes typographiques non échappées dans des chaînes délimitées par des apostrophes ont été corrigées dans le moteur, les tests et l'outil de signature.
PowerShell interprète aussi les guillemets typographiques comme des délimiteurs : ils sont doublés lorsqu'ils appartiennent au texte d'une chaîne.
L'affichage français reste identique. Un contrôle lexical spécifique couvre désormais ces cas et les interpolations imbriquées ; il ne remplace pas le parseur Windows PowerShell 5.1.

## Installation normale

Terminer et vérifier les anciennes interventions. Fermer Pesto et sauvegarder le dossier avec ses états.
Conserver le même emplacement de cfg.json et **sa configuration opérationnelle**, ainsi que les préférences, reçus et journaux.
Ne pas écraser cfg.json par le modèle non configuré du pack.

Le chemin recommandé pour un administrateur est l'outil DEV ci-dessous. Pour une copie manuelle, remplacer ensemble Pesto.exe, les composants applicatifs wad et package.json ; ne pas mélanger EXE et scripts de versions différentes.
Mettre à jour wad/support séparément lorsqu'une copie manuelle est utilisée. Ne pas créer un sous-dossier PROD dans l'installation existante.

Après vérification de provenance : wad\support\DEBLOQUER_TOUT.cmd, puis Pesto.exe --check.
Exécuter TESTER.cmd dans DEV sur une VM de recette avant les opérations réelles.
L'EXE est non signé ; ne pas désactiver les protections de l'entreprise.

## Mise à jour avec sauvegarde et reprise

Exécuter l'outil depuis le **nouveau DEV extrait dans un autre dossier**, avec Python provisionné par l'organisation (DEV uniquement).

```powershell
python .\tools\update_installation.py --destination 'C:\Outils\Pesto'
python .\tools\update_installation.py --destination 'C:\Outils\Pesto' --apply
```

La première commande affiche le plan sans modifier les fichiers. La seconde prépare deux copies vérifiées du code (ancienne et nouvelle), écrit un journal, puis remplace les composants, l'EXE en dernier.
Seuls les composants applicatifs et le manifeste sont remplacés. La configuration et les reçus ne sont pas copiés.
Sur une exception interceptée, retour au code précédent ; sur arrêt brutal, le verrou et la sauvegarde restent en place.
Le lanceur RC22 refuse de charger PowerShell si `.pesto-update.lock` est présent ou ne peut pas être contrôlé. Le contrôle PowerShell refuse également ce verrou.

Après une interruption, depuis ce même nouveau DEV :

```powershell
python .\tools\update_installation.py --destination 'C:\Outils\Pesto' --recover
python .\tools\update_installation.py --destination 'C:\Outils\Pesto' --recover --apply
```

La première commande prévisualise la restauration du code précédent. La seconde restaure uniquement les fichiers dont les empreintes correspondent aux anciennes ou nouvelles copies consignées.
Une modification extérieure, une sauvegarde altérée, une destination liée ou un journal incomplet bloque la reprise ; aucun déverrouillage par âge du fichier.
Une configuration modifiée depuis l'interruption reste conservée. Une restauration incomplète conserve le verrou.
Si l'arrêt a eu lieu dans la préparation avant écriture du journal complet, aucune bascule de code n'a commencé et la reprise automatique est refusée : examiner les copies et le verrou avec le support.
Les sauvegardes ne sont pas supprimées automatiquement.

**Limite :** ce mécanisme est une mise à jour récupérable fichier par fichier. Il n'est ni une transaction atomique globale, ni une preuve contre toute panne électrique/stockage, ni un retour arrière de Windows/AD.
La validation réalisée a interrompu des processus dans des copies Linux ; les mêmes scénarios doivent être exécutés sur le système de fichiers Windows cible.

## Règles inchangées

Jonction locale et renommage unitaire sans file, lots séparés ; même site sans déplacement ; déplacement après renommage confirmé si le site change.
Connexion Windows intégrée après UAC en domaine, login compact non maximisable lorsque nécessaire, thème indépendant du cfg.
Traitement Entra conditionnel, aucun /leave pour une jonction ou un déplacement seul, aucun redémarrage forcé/implicite, aucun WinRM activé.
Identifiants GP de stockage et mutex conservés pour continuité. Ni certificat auto-approuvé ni suppression de verrou pour forcer une opération.

## Références de mise en œuvre

Ces documents décrivent les mécanismes, pas une recette Pesto :
- Microsoft, règles des guillemets PowerShell : https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules?view=powershell-5.1
- Microsoft, DataGridColumn.DisplayIndex : https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.datagridcolumn.displayindex
- Python, os.replace et os.fsync : https://docs.python.org/3/library/os.html
