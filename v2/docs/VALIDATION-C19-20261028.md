# C19 — candidat intermédiaire, identifiants longs

La [CI 40691329646](https://github.com/M4D135/pesto/actions/runs/40691329646)
a réussi pour le SHA exact **e18d0f89d5f7fd60be8ce022fdf243d103cd3c81**.
Le job `122826598844` compte **25 étapes terminées avec succès**, sans étape
ignorée. Déclenchement à 12:51:42 UTC le 28 octobre 2026 ; dernier état final du
run à 13:24:35 UTC. Aucun test n’a été relancé pendant cette collecte.

Ce commit ajoute uniquement le retour à la ligne des identifiants longs dans
`web/css/components.css`, repris de Domenia V2, et met à jour son empreinte dans
`web/provenance.json`. Il conserve les animations existantes. La CI a terminé
ses étapes moteur/bridge, guards, navigateur, reconstruction DEV, configuration,
démonstration native, transactions entre builds et installation par l’interface.

Les [métadonnées du run](evidence/20261028/windows-e18d0f8-intermediate/workflow-run.json),
du [job](evidence/20261028/windows-e18d0f8-intermediate/workflow-jobs.json) et des
[artifacts](evidence/20261028/windows-e18d0f8-intermediate/github-artifacts.json)
sont conservées. Leurs digests restent ceux déclarés par l’API : **aucun ZIP C19
n’a été téléchargé ou recalculé localement**. Aucun nouveau livrable local C19
n’est annoncé.

Ce candidat devient intermédiaire à la demande de l’utilisateur : un logo et
une icône Pesto, puis le contrôle du kit commun, sont en cours d’intégration.
Le prochain commit comprenant ces changements doit passer sa propre CI avant
la collecte des livrables finaux. Les archives C18 déjà vérifiées sont préservées.

Ce verdict de CI ne constitue ni une qualification AD réelle, ni un UAC réel,
ni une preuve UNC/SMB ou sur profil utilisateur ordinaire. Les faits de la VM
et de l’incident disque gardent leurs rapports distincts ; aucune action machine
n’a été effectuée dans cette collecte.
