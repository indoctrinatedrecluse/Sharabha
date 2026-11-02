Dim WshShell, cmd, i
Set WshShell = CreateObject("WScript.Shell")
cmd = ""
For i = 0 To WScript.Arguments.Count - 1
    If i > 0 Then cmd = cmd & " "
    If InStr(WScript.Arguments(i), " ") > 0 And Left(WScript.Arguments(i), 1) <> """" Then
        cmd = cmd & """" & WScript.Arguments(i) & """"
    Else
        cmd = cmd & WScript.Arguments(i)
    End If
Next
WshShell.Run cmd, 0, False
