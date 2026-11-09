> Document historique de la RC1. Les chemins et empreintes ci-dessous correspondent à l’archive précédente. Pour la RC2 avec wad, lire BILAN_LIVRAISON.md.

# Bilan de livraison — GP 17.0-RC1

## Artefact

Base examinée : `GP.zip`, GP 16.0-HD. Livrable : source principal modifié, ressources conservées, configuration originale, exemples, documentation, tests et script de compilation. **Version de préproduction ; pas d’EXE compilé et pas de validation Windows réelle réalisée ici.**

SHA-256 de `GP.ps1` :

```text
3933c8860425525906f0578e42f3cb5394625d4fc356ae4e57ff069f4436b007
```

Le relevé compare 161 fonctions racines d’origine à 195 fonctions racines livrées : **34 nouvelles et 48 définitions existantes modifiées**. Cette métrique n’inclut pas tous les changements de XAML, initialisation et handlers hors fonctions. Le diff complet est livré dans `changes/GP16-to-GP17.patch`.

## Contrôles réellement exécutés

**38 contrôles statiques sur 38 réussis, aucun échec de ces contrôles, un avertissement de configuration.** Rapport JSON : `tests/static-report.json` ; horodatage UTC : 2026-09-21T10:52:59.136125+00:00.

| Contrôle | Résultat observé |
|---|---|
| Encodage et scanner lexical du source, tests Windows et build | Réussi dans les limites du scanner |
| Gabarits de fenêtres XML/XAML | 5 gabarits XML bien formés |
| Liaisons des contrôles principaux | 93 noms retrouvés, aucun manquant |
| Fonctions exportées au worker | 48 déclarées, dépendances lexicales présentes avec helpers locaux |
| Gardes explicites contrôlées | Confirmation booléenne, protection, UAC/PID, état incertain, Entra opt-in, stockage atomique |
| Ressources héritées | 8 empreintes originales conservées : configuration, icône, fichiers du module AD |
| Démo/exemple | JSON lisibles, domaine/DN cohérents, GUI+simulation actifs pour la démo |

Le validateur statique a aussi subi **5 contre-tests négatifs, tous détectés** : liaison de bouton cassée, réparation Entra activée par défaut, garde de confirmation retirée, garde de protection retirée, guillemet typographique introduit. Ces essais modifient des copies temporaires et testent le validateur, **pas le comportement Windows de GP**. Rapport : `tests/checker-selftest-report.json`.

Les contrôles lexicaux ne sont pas le parseur natif PowerShell ; ils ne valident pas toute la syntaxe, le contenu des here-strings ou les types .NET. Le XML bien formé ne valide ni les propriétés WPF ni le rendu. Les contrôles de fragments de code ne prouvent pas l’absence de tous les défauts.

## Avertissement de configuration conservé

`CONF[0].Domaine = o.LOCAL` ne correspond pas à `DC=labo,DC=local`. Les valeurs et noms d’OU ont été conservés ; GP demande leur correction avant connexion. **Un bilan statique vert n’autorise pas à utiliser cette configuration réelle telle quelle.** `cfg.original.json` reste inchangé.

## Non exécuté dans l’environnement de livraison

Le parseur Windows PowerShell 5.1, `Run-EngineTests.ps1`, les interactions WPF, les opérations Active Directory, l’UAC et les pipes, le Planificateur COM, la compilation PS2EXE, la signature et la validation antivirus/EDR n’ont pas été exécutés. Le workflow GitHub livré n’a été ni installé ni déclenché dans un dépôt.

Le script de build relance la suite Windows avant compilation, mais une réussite de tests à doublures et de compilation ne remplace pas la matrice manuelle de `VALIDATION.md`. Les défauts propres au réseau, aux délégations, à la politique UAC, aux DLL héritées, au DPI et à l’EDR restent à valider.

## Principales limites à conserver dans la recette

Une seule instance par configuration ; pas de coordination interprocessus. Pas de délai maximal absolu pour un RPC bloqué. Pas de transaction globale ni garantie de convergence AD. Levée du verrou sur contrôle manuel de l’opérateur, pas sur auto-réparation. Reprise locale non signée ; noms d’OU et résultats sensibles dans les fichiers. Conservation possible de tâches GP incertaines à examiner sur les cibles.

L’archive originale n’a pas été modifiée. La nouvelle archive exclut les anciens journaux, anciennes versions et l’ancienne documentation, et inclut sa propre documentation. Les droits et signatures des composants tiers doivent être revus avant redistribution.
