# 7 octobre 2026 — fenêtres de résultat (captures reçues)

Captures reçues dans l'archive `PESTO.zip` du 07/10 (dossier `preuves-popup-20261007`, fichiers datés 12:22), produites
avant la relecture de Claude, sur l'EXE `5178edab…` (compilé avec le clang d'Apple 21, hors chaîne documentée). Elles
montrent les fenêtres de résultat ajoutées ce jour-là : `popup-renommer.png` (action directe), `popup-jonction.png`,
`popup-file.png` (bilan de la file). Non reproduites par Claude.

Vérification de Claude le 07/10 sur l'EXE final `92676b22…` (clang/lld 23.1.2, mêmes sources), Windows PowerShell 5.1,
VM `PESTO-W11-TEST` en SSH sans bureau : `--check-json` PASS (38 composants, syntaxe et writer PASS), `--check --quiet`
code 0, stabilisation 27/27, test WPF des services 10/10. Fenêtres de résultat non revues en session.
