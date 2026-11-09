# Kit commun Domenia — contrôle local

`v2/web/ui-kit.lock.json` fixe les octets de 28 fichiers communs de Pesto et leur référence
Domenia `75778d1df7777e601fe9179d2d075e19d7d9644c`.
Les chemins sont relatifs à la racine du dépôt. L’adoption déclarée est partielle :
ce manifeste ne couvre ni toute l’interface ni le moteur métier.

Le kit reste une copie locale livrée avec l’application. Aucun téléchargement,
import partagé à l’exécution ou changement d’authentification n’est introduit.
Les adaptations de Pesto sont nommées dans le manifeste. Leur empreinte locale et
celle du fichier canonique restent toutes deux obligatoires ; une adaptation
n’autorise pas une dérive libre. Les animations actuelles sont conservées.

Les images PNG, l’icône Windows et les écrans de marque propres à Pesto restent
hors de ces 28 fichiers communs. `js/icons.js` conserve les pictogrammes dérivés
de Domenia mais remplace son logo par la marque Pesto ; sa provenance et son
empreinte sont suivies dans `web/provenance.json`. La règle de dimensions du logo
dans `css/shell.css` est une adaptation Pesto explicite du présent lock. Aucun
asset de marque Pesto n’est déclaré identique à un asset Domenia.

Le contrôle historique `web/provenance.json` et `tools/tests/web-check.mjs` reste
actif. Le nouveau manifeste ajoute le lien explicite de chaque fichier vers le
canon actuel, sans réécrire les variantes métier (notamment les confirmations).

## Vérification sans réseau

Le contrôleur standard de `M4D135/m4d-admin-common` est livré dans
`v2/tools/m4d-components/`, à la révision exacte
`67ae057d3f46dbb9a72562b3f444a8fd069b10c5`. Son lock fixe les empreintes et tailles
du programme Python et du schéma ; `v2/tools/check-ui-kit.py` les vérifie avant
de lancer le comparateur avec `python -I -S`. Aucun package tiers, téléchargement
ni import par le runtime du produit n’est nécessaire. Depuis la racine du projet :

```text
python3 -I -S v2/tools/check-ui-kit.py
python3 -I -S v2/tools/check-ui-kit.py --canonical-root <canon> --canonical-manifest <canon>/ui-kit.canonical.json
```

Dans le ZIP DEV, depuis `wad/dev`, la commande est
`python3 -I -S tools/check-ui-kit.py`. Le bootstrap adapte uniquement le préfixe
des chemins locaux `v2/` dans un manifeste temporaire supprimé après le contrôle.
Le lock livré, les chemins et empreintes amont et les adaptations restent
inchangés ; aucun fichier source livré n’est réécrit.

Sans canon fourni, le contrôle vérifie les fichiers locaux et marque l’amont
comme non contrôlé. Les deux arguments canoniques déclenchent en plus la comparaison
avec la copie fournie. Aucun appel réseau n’est fait.
Le résultat JSON distingue conformité des octets déclarés et couverture : code
0 si cohérent, 1 si dérive, 2 si entrée invalide. Le SHA de commit déclaré ne
prouve pas à lui seul la provenance Git ; l’export du canon doit être fait depuis
ce commit exact et conservé avec sa preuve. Ces commandes ne certifient ni le
rendu visuel complet, ni Windows, ni les opérations métier.

Un changement du canon demande une comparaison explicite et une nouvelle revue
avant de mettre à jour les empreintes. Ne pas copier automatiquement les fichiers
au-dessus des adaptations du produit.

La CI `ui-kit-integrity.yml` exécute ce contrôle hors ligne sous Linux et Windows
sur les PR et les pushes de `master` et `codex/pesto-v2-20261023`. Le passage des tests locaux
ne vaut pas passage de cette CI. La CI Common de la révision du comparateur est
signalée bloquée par la facturation lors de l’intégration ; elle n’est pas déclarée
réussie. Le comparateur est un outil de construction et de revue, distinct des DLL
historiques Common 0.2.0/net472.
