# Preuve OCR — fenêtre d'initialisation « Pesto » (09/10/2026)

Relue depuis le Spark le 10/10/2026, à distance, sans passer par le Mac : le
Spark n'a aucun identifiant GitHub et ne peut pas pousser. Ce fichier est déposé
à côté de l'image qu'il commente.

## Ce que cette preuve établit, et ce qu'elle n'établit pas

La capture `fenetre-initialisation.png` (produite le 09/10 sur la VM de labo,
session console 1 sous `LABO\tech.pesto`, après `eveil.ps1`) n'a **jamais été
lue** : la session Qwen Code qui l'a obtenue n'avait pas d'entrée image et
s'était contentée de statistiques de pixels (« 993 couleurs, 4,7 % de pixels
sombres ») — ce qui prouve une fenêtre rendue, pas le texte affiché.

Elle est relue ici par **OCR local**, qui est une lecture des pixels : la
chaîne affichée est bien établie. Ce n'est toujours pas un œil humain, et la
capture ne montre qu'un instant du démarrage (`Préparation…`).

## Source mesurée

```
fichier : preuves/vm-2026-10-09-marque/fenetre-initialisation.png
sha256  : ccf0f8bd924a432bbcc335322fa9411b1a5f78a7b98d98c22340f4574c68f004
taille  : 10 015 octets
mode    : RGBA, 620x330 (= taille client de la fenêtre)
```

L'OCR a tourné sur une copie locale de ce cadre, rapatriée du labo le 09/10
(`/home/m4d135/pesto-init-fenetre-2026-10-09.png`). Identité **vérifiée** le
10/10/2026 sur le Mac : le fichier committé ci-dessus vaut la même empreinte
`ccf0f8bd…` et la même taille que le fichier relu ici. La preuve porte donc bien
sur l'image committée, pas sur une copie dérivée.

## Méthode

`rapidocr-onnxruntime` (ONNXRuntime, CPU) dans un venv utilisateur, sans root :
`/home/m4d135/dav/tmp/pesto/ocr-venv`. Passage à l'échelle 1x et 3x (LANCZOS) —
les deux échelles concordent.

## Texte détecté (échelle 3x, coordonnées en pixels de l'image d'origine)

| x | y | confiance | texte |
|---|---|-----------|-------|
| 37 | 10 | 0.96 | `Pesto 1.0 — Initialisation` |
| 277 | 81 | **1.00** | `Pesto` |
| 280 | 112 | 1.00 | `Initialisation` |
| 48 | 144 | 1.00 | `Préparation...` |
| 46 | 266 | 0.83 | `0 s` |
| 539 | 266 | 1.00 | `Pesto` |

Échelle 1x : mêmes chaînes, mêmes positions (`Préparation...` à 0.99,
`Pesto` du titre à 1.00).

**Zéro occurrence** de `Gestion` ni `Postes` sur l'image entière.

## Conclusion

Le grand titre affiché de la fenêtre `Show-PestoStartupWindow` lit bien
**`Pesto`** (confiance 1.00), sous la barre `Pesto 1.0 — Initialisation` et
au-dessus du sous-titre `Initialisation`. L'ancienne marque « Gestion des
Postes » n'apparaît nulle part dans la fenêtre rendue. Le correctif du point 38
est donc **prouvé à l'écran**, et non plus seulement dans le XAML source.
