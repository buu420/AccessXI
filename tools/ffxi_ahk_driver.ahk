#NoEnv
#SingleInstance Force
#Persistent
SendMode Input
SetTitleMatchMode, 2
SetKeyDelay, 40, 80

cmdPath := "C:\Users\buu42\AccessXI\logs\ffxi-ahk-driver.cmd"
ackPath := "C:\Users\buu42\AccessXI\logs\ffxi-ahk-driver.ack"
heartbeatPath := "C:\Users\buu42\AccessXI\logs\ffxi-ahk-driver.heartbeat"
lastCommand := ""

SetTimer, AXHeartbeat, 1000
SetTimer, AXPollCommands, 150
return

AXHeartbeat:
    FormatTime, now,, yyyy-MM-ddTHH:mm:ss
    FileDelete, %heartbeatPath%
    FileAppend, %now%, %heartbeatPath%
return

AXPollCommands:
    if (!FileExist(cmdPath))
        return

    FileRead, content, %cmdPath%
    if (content = "" || content = lastCommand)
        return
    lastCommand := content

    id := ""
    commands := []
    Loop, Parse, content, `n, `r
    {
        line := Trim(A_LoopField)
        if (line = "")
            continue
        if (id = "")
            id := line
        else
            commands.Push(line)
    }
    if (id = "")
        return

    ok := AXFocusPol()
    for _, cmd in commands
    {
        if (cmd = "stop")
        {
            AXAck(id, "stopped", ok)
            ExitApp
        }
        AXRunCommand(cmd)
    }
    AXAck(id, "ok", ok)
return

AXFocusPol()
{
    WinActivate, ahk_exe pol.exe
    WinWaitActive, ahk_exe pol.exe,, 2
    if (ErrorLevel)
        return 0
    return 1
}

AXAck(id, status, ok)
{
    global ackPath
    FileDelete, %ackPath%
    FileAppend, %id% %status% focus=%ok%, %ackPath%
}

AXRunCommand(cmd)
{
    StringLower, lower, cmd
    if (RegExMatch(lower, "^sleep\s+(\d+)$", m))
    {
        Sleep, %m1%
        return
    }

    if (lower = "enter")
        SendInput, {Enter}
    else if (lower = "escape" || lower = "esc")
        SendInput, {Esc}
    else if (lower = "up")
        SendInput, {Up}
    else if (lower = "down")
        SendInput, {Down}
    else if (lower = "left")
        SendInput, {Left}
    else if (lower = "right")
        SendInput, {Right}
    else if (lower = "tab")
        SendInput, {Tab}
    else if (lower = "numpadsub" || lower = "numpadminus" || lower = "menu")
        SendInput, {NumpadSub}
    else if (lower = "numpadenter")
        SendInput, {NumpadEnter}
    else if (lower = "reloadaddon")
        SendInput, /addon reload accessxi_reader{Enter}
    Sleep, 250
}
