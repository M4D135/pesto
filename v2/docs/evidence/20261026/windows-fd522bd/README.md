# Windows C9 — fd522bd, 26 octobre 2026

Source binaire : `fd522bd61765834f5b66609a372900ecd1ab4ac3`.
[Campagne GitHub réussie](https://github.com/M4D135/pesto/actions/runs/40339777991).
[Rapport complet](../../../VALIDATION-C9-20261026.md).

## Candidats vérifiés

| Canal | Téléchargement | SHA-256 ZIP interne |
|---|---|---|
| PROD | [Archive](https://github.com/M4D135/pesto/actions/runs/40339777991/artifacts/12660346007) | `9fd929c8b9c91afdb20d45d49915b42522a08dfbd78ffee220530019faf0b015` |
| DEV | [Archive](https://github.com/M4D135/pesto/actions/runs/40339777991/artifacts/12659866271) | `f481e9e05a6534fa078e2d53603d0eb086a2df05374a025b1fc9bb983cfb8390` |

EXE commun : `8ebec5a431361e380872a4e6803e8e35bc7a3b31f2b2fab7c0a86c6c1bec97c6`.
Windows 2025, SDK .NET 10.0.302, runtime WebView2 Microsoft fixe 156.0.4314.42.
Les enveloppes téléchargées ont également été vérifiées contre leurs empreintes API ; elles sont distinctes des ZIP internes. Les métadonnées sont dans [summary.json](summary.json).
Les packs restent candidats (`official=false`, `qualification=unqualified`). Aucune release V1 n’est remplacée.

## Preuves CI

[Archive complète Windows](https://github.com/M4D135/pesto/actions/runs/40339777991/artifacts/12660076417).
Trois compilations sans avertissement ni erreur ; 201 tests moteur, 15 tests du pont, 30 contrôles du compagnon ; parsing PS5.1 de 18 variantes métier et du point d’entrée de qualification. Chromium : 33/41/8/149 contrôles réussis.

PROD et DEV : démarrage/fermeture, coexistence avec un parent en configuration locale, six transitions fraîches, contexte parent conservé, trois profils/deux instances/trois reçus distincts et 44 refus directs. Les huit captures ont été relues.
Les 14 contrôles natifs de configuration passent dans chaque canal, sur profils temporaires : export/import exacts, encodage invalide refusé, annulations, pack personnalisé complet, profil neuf et profil existant préservé.

Mise à jour entre `de527313b98f30d52802ec6abd51804e12f8c298` et cette source : trois transactions PROD (normale, santé négative, interruption/reprise) et une DEV (normale), toutes terminées par rollback explicite. Quatre identifiants distincts, huit reçus santé et sept lancements du helper recoupés ; sources, ZIP et sentinelle préservés.

## VM exacte et diagnostics

Le PROD exact de GitHub a été installé sur la seule VM PESTO-W11-TEST, avec 502 entrées SHA-256 vérifiées. En session console 1 non élevée : démo puis configuration réussies, codes 0, aucune exception UI enregistrée. [Synthèse du binaire exact](vm-fd522bd-ci-summary.json).

- Preuve démo : `522ba6ab74e89abb7742744a1b2651e08f9fe012d8ee571743cd4e365257c823`.
- Preuve configuration : `3f0e9eb009c0b805ad94800839e87eb79c144c399b64045fcbb2164201537425`.
- [Premier essai afa9ee7](vm-afa9ee7-summary.json) : preuve de configuration positive mais code 2, donc échec global conservé.
- [Essai fd522bd compilé localement](vm-fd522bd-local-summary.json) : 14 contrôles/code 0, EXE différent du binaire GitHub ; preuve distincte.
- [Diagnostic VirtualBox](virtualbox-diagnosis.json) : deux crashes immédiatement après l’arrêt en erreur de l’ancien enregistrement ; enregistrement désactivé sur cette seule VM, contrôleur vboxsvga restauré, stabilité ensuite observée. Aucune restauration de snapshot ni modification d’une autre VM.

Le harnais distinct passe l’inspection, les quatre refus et le déplacement Paris → Lyon → Paris, avec retour complet de l’identité initiale. [Preuves AD](ad-summary.json) et rapport C9. Cette campagne ne qualifie pas une sortie/jonction positive, les chemins UNC réels, l’acquisition de release officielle, UAC avec une autre identité, les ACL/DPAPI opérateur, ODJ ou Entra. La sélection positive du dossier de pack et la coexistence avec un parent AD connecté restent séparées.
