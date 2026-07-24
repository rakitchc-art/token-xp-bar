' Lanceur silencieux de la barre de tokens.
' Double-clique dessus : ca ouvre TokenBar.ps1 en mode graphique (STA),
' SANS afficher de fenetre noire PowerShell.
Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & scriptDir & "\TokenBar.ps1"""
shell.Run cmd, 0, False
