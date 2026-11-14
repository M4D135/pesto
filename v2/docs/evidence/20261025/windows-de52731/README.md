# Candidat C5 — qualification Windows du 25 octobre 2026

**Campagne réussie : [40230708170](https://github.com/M4D135/pesto/actions/runs/40230708170).**
Commit source testé : `de527313b98f30d52802ec6abd51804e12f8c298`, branche `codex/pesto-v2-20261023`.

Le workflow a construit, assemblé et exécuté les deux candidats sur un runner Windows 2025
(Windows NT 10.0.26100.0), avec leur runtime WebView2 fixe **156.0.4314.42**.
Le commit documentaire qui enregistre ce bilan ne reconstruit pas les binaires.
Les packs demeurent `official=false`, `distribution=candidate`, `qualification=unqualified` :
ces essais natifs ne constituent pas une qualification AD de production. Aucune release V1 n’est modifiée.

## Packs téléchargeables

| Canal | Artefact GitHub Actions | Archive interne |
|---|---|---|
| PROD | [Télécharger le candidat PROD](https://github.com/M4D135/pesto/actions/runs/40230708170/artifacts/12612902555) | `Pesto_V2_PROD_candidate.zip` |
| DEV | [Télécharger le candidat DEV](https://github.com/M4D135/pesto/actions/runs/40230708170/artifacts/12613416668) | `Pesto_V2_DEV_candidate.zip` |

GitHub emballe chaque archive dans un artefact. Extraire l’artefact, puis le ZIP interne :
le dossier `PROD` ou `DEV` contient **`Pesto.exe` et `wad` à sa racine**. Garder cet ensemble.
Le runtime .NET, WebView2 et le module Microsoft ActiveDirectory épinglé sont livrés avec le pack.
Il n’y a qu’un lanceur Pesto ; PowerShell 7, Spark et OpenCode ne sont pas nécessaires.
La rétention configurée pour ces artefacts de CI est de **30 jours** ; ce ne sont pas des assets de release.

Après configuration dans l’application, le bouton **Définir comme configuration par défaut** prépare
une distribution personnalisée distincte de ces candidats. Voir [Configuration](../../../CONFIGURATION.md)
et [Packaging](../../../PACKAGING.md).

### Empreintes du contenu distribué

Les valeurs suivantes sont enregistrées dans `artifacts.json` après les essais natifs.

| Fichier | SHA-256 |
|---|---|
| `Pesto.exe`, commun aux deux canaux | `438c4528d2c529f6b4a33225924330e47491cee9bb76ec1f121bebd639365848` |
| `Pesto_V2_PROD_candidate.zip` | `169e02fcbcbf8ac2c1cff53ad8a5ac7897dfcaa5344127691356edd5ca2861e6` |
| `Pesto_V2_DEV_candidate.zip` | `0741e606e74d2f09c0acb7df3ffa7d7bc6858efe200582a816f04df408b4f934` |

Les enveloppes d’artefacts GitHub ont des empreintes différentes :

| Artefact | Taille en octets | SHA-256 de l’enveloppe |
|---|---:|---|
| PROD | 369724049 | `0f87671ddc3fff09d72db321917e02bb0eb8fc6d2f9f1da8f93e594a3d570eb4` |
| DEV | 383829628 | `80211185ad529a23b3d2051c2051f0b288081a85ff6fbd1628bf22c7c8189137` |
| Preuves | 51843 | `b4649581a5815a5751656519f937544393e3e280ab12057287380d30b59cfeaa` |

L’enveloppe des preuves a été téléchargée et son empreinte vérifiée avant rédaction du bilan.
Les empreintes et tailles des deux gros packs sont celles du workflow et de GitHub Actions ;
ces archives n’ont pas été retéléchargées dans l’environnement de développement.

## Résultats établis

| Essai | Résultat |
|---|---|
| Analyse des scripts compilés par Windows PowerShell 5.1 | **18/18**, code 0, stderr vide ; aucune exécution métier |
| Suites moteur ciblées exécutées sur Windows | **171/171** sur fixtures, pont **15/15**, banc portable **10/10** |
| Démarrage/fermeture natifs en mode démo, PROD et DEV | Interface prête, fermeture normale, **44 refus directs par canal**, zéro invocation de l’hôte sentinelle, aucun profil réel sentinelle créé |
| Transaction PROD normale | Installation, santé WebView2 et rollback explicite réussis |
| Transaction PROD avec santé négative | Échec détecté, ancien pack restauré et contrôlé |
| Transaction PROD interrompue pendant la santé | Interruption constatée puis reprise native réussie |
| Préservation dans les trois scénarios | Source et configuration sentinelle inchangées ; deux tentatives de santé distinctes par cas ; état final `rolledBack` |

Les trois transactions emploient des copies physiques isolées du même pack PROD, avec versions de
manifeste synthétiques et une page locale volontairement invalide dans le cas négatif. Le vrai
EXE, le helper issu de ce même EXE et WebView2 sont exécutés sous Windows, avec leurs verrous de fichiers.

La [synthèse JSON](summary.json) ne contient que les résultats, compteurs et identités publiques du candidat.
Les [journaux et JSON natifs originaux](https://github.com/M4D135/pesto/actions/runs/40230708170/artifacts/12613546435)
restent dans leur artefact GitHub. Ils ne sont pas recopiés dans le dépôt.

## Limites à conserver

- Le smoke utilise une **fenêtre de démo masquée** pour l’automatisation. Il ne prouve pas une session AD normale,
  l’ouverture de la démo depuis cette session conservée, l’UAC avec un autre compte, ni la fermeture pendant une mutation réelle.
- Les scénarios, reset, identifiants et redémarrage fictif ont des contrôles moteur/interface séparés.
  Le smoke Windows ne parcourt pas tous leurs clics et ne vérifie pas visuellement la bannière sur chaque route.
- Les refus directs vérifient les garde-fous exercés ; le banc ne comprend pas de capture réseau indépendante.
- La qualification transactionnelle native porte sur **PROD seulement**. DEV est qualifié ici pour le démarrage,
  la fermeture et les refus de démo. Il n’y a pas d’essai entre deux builds applicatifs différents,
  sur un UNC réel, dans Program Files, ou sur une configuration réelle d’opérateur.
- Le canari AD, les attributs réels, ODJ/djoin, la CLI avec credentials, les politiques et interactions AD/SMB,
  ainsi que les parcours Entra et redémarrage réel restent à qualifier sur le laboratoire autorisé.
  Après publication du candidat, l’accès SSH à ce laboratoire a encore répondu `Connection refused`, code 255 ;
  aucune session ni mutation AD n’a eu lieu.

Voir le [rapport C5](../../../VALIDATION-C5-20261025.md) et la [recette Windows restante](../../../QUALIFICATION-WINDOWS.md).
