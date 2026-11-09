# Intégration locale du contrôle de kit UI

Preuves du 28 octobre 2026 avant le commit final, sur une base `e18d0f89` avec
la marque Pesto ajoutée dans le working tree. `sourceCommit: null` est conservé
pour cette collecte ; elle ne se présente pas comme l’exécution d’un binaire livré.

- [Validation locale](ui-kit-local.json) : 28 fichiers, cinq adaptations explicites,
  aucun écart ; amont non comparé dans cette commande.
- [Comparaison](ui-kit-compare.json) : mêmes 28 fichiers sans écart contre l’export
  canonique Domenia V2 déclaré `75778d1d`. Le rapport garde explicitement le statut
  `declared-not-git-proven` pour le commit de cet export.
- [Revue du bootstrap](ui-kit-bootstrap-review.json) : neuf fixtures locales passent,
  dont refus d’un comparateur altéré, pin modifié, doublon JSON, lien, produit jeu,
  adaptation non déclarée, fichier manquant et fichier dérivé.
- [Script de la revue](check_ui_kit_adversarial.py.txt) : copies temporaires supprimées
  à la fin ; aucun réseau, runtime produit ou accès machine.

Le comparateur et son schéma ont aussi été relus via le connecteur GitHub au
commit Common exact `67ae057d3f46dbb9a72562b3f444a8fd069b10c5` et leurs deux
SHA256 correspondent aux pins. Les huit fichiers du transfert correspondaient
à son inventaire ; après intégration, le workflow cible la branche Pesto,
la documentation décrit le vendor réellement livré et le pin de `shell.css`
inclut les adaptations Pesto explicitement décrites.

La CI Common de ce nouvel outil est signalée bloquée par la facturation,
sans verdict de réussite affirmé ici. La validation Windows de notre intégration
reste à obtenir. Aucune qualification UI exhaustive, métier, AD ou de production
n’est attribuée à ces contrôles. Voir le [contrat du kit](../../../UI-KIT.md).

Le [manifeste](manifest.json) épingle les six pièces de preuve d’origine.

## Disposition des sources dans DEV

Le bootstrap initial signalait [28 fichiers manquants](ui-kit-dev-layout-before.json)
dans la copie DEV : les fichiers sont sous `wad/dev/web`, tandis que le lock
conserve les chemins du dépôt `v2/web`. Le bootstrap Pesto projette maintenant
uniquement ces chemins locaux dans un manifeste temporaire. Le comparateur Common
reste inchangé. Trois [contrôles ciblés](ui-kit-dev-layout-after.json) passent :
validation locale, comparaison canon et détection d’un fichier UI modifié.
Les 33 fichiers de la fixture restent identiques après les deux lectures valides.
Les neuf fixtures de refus ont ensuite été rejouées avec ce bootstrap final.
