# Livraison du 18 octobre 2026

Sources : `dab2772abd4a525cba13814005fb9a3a6497fe00`, arbre propre lors de la génération des archives et de la provenance. [Le rapport de finalisation](../../DEV/docs/implementation/proofs/FINALISATION_20261018.json) donne les corrections, empreintes, résultats et limites. Les archives publiées sont dans [packs](../../packs/README.md).

- [release.json](release.json) : EXE, guides, archives et références des vérifications.
- [pack-verification-dab2772.json](pack-verification-dab2772.json) : archives lisibles, EXE et guides identiques aux sources, configuration neutre, trois sources C# présentes dans DEV et absentes de PROD.
- [SBOM](sbom.cdx.json) et [provenance](provenance.intoto.json) : inventaire et inspection du build fourni ; déclaration locale non signée, sans attestation d'un constructeur de confiance.
- [Composants Microsoft](microsoft-components.json) : inventaire observable ; présence et empreintes ne prouvent ni origine de téléchargement ni droit de redistribution.
- [SHA256SUMS.json](SHA256SUMS.json) : empreintes des quatre rapports de livraison.

Vérification : 596 tests Python, dont 590 réussis et six optionnels ignorés. Sur PESTO-W11-TEST / PowerShell 5.1, les 61 suites isolées passent. Le dernier renforcement contre la suppression d'une fonction ou d'un alias initial a ensuite été vérifié par ReadPool56 (24/24), Async (32/32) et Progress (21/21). Le banc manuel de jonction passe ses 39 cas après correction de son import ; AD, reçus et mutations y sont doublés. Les deux guides Word ont été rendus en PDF et toutes leurs pages contrôlées au fil des versions, puis les pages finales modifiées revues.

Aucune jonction, aucun renommage ni aucune mutation AD réelle n'a été exécuté pour ces vérifications. Le test WPF de 32 cycles et 256 sélections est une mesure isolée de 6,748 secondes, sans fenêtre suivie restante ; il ne clôture pas le point 107. Les qualifications 92, 95, 98, 99, 100, 101, 102, 103, 104 et 106 restent ouvertes. La signature de livraison (88) est retirée sur demande de David ; les approbations de campagne (117) et les contrôles d'intégrité sont conservés.
