# Guides Word et PDF de Pesto

Les guides livrés dans `DEV/docs` sont fabriqués ici à partir du texte (`technicien.md`,
`administrateur.md`) et des fiches JSON correspondantes (titres, page de garde, figures).
Corriger les sources puis régénérer les livrables, sans modifier le Word à la main.

```bash
cd outils/guides
npm install                                  # une fois, module docx déclaré dans package.json
node build_guide.js technicien.json --no-pdf
node build_guide.js administrateur.json --no-pdf
```

Pour les livrables qualifiés, convertir chaque DOCX avec le renderer `render_docx.py` du
skill Documents de Codex (`--emit_pdf --output_dir DOSSIER`) ou un moteur bureautique
compatible. Relire toutes les pages PNG obtenues, puis copier les DOCX et PDF approuvés
dans `DEV/docs`. Le PDF doit provenir du DOCX relu. Le PDF HTML produit par défaut par
le constructeur reste un aperçu distinct : sa pagination ne prouve pas celle du Word.

Le constructeur accepte `PESTO_DOCX_MODULE` pour utiliser un module docx déjà installé.
Le rendu qualifié utilise Liberation Sans pour le corps et Liberation Mono pour le code.
Un changement de police ou de moteur peut modifier la pagination : refaire la vérification
visuelle. Le rapport `preuves/guides-zoom-2026-10-12/summary.json` identifie les livrables,
leurs empreintes et les contrôles de cette édition.

## Syntaxe du texte

| Élément | Écriture |
|---|---|
| Chapitre (nouvelle page, entrée du sommaire) | `# 7 Ajouter un PC au domaine` |
| Section | `## Préparer` |
| Paragraphe | une ligne |
| Étape numérotée | `1. **Titre court.** Texte de l'étape.` |
| Puce | `- texte` (un seul niveau) |
| Tableau | `\| A \| B \|`, `\|---\|---\|`, puis les lignes |
| Encadré | `> [!ATTENTION] …`, `> [!ASTUCE] …`, `> [!RESULTAT] …`, `> [!NOTE] …` |
| Figure | `![Légende](fig:ID)`, l'ID étant déclaré dans la fiche JSON (fichier et largeur en cm) |
| Commandes (police à chasse fixe) | bloc entre deux lignes de trois accents graves |
| Gras | `**mot**` |

Le programme refuse une figure inconnue ou utilisée deux fois et signale une syntaxe non prise en charge
(`###`, citation).

## Captures (`images/`)

Les figures référencées par les deux fiches sont dans `images/v1/` et `images/ui-2026-10-12/` : captures natives
1920 × 1160, issues de l’interface Windows réelle, sans infobulle ni agrandissement artificiel.
Les originaux et la correspondance par SHA-256 sont identifiés dans le rapport de preuve.
Les préparations, confirmations et résultats de lecture ou d’exécution sont distingués dans
les légendes. Une capture de préparation ne vaut pas validation de l’opération.

Conserver la résolution native lors d’un remplacement. Après toute modification de figure
ou de légende, régénérer le DOCX et son PDF puis contrôler les pages concernées.

## Kit pour un autre logiciel

`PROMPT_GUIDES_AUTRE_LOGICIEL.md` (et sa version à coller `.txt`) décrit la méthode ; `LIRE-KIT.md` et `exemple/`
accompagnent l'outil dans l'archive `KIT-GUIDES-<date>.zip` (fabriquée avec `fabriquer_kit.sh`). Prompt et kit éprouvés le
07/10 par un agent indépendant (guide d'un logiciel fictif jusqu'au PDF) et une revue adverse contre-vérifiée.
