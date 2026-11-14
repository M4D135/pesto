# 7 octobre 2026 — revue du design en session console (démonstration)

VM `PESTO-W11-TEST`, session console de `labadmin` (ouverture automatique posée par David), `DEMO.cmd`, Windows
PowerShell 5.1, EXE `921864d2…`. Captures prises par le pilote (UI Automation), pas une relecture humaine.

- `final-NavHome.png`, `final-NavRename.png`, `final-NavNames.png` : menu sans « Aide et raccourcis » (demande de
  David : retirer cette seule entrée ; le bouton « ? », le panneau d'aide, « Comprendre le parcours », F1 et les
  infobulles restent) ; aperçu « Nouveau nom : À définir » tant qu'aucun site n'est choisi (il affichait le nom actuel) ;
  Noms disponibles : filtre et colonne « Service ».
- Piège du labo : écran de la session en veille → captures figées (horloge arrêtée, fenêtre blanche). `eveil.ps1` les
  rétablit ; ce n'était pas un défaut de Pesto.

## Mode clair et mode sombre (rendu hors écran, 07/10 vers 20 h 45)

`Light-*.png` et `Dark-*.png` : Accueil, Un poste, Noms disponibles, Paramètres, Journal, Historique, rendus sous Windows
PowerShell 5.1 (VM, SSH, STA, sans session console) par `render-theme.ps1` : le banc `tests/Run-UxTests.ps1` (vraie
fenêtre `Pesto-Shell.xaml`, vraies palettes, vrai `Set-Theme`) complété d'un rendu `RenderTargetBitmap`. Sans données
(aucune démo chargée) et sans contexte : en-tête vide, « Thème : Clair » dans Paramètres même en sombre (le banc appelle
`Set-Theme` directement ; dans l'application, `Set-PestoThemeMode` synchronise la liste). Aucun défaut de contraste ou de
couleur relevé en sombre ; menu sans « Aide et raccourcis ».

## Contraste élevé et échelles (rendu hors écran, 07/10 vers 21 h 30)

`render-hc-echelles.ps1` (même banc) : vraie conversion `ConvertTo-PestoHighContrastPalette` avec les couleurs système des
thèmes Windows « Nuit » (fond noir) et « Désert » (fond clair), `HC-*.png` ; échelles 125, 150 et 200 % (place logique
d'un écran 1920 × 1040, rendu à la densité correspondante), `Echelle*.png`. La session sans bureau plafonne la fenêtre à
1044 × 788 unités.

- Couleurs système appliquées, anneau du menu actif visible (X5). **Défaut corrigé** : l'icône lune de l'en-tête avait
  une couleur fixe violet pâle, peu visible sur fond clair (thème clair et « Désert ») ; elle suit la couleur de texte du
  thème (`FgText`), vérifiée sur les deux rendus.
- 200 % : le banc garde la taille minimale 1000 × 620 du XAML, plus grande que la place d'un écran 1080p à 200 %. Pesto
  réduit lui-même ce minimum à la surface de travail au démarrage (`Pesto-Core.ps1` vers la ligne 2422,
  `Pesto-Appearance.ps1` vers la ligne 221), code non joué par le banc : pas de défaut retenu. Menu défilant et libellés
  repliés lisibles à 200 %.

## Page « Ajouter au domaine » pour les guides (rendu hors écran, 07/10 vers 21 h 30)

`render-jonction.ps1` (même banc, sur `C:\PestoTest`) : vraie fenêtre, vrai `Pesto-Join.xaml` (SHA-256 `5932eae3…`,
identique au dépôt) remplie de valeurs fictives (DESKTOP-7Q2K4LM, example.local, Portable, Paris, service 765,
P111301VA765003, INC-2026-0412) ; `Light-Jonction.png` (haut de page), `Light-Jonction-nom.png` (partie « 2. Son nom et
son emplacement », reprise dans les guides). Banc : 43/45, les 2 écarts sont les mesures de mise en page déjà connues
en SSH sans session. VM éteinte ensuite.

## Rendus en mode réel pour les guides (08/10 vers 0 h)

`render-guide.ps1` : même banc, mode réel forcé (`GUI`, `SIM` faux, domaine example.local), en-tête renseigné (poste,
domaine, compte fictifs), accueil sobre, Un poste, Noms disponibles (lignes fictives, ligne d'inventaire au format réel),
Historique, Ajouter au domaine, fenêtre de bilan (vrai gabarit de `Show-PestoPanel`, texte du code 10 de `Pesto-Join.ps1`).
Images dans `preuves/vm-2026-10-07-reel/`, sans aucune trace de démonstration (contrôle OCR). Banc 43/45 (2 mesures de
mise en page connues sans session). Ce sont des rendus de la vraie fenêtre, pas une opération réelle.
