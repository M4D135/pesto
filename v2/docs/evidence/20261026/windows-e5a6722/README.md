# Preuves Windows et laboratoire — e5a6722

Source : `e5a67227449e60ca8b91dc7a397a7671d51a6378`. [Campagne GitHub réussie](https://github.com/M4D135/pesto/actions/runs/40368778290). Téléchargements : [PROD](https://github.com/M4D135/pesto/actions/runs/40368778290/artifacts/12671514909), [DEV](https://github.com/M4D135/pesto/actions/runs/40368778290/artifacts/12673057185), [preuves Windows](https://github.com/M4D135/pesto/actions/runs/40368778290/artifacts/12671679566).

EXE : `9e2f6eb2400d7d06d219d3a435d24f72b8dbf336120139153437313e703a5336`. Runtime WebView2 : `156.0.4314.42`. PROD et DEV ont le même exécutable et des manifestes distincts.

| Archive candidate | SHA-256 |
|---|---|
| PROD | `7ae21e3395562ed44da692747000cffa12e3292d8f48766ba019f48082854b2d` |
| DEV | `9eac46b4adfb853c88329326b6572ae7dbde649f1301f541a28afa7bab3aeec2` |

## Campagne automatisée

203 tests moteur, 15 du pont, 30 du compagnon de mise à jour, 70 gardes de retour AD sans mutation ; PS5.1 : 18 variantes et entrée de banc analysées, deux contrôles UTF-8. Chromium : 33 maintenance, 41 opérateur, 9 démo, 28 accueil et 149 statiques. Accueil natif : cinq contrôles ; saisie native : seize. PROD et DEV : 14 contrôles de configuration par canal, six transitions de démo et 44 API réelles refusées. Quatre transactions entre deux compilations, huit reçus santé et sept lancements du helper sont recoupés avec les archives exactes.

## Paquet exact en VM

Le pack PROD GitHub exact de `e5a6722` passe accueil, saisie native AD synthétique, démonstration et configuration, puis une élévation UAC réelle depuis un parent non élevé, en session console 1. Les cinq parcours terminent avec code 0. Les bancs restent isolés du profil ordinaire et ne font aucun appel AD.

Le renommage réel `P111301VA765158` → `P111301VA765586`, sa vérification après redémarrage et le retour au nom initial sont confirmés. L’inspection finale du 26 octobre à 17:41 UTC retrouve le même GUID, Paris, UAC4096, protection false, domaine et canal sécurisé sains, noms actif/configuré cohérents et aucun renommage en attente. Les cinq anciennes entrées V1 sont inchangées. Le déplacement Paris → Lyon → Paris reste lié au moteur C9 et à son rapport historique.

Les packs restent `official=false`, `distribution=candidate`, `qualification=unqualified`. La jonction/sortie positive, l’élévation sous une autre identité, UNC réel, Program Files, acquisition depuis une release officielle et les autres parcours externes du rapport restent à qualifier. Aucune release V1 n’est remplacée.

## Fichiers

- `windows-summary.json` : résultats CI, identités des packs, empreintes des preuves.
- `vm-summary.json` : installation vérifiée, codes de sortie et contrôles natifs, preuve du jeton UAC et du même EXE.
- `ad-summary.json` : chronologie C13/C14, empreintes de chaque preuve, vérification du retour et conservation de l’historique.
- `virtualbox-final.json` : état final de la seule VM, séparé du blocage du redémarrage Windows et de la réinitialisation autorisée.
- `github-artifacts.json` : identifiants, empreintes d’enveloppes et expiration des artefacts GitHub.
- `connexion.png`, `connexion-erreur.png` : captures du binaire GitHub dans la VM.

Les reçus AD proviennent du harnais compilé localement avec les sources indiquées dans `ad-summary.json`. Ils ne sont pas attribués au hash du single-file produit par GitHub. Les échecs intermédiaires et la réinitialisation du seul invité après blocage du redémarrage sont conservés dans [le rapport C14](../../../VALIDATION-C14-20261026.md). La preuve UAC couvre le même compte ; les saisies synthétiques ne prouvent pas tous les scénarios d’authentification.
