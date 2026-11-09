# Campagne 1 — hôte Windows du labo, 2 octobre 2026

- Machine : DESKTOP-285EKHU, **hôte VirtualBox** (pas une VM du domaine), Windows 11 Pro 10.0.26200.
- Moteur : **Windows PowerShell 5.1.26100.9549 Desktop x64**.
- Compte : `degun`, session **SSH non interactive** (pas de bureau, pas d'UAC). Copie dans `C:\Users\degun\pesto-claude`.
- Pack : `DEV/` du commit c2e62e2 ; `Pesto.exe` SHA-256 `d844c2fc5b9e08ebd6aee7d563503138b3d70ca8ecd14ab4af3b4545d47e45e2`.

| Contrôle | Résultat |
|---|---|
| `outils/parse_all.ps1` (vrai parseur 5.1) | 68 fichiers, 0 erreur |
| `Pesto.exe --check-json` (PE réel, sans UAC ni AD) | code 0, Runtime PASS, 38 composants |
| `Run-StabilisationTests.ps1` | 8/8 (doubles AD) |
| `Test-Pesto19.ps1` | vert |
| `Run-NamesLoadingTests.ps1 -Wpf` | vert, 25 OK |
| `Run-Pesto21Tests.ps1 -Wpf` | vert, 61 PASS |
| `Run-Pesto22Tests.ps1 -Wpf` | vert, 33 PASS |
| `Run-Pesto23Tests.ps1 -Wpf` | vert, 65 PASS |

Sans `-Wpf`, les suites 21/22/23 sortent en 1 à cause du seul cas WPF en SKIP (pas d'échec).

**Ce que ça ne prouve pas** : WPF ici = chargement XAML et mise en page hors écran, sans interaction humaine ;
aucune UAC, aucun AD/Entra réel, aucune mutation, aucun démarrage de l'interface connectée. La matrice interactive
sur VM du domaine reste à faire.
