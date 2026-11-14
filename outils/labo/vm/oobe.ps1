Import-Module C:\PestoTest-run\pilote.psm1
& { $w = Wait-Fenetre "Microsoft account" 5; if ($w) { Get-Arbre $w 8 } else { "absente" } } *> C:\PestoTest-preuves\phase2\oobe.txt
