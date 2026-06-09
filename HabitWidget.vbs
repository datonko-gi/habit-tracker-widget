Set WshShell = CreateObject("WScript.Shell")
scriptDir = WshShell.CurrentDirectory
Set fso = CreateObject("Scripting.FileSystemObject")
selfPath = fso.GetParentFolderName(WScript.ScriptFullName)
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & selfPath & "\habit_widget.ps1""", 0, False
