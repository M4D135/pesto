# Tests historiques et tests actuels

Pour RC19, lancer **TESTER.cmd**, puis `tools/Verify-Release.ps1` avec les modules développeur approuvés. Le second exige les rapports du premier.
Les Run-*, Regression-* et Test-Pesto18/17/16 conservés ici reflètent leurs anciens contrats : ils ne sont pas la preuve de validation de RC19. Leurs principes utiles sont repris dans Test-Pesto19.ps1 ; il ne faut pas remplacer silencieusement des tests en échec par un ancien rapport vert.
Tests portables actuels : `python -m unittest discover -s tests -p "test_*.py" -v`, `python tools/checks/validate_pesto.py` et `python tools/checks/run_native_portable.py`. Les tests Windows n'ont pas été exécutés dans l'environnement de préparation Linux.
