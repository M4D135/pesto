# CLI JSON — Windows PowerShell 5.1 — 14 octobre 2026

Scripts locaux non commités, copiés vers `C:\PestoCli_20261014\DEV`.
Le banc remplace l'intégrité et le moteur par des fixtures. Aucune mutation AD.
EXE local du Mac au moment du test : `ca421fdce24a12c4adc7f6ca3ad9ea3b049c3d713be09d45482f2aa58fcbc21e`.
Cet essai ne qualifie pas cet EXE : `Run-CliOutputTests.ps1` n'a pas lancé `Pesto.exe`.

VM `PESTO-W11-TEST`, démarrée pour ce banc puis arrêtée. État final VirtualBox : `poweroff`.
PowerShell : 5.1.26100.6584.

| Passe | Cache module | Résultat |
|---|---|---|
| Chaud | présent, 81188 octets, horodaté 2026-10-10 23:00 | 12/12, code 0 |
| Froid | fichier retiré avant le banc, absence constatée | 12/12, code 0 |

Le cache d'origine a été remis : même taille, même horodatage du 10 octobre.
Les deux échecs C4 (`Preparing modules for first use.` en CLIXML) ne se reproduisent pas sur ces scripts.
