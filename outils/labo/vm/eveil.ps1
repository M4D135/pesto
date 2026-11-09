# Garde l'écran et la session éveillés pendant une campagne (aucun réglage modifié) ; s'arrête seul après 4 h.
# Lancer avec lancer.ps1 -Dossier C:\PestoTest-run : un répertoire courant dans C:\PestoTest verrouillerait ce dossier.
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class Eveil{[DllImport("kernel32.dll")]public static extern uint SetThreadExecutionState(uint f);[DllImport("user32.dll")]public static extern void mouse_event(uint f,int x,int y,uint d,UIntPtr e);}'
[void][Eveil]::SetThreadExecutionState([uint32]2147483651)
[Eveil]::mouse_event(1, 1, 0, 0, [UIntPtr]::Zero); [Eveil]::mouse_event(1, -1, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Seconds 14400
