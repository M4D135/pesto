# Fixtures historiques non exécutées pour RC19

`test_pesto_brand.py` exigeait une identité de 405 fonctions avec RC17 après un simple renommage. RC19 modifie réellement le moteur.
`test_support_distribution_reprise.py` testait un générateur provisoire à manifeste minuscule en minuscules, remplacé par le générateur fermé commun.
Leurs tests sont conservés comme historique, pas comme preuve verte. La séparation, le support, les entrées hostiles et les fichiers altérés sont testés dans `test_distribution.py` et `test_rc19.py`.
