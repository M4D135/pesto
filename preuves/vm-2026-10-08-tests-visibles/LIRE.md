# Tests GUI visibles — PESTO-W11-TEST, 08/10/2026 soir

Pilotage de la vraie fenêtre WPF dans la session ouverte (LABO\tech.pesto, AD réel du labo labo.local),
lancé par `outils/labo/mac/tests-visibles.sh`. EXE cbb0b008 (pack PROD dans C:\PestoDemo et C:\PestoDemo2),
registre partagé C:\PestoRegistre, réservation AD active, hasard 0. Journal : `deroulement.txt`.

| Étape | Ce qui est fait dans l'interface | Résultat observé |
|---|---|---|
| t-30 | Deux Pesto côte à côte, même site/service/type | A propose P111301VA765004, B P111301VA765005 ; deux réservations distinctes ; aucune collision (`t30-1-cote-a-cote.png`) |
| t-10 | Renommer, même site (Paris) : lire le poste, organisation, site, service 765, type, Vérifier puis renommer, Confirmer | P111301VA765003 → P111301VA765004, aucun déplacement (`t10-*.png`, `t10-op.txt`) |
| redémarrage | Redémarrage de la VM, ouverture de session | nom actif P111301VA765004 (`vm-t10-ouverture-session.png`) |
| t-15 | « Un poste » affiche « Vérifier l'opération » et la cause ; clic, vérification, « Consigner la vérification », Confirmer | conforme au plan, consigné, bouton revenu à « Lire ce poste » (`t15-verification.txt`) |
| t-20 | Renommer avec changement de site Paris → Lyon | P111301VA765004 → P111301LY765002, déplacé dans OU=Lyon (`t20-*.png`, `t20-op.txt`) |
| redémarrage | idem | nom actif P111301LY765002 (`vm-t20-ouverture-session.png`) |
| t-25 | Vérification après redémarrage, comme t-15 | conforme, consigné (`t25-*.png`, `t25-verification.txt`) |

Limites et défauts constatés :

- Les captures de t-15 portaient le nom `System.Diagnostics.Process (Pesto)-*` (variable `$p` du processus qui écrasait
  le préfixe `$P`, PowerShell ignore la casse) ; t-25 les a écrasées. Les captures `t25-*.png` sont celles de t-25 ;
  pour t-15 il reste le journal `t15-verification.txt`. Script corrigé (`$proc`).
- Le texte de confirmation affichait « Site VA conserve … aucun deplacement » et « deplacement automatique apres
  renommage confirme » sans accents : corrigé dans `Pesto-Operations.ps1` (EXE suivant).
- La ligne « reprise après redémarrage (RunOnce) : absente » des journaux t-10/t-20 vérifie seulement qu'aucune entrée
  RunOnce n'est écrite (option retirée) ; libellé du script mis à jour.
- `t30-deux-pesto.txt` est pollué par la sortie des fonctions d'aide (UTF-16) : les noms proposés sont lisibles dans
  la capture et dans la ligne « réservations après B ».
- Registre relu à 19:45 : P111301VA765004 (propriétaire ca99eb, le Pesto A de t-30 réutilisé par t-10) et
  P111301LY765002 (bf6cb8, t-20) restent réservés jusqu'à leur expiration (15 min) : le redémarrage a fermé Pesto
  sans libération. Comportement voulu : la réservation couvre la réplication AD vers les autres contrôleurs.
- Journaux `*.txt` de la VM en UTF-16 (sortie `*>` de Windows PowerShell 5.1).

## Contrôle de l'EXE suivant (5fb95962, accents de la confirmation)

`suite-windows-5fb95962.txt` : parseur 5.1 66 fichiers 0 erreur, `--check-json` 0 (DEV et PROD), stabilisation 27/27,
noms 25/25, services 14/14, blocage 14/14, registre SMB 15/15, jonction 23/23, paramètres 15/15, UX : les 2 mêmes mesures
de mise en page KO qu'avant (sans bureau). La mise à jour de C:\PestoDemo a d'abord échoué (le PowerShell de Pesto, lancé
par Pesto.exe, tenait encore des fichiers ; seul Pesto.exe avait été arrêté) : processus arrêté par sa ligne de commande,
dossier recopié, cfg de test remis ; C:\PestoDemo et C:\PestoDemo2 : EXE 5fb95962, `--check-json` 0.
