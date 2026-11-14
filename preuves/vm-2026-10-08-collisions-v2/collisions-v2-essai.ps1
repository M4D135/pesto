# Essai court du banc v2 (validation du harnais) : 1 tour, 2 réglages, départ simultané.
& { try{ & C:\PestoTest-run\collisions-v2.ps1 -Rounds 1 -Profiles "Simultané" -OnlyModes "Sans protection;Registre (avant correctif);Registre;Tout (registre, hasard, AD)" -Out C:\PestoTest-preuves\collisions-v2-essai }catch{ 'ARRÊT : '+($_|Out-String) } } *> C:\PestoTest-preuves\collisions-v2-essai.log
