# Bilan de livraison - GP 17.0-RC2

## Objet

Ajout de `DEBLOQUER_TOUT.cmd` et du dossier `wad`, suivant l'organisation demandée. Révision construite depuis l'archive GP_17_ameliore.zip fournie dans la conversation. Aucun EXE nouvellement compilé n'est inclus.

## Résultats réellement obtenus

- **53 contrôles statiques, 53 réussis, 0 échec.** Rapport : `tests/static-report.json`.
- **10 injections de défauts, 10 détectées.** Elles vérifient le validateur lui-même, pas l'exécution Windows. Rapport : `tests/checker-selftest-report.json`.
- **11 fonctions critiques identiques après normalisation des fins de ligne** par comparaison textuelle avec la RC1. Le détail et les empreintes sont dans `tests/rc2-business-regression.json`.
- **8 ressources d'origine vérifiées par SHA-256** : configuration originale, icône et six fichiers du module AD. Seuls les chemins ont changé. Référentiel à cette révision : `tests/original-assets.json`. **État courant du référentiel (11/10/2026) : 7 empreintes.** `wad/cfg.original.json` en a été retiré — c'est un fichier utilisateur, gitignoré, écrit par le produit à la première utilisation et jamais livré : aucune empreinte n'en est vérifiable dans un dépôt, et l'exiger rendait la garde rouge par construction ; la préservation de la configuration d'origine d'un poste reste un contrat d'exécution du produit, pas une empreinte statique. `wad/icone.ico` y figure sous son nom courant `wad/Pesto.ico`, à octets identiques (`e1d9fa9e…`). Les six fichiers du module Active Directory sont inchangés.

Les vérifications statiques portent notamment sur les délimiteurs PowerShell, cinq gabarits XML/XAML, les liaisons de contrôles, les dépendances lexicales des workers, les gardes métier, l'encodage des CMD, la structure du bloc PowerShell autonome, les chemins de ressources et les scripts de compilation/tests.

Le validateur Python n'est pas un parseur PowerShell natif. Ces résultats ne prouvent pas que l'interface, les appels AD, les CMD ou le déblocage NTFS ont été exécutés avec succès.

### Empreinte du moteur livré

`wad/GP-Core.ps1` :

```text
8f8aace297bf5d95762a175f2987bc565765a615f829a6e2f9d665eaf27ae7ed
```

## Limites explicites

Environnement de vérification : Linux, sans Windows PowerShell, WPF, Active Directory, UAC ou compilateur PS2EXE utilisable. L'acquisition d'un moteur PowerShell de test n'a pas abouti, faute de résolution réseau depuis le conteneur. Aucun résultat de parseur natif ou de test Windows n'est donc revendiqué.

**Non exécutés :** `Run-EngineTests.ps1`, `Run-PackageTests.ps1`, les CMD sous cmd.exe, le retrait réel de flux Zone.Identifier, la compilation, le lancement WPF et les opérations de domaine. La nouvelle suite Windows est fournie, pas déclarée réussie.

Le script de package teste les flux sur des fichiers temporaires et utilise un moteur factice pour vérifier le lanceur. Il ne charge ni le moteur réel ni l'AD. La recette Windows reste nécessaire.

## Points à conserver lors d'une mise à jour

La configuration active se trouve désormais dans `wad/cfg.json`. Elle conserve l'incohérence `o.LOCAL` / suffixes `DC=labo,DC=local` signalée dans la RC1. **1 avertissement de configuration subsiste** : corriger et vérifier les valeurs avant connexion réelle.

La fonction de stockage de reprise n'a pas été modifiée. Son identifiant dépend toutefois du chemin absolu de la configuration : déplacer cette dernière vers `wad` ne migre pas automatiquement les reprises et verrous de l'ancien dossier. Fermer les anciennes instances et vérifier l'absence d'action en cours ou incertaine avant changement d'installation.

Le déblocage de fichiers n'est pas un déverrouillage métier. Il ne modifie pas les droits, ne lève pas les protections AD et ne supprime pas les règles de sécurité de l'organisation. `GP.cmd` demande RemoteSigned pour le processus de lancement seulement, sans modification persistante de politique.

## Démarrage de la copie de test

Extraire l'ensemble du dossier, double-cliquer sur `DEBLOQUER_TOUT.cmd`, confirmer avec O, puis lancer `GP.cmd`. Pour la démonstration : `GP.cmd -Demo`.
