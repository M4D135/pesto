# Démo réelle : l'opération de renommage restée « incertaine » (défaut corrigé depuis : refus avant lancement noté 97) n'a
# jamais été lancée. Comme un administrateur, on termine l'action prévue (même nom, même OU), avec le compte de recette
# de la session (aucun mot de passe), puis Pesto vérifiera et consignera après redémarrage. Aucun reçu modifié.
$D = 'C:\PestoTest-preuves\demo-reelle\captures'
& {
  "session : $([Environment]::UserDomainName)\$([Environment]::UserName)"
  "avant : $env:COMPUTERNAME"
  Rename-Computer -NewName 'P111301VA765003' -Force -ErrorAction Stop
  'renommage demandé : P111301VA765003 (redémarrage nécessaire)'
} *> "$D\04-terminer-renommage.txt"
