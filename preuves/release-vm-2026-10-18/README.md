# Livraison après qualification VM — 18 octobre 2026

Les packs proviennent du commit source propre `f21aede20f847a8e774ded93d9a4812a0151a471`. Le lanceur est `7ba3e7d3b8d4b75a10c4eb6dd60fb68ee2b0f562eb540d16b2f17e3c40e72230`. Les guides restent ceux validés précédemment (24 pages technicien, 66 administrateur).

- [Campagne VM et limites](../qualification-vm-2026-10-18/README.md) : opérations GUI/AD réelles, jonction après Sysprep, vérification du canal sécurisé après reboot et coordination SMB.
- [Vérification des packs](pack-verification.json) : chaque entrée comparée octet pour octet aux sources, noms uniques, ZIP intègres, configuration neutre et liste fermée du PROD.
- [Provenance](provenance.intoto.json), [SBOM](sbom.cdx.json) et [livraison](release.json) : inspection du build, déclaration non signée. L’inventaire [Microsoft](microsoft-components.json) ne prouve ni origine de téléchargement ni droits de redistribution.
- [Catalogue des 120 points](../../DEV/docs/implementation/RAPPROCHEMENT_120.md) : 102 implémentés, 6 retirés, 2 qualifiés dans leur périmètre, **10 qualifications ouvertes** (92,95,98,99,100,101,102,104,106,107).

Contrôles ciblés : portable 649/649, race 7/7, accessibilité 7/7, livraison 50/50. La CI du commit publié est consultable dans [GitHub Actions](https://github.com/M4D135/pesto/actions/workflows/validate.yml) ; ce dossier ne la déclare pas réussie avant son exécution. Les rapports de la livraison précédente restent historiques.

Le retrait de la signature (88) est conservé. Aucun second DC ni changement des politiques de sécurité n’a été créé pour fermer artificiellement les qualifications. Les preuves publiques et les packs sont archivés sur le Spark sous `/home/m4d135/pesto/releases/2026-10-18-vm-f21aede` après vérification de leurs empreintes ; aucune sauvegarde de VM sur le Mac.
