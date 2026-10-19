Set WshShell = CreateObject("WScript.Shell")
Dim args, psCmd, i
psCmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File"
For i = 0 To WScript.Arguments.Count - 1
    psCmd = psCmd & " """ & WScript.Arguments(i) & """"
Next
WshShell.Run psCmd, 0, False