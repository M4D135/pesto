# 8 octobre 2026 — démonstration réelle de Pesto sur l'AD du labo (captures des guides)

Vrai pack PROD (`C:\PestoDemo`, cfg.json réel : Simulation et GUI à false), Windows 11 et Windows PowerShell 5.1 sur
`PESTO-W11-TEST`, domaine `labo.local`, émulateur PDC `dc01`. Objets de recette créés par `outils/labo/mac/demo-reelle.sh
--preparer` (mot de passe tapé par David) : OU `Departement 111301` sous `ADCC-Lab` (Postes, Staging, SITES, Paris, Lyon),
6 postes désactivés, compte `LABO\tech.pesto` (droits délégués sur cette OU seulement), jonction de la VM. Session console
de `tech.pesto` (ouverture automatique posée par David), Pesto piloté par UI Automation (`outils/labo/vm/demo/`,
`outils/labo/mac/demo-captures.sh`). Nettoyage par David (`--nettoyer` : 7 postes, le compte et 6 OU supprimés), VM remise
sur l'instantané à froid `04-avant-demo-reelle-20261007`.

- `defauts/` : premier essai. Un reçu de jonction du 04/10 (préfixe 999004) bloquait toute opération (97, « Résultat
  incertain » alors que rien n'était lancé : `13-bilan.png`) et rendait la liste des interventions illisible
  (`22-interventions.png`). Corrigé (R1, R2 de `DEV/docs/V1_CONSTATS_OUVERTS.md`), EXE `43af2ab3…` puis `f1d88060…`.
  L'opération restée incertaine (enregistrée avant le correctif) a été terminée comme le ferait un administrateur
  (renommage avec le compte de la session), puis vérifiée et consignée par Pesto.
- `operations/` : opérations réelles par Pesto : renommage sur le même site (Lyon, `70-*`), vérification et consignation
  après redémarrage (`75-*`), changement de site Lyon → Paris (renommage puis déplacement, `80-*`), vérification et
  consignation (`85-*`), inventaire réel (`90-noms.png`). Journaux du pilote en `*.txt`.
- `ecrans/` : accueil, historique (texte corrigé : mise en garde sur la simulation seulement s'il y a des lots simulés),
  interventions, sur l'EXE `f1d88060…`. `93-palette.png` ne montre pas la palette (Ctrl+K non reçu) : non utilisée.
- `rendus-labo/` : rendu de la vraie fenêtre (« Ajouter au domaine », bilan de jonction) avec les valeurs du labo : la VM
  était déjà dans le domaine, la page de jonction hors domaine ne pouvait plus être capturée réellement.

La VM s'est figée trois fois (démarrage ou lecture distante, problème connu NEM) : réinitialisée (`controlvm reset`).
