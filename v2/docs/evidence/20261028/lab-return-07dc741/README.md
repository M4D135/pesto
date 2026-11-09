# Preuves de laboratoire C18 — retour vers Paris

État historique couvert par ce lot, le 28 octobre 2026 : nom **LY715**, Paris confirmé ; restauration du nom original et jonction d’un nouveau compte non effectuées. Dernière lecture AD indépendante incluse dans ce lot : **11:25:23 UTC**. La [suite de l’incident](../../../INCIDENT-C18-DISK-20261028.md) atteste la suppression de l’ancienne VM à 13:31:57 UTC ; la campagne est close et la reconstruction différée. L’ancien snapshot n’est plus un moyen de retour disponible. Les huit preuves ci-dessous conservent leurs octets et empreintes historiques.

Le [manifeste](manifest.json) porte les SHA-256 de chaque fichier, ceux des captures sources et la transformation des projections. Les originaux privés restent conservés dans la session de qualification.

| Fichier | Portée |
| --- | --- |
| [credential-format-refusal.json](credential-format-refusal.json) | Copie exacte du refus du premier essai, avant écriture AD. |
| [preparation2.json](preparation2.json) | Projection du second essai réussi, sans exécution. |
| [move-durable-receipt-wrapper.json](move-durable-receipt-wrapper.json) | Copie exacte du wrapper du reçu move 42ca, code 30 / Verified. |
| [move-independent-after.json](move-independent-after.json) | Copie exacte de la relecture AD du harnais après déplacement. |
| [move-local-result.json](move-local-result.json) | Projection du code de sortie et des noms, boot, domaine et canal Windows. |
| [independent-domain-after-move.json](independent-domain-after-move.json) | Projection de la lecture distincte prouvant GUID/SID et Paris. |
| [backup-and-transfer-cleanup.json](backup-and-transfer-cleanup.json) | Résumé du snapshot froid et des seules copies temporaires identiques supprimées. |
| [harness-provenance.json](harness-provenance.json) | Source 07dc741 / DLL b8, SDK local et distinction avec les ZIP CI 2adf60e. |

Le wrapper du reçu contient un objet JSON parsé et l’empreinte du reçu GP d’origine ; il ne constitue pas un transfert de ses octets bruts. Son propre SHA-256 est distinct et figure au manifeste. Les projections omettent notamment l’inventaire matériel/SSH et la liste des fichiers publics. Aucun fichier de configuration n’est inclus.
