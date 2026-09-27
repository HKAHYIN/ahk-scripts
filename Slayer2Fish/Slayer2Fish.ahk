#Requires AutoHotkey v2.0
#SingleInstance Force

; F6: start/stop. F8 or window X: release inputs and exit. Esc: cancel selection.
; Recovery loops indefinitely; Max cycles = 0 means unlimited.
; T delay: 0-5 seconds. Hold T: 2-15 seconds (default 4).

CoordMode("Mouse", "Screen")
lastPathFile := A_ScriptDir "\Slayer2Fish-last-profile.ini"
defaultPath := A_ScriptDir "\Slayer2Fish.ini"
profilePath := IniRead(lastPathFile, "Profile", "Path", defaultPath)
if !FileExist(profilePath)
    profilePath := defaultPath
cfg := LoadProfile(profilePath)
cap := ""
fields := Map()
running := false
busy := false
mouseHeld := false
tHeld := false
pulseActive := false
lastPulseAt := 0
state := "IDLE"
stateAt := 0
focusAt := 0
barAt := 0
lastGoodAt := 0
lastTargetY := ""
lastDotY := ""
prevError := ""
prevErrorAt := 0
errorSpeed := 0.0
holdAt := 0
validCount := 0
missingCount := 0
castCount := 0
recoveryCount := 0
lastUiAt := 0
collectionReason := ""
detectDiag := "No detection yet"
pickOverlay := ""
pickBox := ""
pickMode := ""
pickDragging := false
pickX := 0
pickY := 0

appGui := Gui("+Resize +MinSize560x350 +AlwaysOnTop +ToolWindow", "Slayer 2 Fishing Controller")
appGui.SetFont("s9", "Segoe UI")
tabs := appGui.Add("Tab3", "x10 y10 w540 h330", ["Main", "Customize"])

tabs.UseTab(1)
statusText := appGui.Add("Text", "x25 y55 w510 h110 +Wrap", "Idle")
waitLabel := appGui.Add("Text", "x25 y195 w108", "Wait for bar (s)")
fields["castWaitSec"] := appGui.Add("Edit", "x135 y193 w45 h24", cfg["castWaitSec"])
delayLabel := appGui.Add("Text", "x192 y195 w82", "T delay (s)")
fields["collectDelaySec"] := appGui.Add("Edit", "x275 y193 w45 h24", cfg["collectDelaySec"])
holdLabel := appGui.Add("Text", "x337 y195 w95", "Hold T (s)")
fields["collectHoldSec"] := appGui.Add("Edit", "x435 y193 w45 h24", cfg["collectHoldSec"])
cooldownLabel := appGui.Add("Text", "x25 y230 w108", "Cooldown (s)")
fields["cooldownSec"] := appGui.Add("Edit", "x135 y228 w45 h24", cfg["cooldownSec"])
cyclesLabel := appGui.Add("Text", "x192 y230 w82", "Max cycles (0=all)")
fields["maxCycles"] := appGui.Add("Edit", "x275 y228 w105 h24", cfg["maxCycles"])
startStopBtn := appGui.Add("Button", "x25 y280 w155 h34", "Start/Stop (F6)")
exitBtn := appGui.Add("Button", "x190 y280 w110 h34", "Exit (F8)")
startStopBtn.OnEvent("Click", ToggleRun)
exitBtn.OnEvent("Click", ExitRun)

tabs.UseTab(2)
appGui.Add("Text", "x25 y50 w500", "Bar area: include its frame and moving target outline")
AddField("barLeft", "X", 25, 77)
AddField("barTop", "Y", 151, 77)
AddField("barWidth", "Width", 277, 77)
AddField("barHeight", "Height", 403, 77)
barPickBtn := appGui.Add("Button", "x25 y111 w180 h28", "Select bar area")
barPickBtn.OnEvent("Click", PickBar)

appGui.Add("Text", "x25 y152 w500", "Cast point: click once here to begin each cycle")
AddField("castX", "X", 25, 180)
AddField("castY", "Y", 151, 180)
castPickBtn := appGui.Add("Button", "x277 y178 w180 h28", "Select cast point")
castPickBtn.OnEvent("Click", PickCast)

appGui.Add("Text", "x25 y222 w500", "Bar control")
AddField("scanInterval", "Scan ms", 25, 249)
AddField("holdThreshold", "Hold px", 151, 249)
AddField("releaseThreshold", "Release px", 277, 249)
AddField("predictionMs", "Predict ms", 403, 249)
AddField("missingGraceMs", "Grace ms", 25, 288)
appGui.Add("Text", "x151 y289 w96 h23", "Max hold (ms)")
fields["maxHoldMs"] := appGui.Add("Edit", "x249 y286 w54 h24", cfg["maxHoldMs"])
enabledCheck := appGui.Add("CheckBox", "x305 y289 w195 h24", "Enable M1 control")
enabledCheck.Value := cfg["controlEnabled"]
AddField("pulseMs", "Pulse ms", 25, 329)
AddField("pulsePeriodMs", "Period ms", 151, 329)

windowSectionText := appGui.Add("Text", "x25 y363 w500 h23", "Window options")
topmostCheck := appGui.Add("CheckBox", "x25 y390 w195 h25", "Always on top")
topmostCheck.Value := cfg["alwaysOnTop"]
topmostCheck.OnEvent("Click", TopmostChanged)

infoText := appGui.Add("Text", "x25 y420 w500 h38 +Wrap", "T delay: 0-5 s after recovery. Hold T: 2-15 s. The default hold is 4 s.")
saveBtn := appGui.Add("Button", "x25 y463 w125 h30", "Save As...")
openBtn := appGui.Add("Button", "x160 y463 w125 h30", "Open INI...")
saveBtn.OnEvent("Click", SaveProfile)
openBtn.OnEvent("Click", OpenProfile)
fileText := appGui.Add("Text", "x25 y504 w500 h40 +Wrap", "Profile: " profilePath)

tabs.UseTab()
tabs.OnEvent("Change", TabChanged)
appGui.OnEvent("Size", GuiResized)
appGui.OnEvent("Close", CloseRun)
OnMessage(0x201, PickerDown)
OnExit(Cleanup)

try {
    cap := MakeCapture(cfg["barLeft"], cfg["barTop"], cfg["barWidth"], cfg["barHeight"])
} catch as err {
    MsgBox("Capture initialization failed:`n" FormatError(err))
    ExitApp()
}

appGui.Show("x20 y100 w560 h350 NoActivate")
WinSetAlwaysOnTop(cfg["alwaysOnTop"], "ahk_id " appGui.Hwnd)
ShowStatus("Idle.", true)

F6::ToggleRun()
F8::ExitApp()
Esc::{
    global pickOverlay
    if IsObject(pickOverlay)
        EndPicker("Selection cancelled.")
}

DefaultConfig() {
    return Map("barLeft", 1407, "barTop", 305, "barWidth", 67, "barHeight", 395,
        "castX", 1200, "castY", 450, "scanInterval", 70,
        "holdThreshold", 8, "releaseThreshold", -2, "predictionMs", 60,
        "missingGraceMs", 120, "maxHoldMs", 3000, "pulseMs", 50,
        "pulsePeriodMs", 110, "controlEnabled", 1, "alwaysOnTop", 1,
        "castWaitSec", 15, "collectDelaySec", 0, "collectHoldSec", 4,
        "cooldownSec", 0, "maxCycles", 0)
}

LoadProfile(path) {
    result := DefaultConfig()
    if FileExist(path) {
        for key, defaultValue in result {
            raw := IniRead(path, "Settings", key, defaultValue)
            if RegExMatch(raw, "^-?\d+$") {
                if (key = "maxCycles")
                    result[key] := Max(0, Min(99999, raw + 0))
                else
                    result[key] := raw + 0
            }
        }
    }
    result["collectDelaySec"] := Max(0, Min(5, result["collectDelaySec"]))
    result["collectHoldSec"] := Max(2, Min(15, result["collectHoldSec"]))
    return result
}

FormatError(err) {
    details := err.Message
    details .= "`nSpecifically: " err.Extra
    details .= "`nFunction: " err.What
    details .= "`nLine: " err.Line
    details .= "`nFile: " err.File
    return details
}

AddField(key, label, x, y) {
    global appGui, fields, cfg
    appGui.Add("Text", "x" x " y" y " w63 h23", label)
    fields[key] := appGui.Add("Edit", "x" (x + 65) " y" (y - 2) " w54 h24", cfg[key])
}

FillFields(values) {
    global fields, enabledCheck, topmostCheck
    for key, editCtrl in fields
        editCtrl.Value := values[key]
    enabledCheck.Value := values["controlEnabled"]
    topmostCheck.Value := values["alwaysOnTop"]
}

NumberField(key, low, high) {
    global fields
    raw := Trim(fields[key].Value)
    if !RegExMatch(raw, "^-?\d+$")
        throw Error(key " must be an integer.")
    value := raw + 0
    if (value < low || value > high)
        throw Error(key " must be between " low " and " high ".")
    return value
}

ApplyFields() {
    global cfg, cap, enabledCheck, topmostCheck, running, appGui
    try {
        next := Map()
        next["barLeft"] := NumberField("barLeft", 0, A_ScreenWidth - 1)
        next["barTop"] := NumberField("barTop", 0, A_ScreenHeight - 1)
        next["barWidth"] := NumberField("barWidth", 35, 140)
        next["barHeight"] := NumberField("barHeight", 250, 650)
        next["castX"] := NumberField("castX", 0, A_ScreenWidth - 1)
        next["castY"] := NumberField("castY", 0, A_ScreenHeight - 1)
        next["scanInterval"] := NumberField("scanInterval", 30, 500)
        next["holdThreshold"] := NumberField("holdThreshold", 0, 50)
        next["releaseThreshold"] := NumberField("releaseThreshold", -30, 30)
        next["predictionMs"] := NumberField("predictionMs", 0, 250)
        next["missingGraceMs"] := NumberField("missingGraceMs", 0, 500)
        next["maxHoldMs"] := NumberField("maxHoldMs", 250, 10000)
        next["pulseMs"] := NumberField("pulseMs", 20, 150)
        next["pulsePeriodMs"] := NumberField("pulsePeriodMs", 50, 500)
        next["castWaitSec"] := NumberField("castWaitSec", 2, 60)
        next["collectDelaySec"] := NumberField("collectDelaySec", 0, 5)
        next["collectHoldSec"] := NumberField("collectHoldSec", 2, 15)
        next["cooldownSec"] := NumberField("cooldownSec", 0, 30)
        next["maxCycles"] := NumberField("maxCycles", 0, 99999)
        next["controlEnabled"] := enabledCheck.Value ? 1 : 0
        next["alwaysOnTop"] := topmostCheck.Value ? 1 : 0

        if (next["barLeft"] + next["barWidth"] > A_ScreenWidth || next["barTop"] + next["barHeight"] > A_ScreenHeight)
            throw Error("The bar area extends beyond the primary screen.")
        if (next["releaseThreshold"] >= next["holdThreshold"])
            throw Error("Release threshold must be below hold threshold.")
        if (next["pulsePeriodMs"] <= next["pulseMs"])
            throw Error("Pulse period must be longer than pulse-on time.")

        if running
            StopRun()
        replacement := MakeCapture(next["barLeft"], next["barTop"], next["barWidth"], next["barHeight"])
        if IsObject(cap)
            FreeCapture(cap)
        cap := replacement
        cfg := next
        WinSetAlwaysOnTop(cfg["alwaysOnTop"], "ahk_id " appGui.Hwnd)
        ShowStatus("Settings applied.", true)
        return true
    } catch as err {
        ShowStatus("Settings error:`n" FormatError(err), true)
        return false
    }
}

TopmostChanged(guiControl, info) {
    global cfg, profilePath, appGui
    setting := guiControl.Value ? 1 : 0
    cfg["alwaysOnTop"] := setting
    WinSetAlwaysOnTop(setting, "ahk_id " appGui.Hwnd)
    try {
        IniWrite(setting, profilePath, "Settings", "alwaysOnTop")
        ShowStatus("Always on top " (setting ? "enabled" : "disabled") ". Setting saved.", true)
    } catch as err {
        ShowStatus("Always on top changed but not saved:`n" FormatError(err), true)
    }
}

RememberProfile(path) {
    global lastPathFile
    IniWrite(path, lastPathFile, "Profile", "Path")
}

SaveProfile(guiControl := "", info := "") {
    global appGui, cfg, profilePath, fileText
    if !ApplyFields() {
        appGui.Opt("+OwnDialogs")
        MsgBox("Settings were not saved. Check the error on the Main tab.", "Save failed")
        return
    }
    try {
        appGui.Opt("+OwnDialogs")
        path := FileSelect("S16", profilePath, "Save INI profile", "INI files (*.ini)")
        if (path = "") {
            ShowStatus("Save cancelled. Changes are applied in memory only.", true)
            return
        }
        if !RegExMatch(path, "i)\.ini$")
            path .= ".ini"
        for key, value in cfg
            IniWrite(value, path, "Settings", key)
        profilePath := path
        fileText.Text := "Profile: " path
        try RememberProfile(path)
        catch as pathError {
            ShowStatus("Profile saved, but last-used path could not be remembered:`n" FormatError(pathError), true)
            return
        }
        ShowStatus("Profile saved: " path, true)
    } catch as err {
        ShowStatus("Save failed:`n" FormatError(err), true)
        appGui.Opt("+OwnDialogs")
        MsgBox(FormatError(err), "Save failed")
    }
}

OpenProfile(guiControl := "", info := "") {
    global appGui, profilePath, fileText
    try {
        appGui.Opt("+OwnDialogs")
        path := FileSelect(1, profilePath, "Open INI profile", "INI files (*.ini)")
        if (path = "")
            return
        FillFields(LoadProfile(path))
        if ApplyFields() {
            profilePath := path
            fileText.Text := "Profile: " path
            RememberProfile(path)
            ShowStatus("Profile opened and applied: " path, true)
        }
    } catch as err {
        ShowStatus("Open failed:`n" FormatError(err), true)
        appGui.Opt("+OwnDialogs")
        MsgBox(FormatError(err), "Open failed")
    }
}

TabChanged(guiControl, info) {
    global tabs, appGui
    if (tabs.Value = 2)
        appGui.Show("w560 h570")
    else
        appGui.Show("w560 h350")
}

GuiResized(guiObject, minMax, width, height) {
    global tabs, statusText, startStopBtn, exitBtn, saveBtn, openBtn, fileText
    global waitLabel, delayLabel, holdLabel, cooldownLabel, cyclesLabel, fields
    global infoText, windowSectionText, topmostCheck
    if (minMax = -1)
        return
    if (tabs.Value = 2 && height < 570) {
        guiObject.Show("h570")
        return
    }
    tabs.Move(10, 10, Max(540, width - 20), Max(330, height - 20))
    if (tabs.Value = 1) {
        row1 := height - 160
        row2 := height - 125
        statusText.Move(25, 55, Max(500, width - 50), Max(100, row1 - 90))
        waitLabel.Move(25, row1 + 2)
        fields["castWaitSec"].Move(135, row1)
        delayLabel.Move(192, row1 + 2)
        fields["collectDelaySec"].Move(275, row1)
        holdLabel.Move(337, row1 + 2)
        fields["collectHoldSec"].Move(435, row1)
        cooldownLabel.Move(25, row2 + 2)
        fields["cooldownSec"].Move(135, row2)
        cyclesLabel.Move(192, row2 + 2)
        fields["maxCycles"].Move(275, row2)
        startStopBtn.Move(25, height - 70)
        exitBtn.Move(190, height - 70)
    } else {
        windowSectionText.Move(25, height - 207)
        topmostCheck.Move(25, height - 180)
        infoText.Move(25, height - 150, Max(500, width - 50), 38)
        saveBtn.Move(25, height - 107)
        openBtn.Move(160, height - 107)
        fileText.Move(25, height - 66, Max(500, width - 50), 40)
    }
}

CloseRun(guiObject) {
    ExitApp()
}

ToggleRun(guiControl := "", info := "") {
    global running
    if running
        StopRun()
    else
        StartRun()
}

StartRun(guiControl := "", info := "") {
    global running, state, stateAt, focusAt, castCount, barAt, validCount
    global missingCount, lastTargetY, lastDotY, lastGoodAt, prevError
    global prevErrorAt, errorSpeed, startStopBtn, cfg, collectionReason
    global pulseActive, lastPulseAt, recoveryCount, detectDiag
    if running || !ApplyFields()
        return
    ReleaseInputs()
    running := true
    state := "WAIT_FOCUS"
    stateAt := A_TickCount
    focusAt := stateAt
    castCount := 0
    recoveryCount := 0
    barAt := 0
    validCount := 0
    missingCount := 0
    lastTargetY := ""
    lastDotY := ""
    lastGoodAt := 0
    prevError := ""
    prevErrorAt := 0
    errorSpeed := 0.0
    pulseActive := false
    lastPulseAt := 0
    collectionReason := ""
    detectDiag := "No detection yet"
    startStopBtn.Text := "Stop (F6)"
    ShowStatus("Started. Activate Roblox within 10 seconds. T delay " cfg["collectDelaySec"] "s; T hold " cfg["collectHoldSec"] "s.", true)
    SetTimer(Tick, cfg["scanInterval"])
}

StopRun(guiControl := "", info := "") {
    global running, state, startStopBtn
    running := false
    state := "IDLE"
    SetTimer(Tick, 0)
    ReleaseInputs()
    startStopBtn.Text := "Start/Stop (F6)"
    ShowStatus("Stopped. M1 and T released.", true)
}

StopReason(message) {
    global running, state, startStopBtn
    running := false
    state := "IDLE"
    SetTimer(Tick, 0)
    ReleaseInputs()
    startStopBtn.Text := "Start/Stop (F6)"
    ShowStatus(message, true)
}

BeginFallback(reason, now) {
    global state, stateAt, collectionReason, recoveryCount, cfg
    CancelPulse()
    ReleaseMouse()
    recoveryCount += 1
    collectionReason := reason
    state := "WAIT_T_DELAY"
    stateAt := now
    ShowStatus("Recovery " recoveryCount ": " reason "`nWaiting " cfg["collectDelaySec"] "s, then holding T for " cfg["collectHoldSec"] "s.", true)
}

ExitRun(guiControl := "", info := "") {
    ExitApp()
}

ShowStatus(message, force := false) {
    global statusText, lastUiAt
    if (!force && A_TickCount - lastUiAt < 150)
        return
    statusText.Text := message
    lastUiAt := A_TickCount
}

PickBar(guiControl := "", info := "") {
    BeginPicker("bar")
}

PickCast(guiControl := "", info := "") {
    BeginPicker("cast")
}

BeginPicker(mode) {
    global pickOverlay, pickBox, pickMode, pickDragging
    if IsObject(pickOverlay)
        EndPicker("Previous selection cancelled.")
    StopRun()
    pickMode := mode
    pickDragging := false
    ShowStatus("Select " mode " on screen. Esc cancels.", true)
    pickOverlay := Gui("-Caption +AlwaysOnTop +ToolWindow", "Screen selection")
    pickOverlay.BackColor := "000000"
    pickOverlay.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    WinSetTransparent(65, "ahk_id " pickOverlay.Hwnd)
    pickBox := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20", "Selection preview")
    pickBox.BackColor := "00FF00"
}

PickerDown(wParam, lParam, message, hwnd) {
    global pickOverlay, pickMode, pickDragging, pickX, pickY, fields
    if !IsObject(pickOverlay) || hwnd != pickOverlay.Hwnd
        return
    MouseGetPos(&x, &y)
    if (pickMode = "cast") {
        fields["castX"].Value := x
        fields["castY"].Value := y
        EndPicker("Cast point selected. Save or Start to apply.")
        return
    }
    pickX := x
    pickY := y
    pickDragging := true
    SetTimer(PickerPoll, 25)
}

PickerPoll() {
    global pickDragging, pickX, pickY, pickBox, fields
    if !pickDragging
        return
    MouseGetPos(&x, &y)
    left := Min(x, pickX)
    top := Min(y, pickY)
    width := Max(1, Abs(x - pickX) + 1)
    height := Max(1, Abs(y - pickY) + 1)
    if GetKeyState("LButton") {
        pickBox.Show("x" left " y" top " w" width " h" height " NoActivate")
        WinSetTransparent(90, "ahk_id " pickBox.Hwnd)
        return
    }
    SetTimer(PickerPoll, 0)
    pickDragging := false
    if (width < 10 || height < 10) {
        EndPicker("Selection too small. Drag around the entire bar.")
        return
    }
    fields["barLeft"].Value := left
    fields["barTop"].Value := top
    fields["barWidth"].Value := width
    fields["barHeight"].Value := height
    EndPicker("Bar area selected. Save or Start to apply.")
}

EndPicker(message) {
    global pickOverlay, pickBox, pickDragging, pickMode
    SetTimer(PickerPoll, 0)
    pickDragging := false
    if IsObject(pickBox)
        pickBox.Destroy()
    if IsObject(pickOverlay)
        pickOverlay.Destroy()
    pickBox := ""
    pickOverlay := ""
    pickMode := ""
    ShowStatus(message, true)
}

Tick() {
    global cap, cfg, running, busy, state, stateAt, focusAt
    global castCount, barAt, validCount, missingCount, lastTargetY, lastDotY
    global lastGoodAt, prevError, prevErrorAt, errorSpeed, mouseHeld, holdAt
    global collectionReason, pulseActive, lastPulseAt, detectDiag
    if (!running || busy)
        return
    busy := true
    try {
        now := A_TickCount
        if !WinActive("Roblox") {
            ReleaseInputs()
            if (state = "WAIT_FOCUS" && now - focusAt < 10000) {
                ShowStatus("Activate Roblox within 10 seconds.")
                return
            }
            StopReason("Roblox lost focus. Inputs released for safety.")
            return
        }
        if (state = "WAIT_FOCUS" || state = "CAST") {
            ReleaseInputs()
            if (cfg["maxCycles"] > 0 && castCount >= cfg["maxCycles"]) {
                StopReason("Maximum cast cycles reached.")
                return
            }
            Click(cfg["castX"] " " cfg["castY"])
            castCount += 1
            state := "WAIT_BAR"
            stateAt := A_TickCount
            validCount := 0
            missingCount := 0
            lastTargetY := ""
            lastDotY := ""
            lastGoodAt := 0
            prevError := ""
            prevErrorAt := 0
            errorSpeed := 0.0
            ShowStatus("Cast " castCount ". Waiting up to " cfg["castWaitSec"] " seconds for the bar.", true)
            return
        }
        if (state = "WAIT_T_DELAY") {
            if (now - stateAt >= cfg["collectDelaySec"] * 1000) {
                ReleaseMouse()
                HoldT()
                state := "COLLECT"
                stateAt := A_TickCount
                ShowStatus(collectionReason "`nT DOWN. Holding " cfg["collectHoldSec"] " seconds.", true)
            }
            return
        }
        if (state = "COLLECT") {
            remaining := Max(0, cfg["collectHoldSec"] * 1000 - (now - stateAt))
            if (remaining <= 0) {
                ReleaseT()
                stateAt := now
                if (cfg["cooldownSec"] = 0) {
                    if (cfg["maxCycles"] > 0 && castCount >= cfg["maxCycles"])
                        StopReason("Maximum cast cycles reached.")
                    else {
                        state := "CAST"
                        ShowStatus("T UP after " cfg["collectHoldSec"] "s. Recasting on next tick.", true)
                    }
                } else {
                    state := "COOLDOWN"
                    ShowStatus("T UP after " cfg["collectHoldSec"] "s. Cooldown " cfg["cooldownSec"] "s.", true)
                }
            } else {
                ShowStatus("T is DOWN | " Round(remaining / 1000, 1) " seconds left.")
            }
            return
        }
        if (state = "COOLDOWN") {
            if (now - stateAt >= cfg["cooldownSec"] * 1000) {
                if (cfg["maxCycles"] > 0 && castCount >= cfg["maxCycles"])
                    StopReason("Maximum cast cycles reached.")
                else
                    state := "CAST"
            }
            return
        }
        if !GrabFrame(cap) {
            StopReason("Screen capture failed. Inputs released for safety.")
            return
        }
        result := DetectBar(cap, cfg)
        barFramePresent := FrameVisible(cap, cfg)
        now := A_TickCount
        if (state = "WAIT_BAR") {
            if (result != "") {
                validCount += 1
                if (validCount >= 2) {
                    state := "CONTROL"
                    stateAt := now
                    barAt := now
                    lastGoodAt := now
                    lastTargetY := result.targetY
                    lastDotY := result.dotY
                    validCount := 0
                    missingCount := 0
                    ShowStatus("Fishing bar confirmed. Tracking marker.", true)
                }
                return
            }
            validCount := 0
            if (now - stateAt >= cfg["castWaitSec"] * 1000)
                BeginFallback("No bar detected within " cfg["castWaitSec"] "s. " detectDiag, now)
            return
        }
        if (state != "CONTROL")
            return
        if (now - barAt > 45000) {
            BeginFallback("Bar control timed out after 45s. " detectDiag, now)
            return
        }
        if (result = "") {
            missingCount += 1
            keepHolding := mouseHeld && barFramePresent && lastDotY != "" && lastTargetY != "" && lastDotY > lastTargetY + cfg["holdThreshold"] && now - lastGoodAt < cfg["missingGraceMs"] && now - holdAt < cfg["maxHoldMs"]
            if !keepHolding {
                CancelPulse()
                ReleaseMouse()
            }
            ; After tracking has started, recover after 2 seconds without the bar/marker.
            if (now - lastGoodAt >= 2000) {
                BeginFallback("Bar/marker not detected for 2s. " detectDiag, now)
                return
            }
            if (missingCount >= 8) {
                lastTargetY := ""
                lastDotY := ""
            }
            if (missingCount >= 3) {
                prevError := ""
                prevErrorAt := 0
                errorSpeed := 0.0
            }
            ShowStatus("Tracking lost | Shadow: " (barFramePresent ? "dark" : "faded/absent") " | Missing: " missingCount "`n" detectDiag "`nM1: " (keepHolding ? "brief hold" : "released"))
            return
        }
        targetJump := lastTargetY != "" && Abs(result.targetY - lastTargetY) > 110
        dotJump := lastDotY != "" && Abs(result.dotY - lastDotY) > 110
        if (targetJump || dotJump) {
            CancelPulse()
            ReleaseMouse()
            missingCount += 1
            if (missingCount >= 8) {
                BeginFallback("Repeated unreliable positions. " detectDiag, now)
                return
            }
            ShowStatus("Unreliable position jump. M1 released.`n" detectDiag)
            return
        }
        lastTargetY := result.targetY
        lastDotY := result.dotY
        lastGoodAt := now
        missingCount := 0
        error := result.dotY - result.targetY
        if (prevErrorAt > 0) {
            dt := now - prevErrorAt
            if (dt > 0 && dt < 250) {
                rawSpeed := Max(-0.8, Min(0.8, (error - prevError) / dt))
                errorSpeed := 0.6 * errorSpeed + 0.4 * rawSpeed
            } else {
                errorSpeed := 0.0
            }
        }
        prevError := error
        prevErrorAt := now
        predictedError := error + errorSpeed * cfg["predictionMs"]
        if !cfg["controlEnabled"] {
            CancelPulse()
            ReleaseMouse()
        } else {
            if (mouseHeld && now - holdAt >= cfg["maxHoldMs"]) {
                BeginFallback("Maximum continuous M1 hold reached.", now)
                return
            }
            if (result.dotY > result.targetBottom + 8 && predictedError > cfg["holdThreshold"]) {
                CancelPulse()
                HoldMouse()
            } else if (result.dotY < result.targetTop + 8 || predictedError < -6) {
                CancelPulse()
                ReleaseMouse()
            } else if (predictedError >= 4 && errorSpeed > -0.15) {
                if (!pulseActive && now - lastPulseAt >= cfg["pulsePeriodMs"]) {
                    if mouseHeld
                        ReleaseMouse()
                    HoldMouse()
                    pulseActive := true
                    lastPulseAt := now
                    SetTimer(EndPulse, -cfg["pulseMs"])
                }
            } else {
                CancelPulse()
                ReleaseMouse()
            }
        }
        mode := pulseActive ? "PULSE" : (mouseHeld ? "HELD" : "RELEASED")
        ShowStatus("Fishing bar | Cast " castCount "`nTarget Y: " result.targetY " | Marker Y: " result.dotY "`nPredicted error: " Round(predictedError, 1) " px | M1: " mode)
    } catch as err {
        details := FormatError(err)
        StopReason("Script error. Inputs released. See error dialog.")
        MsgBox(details, "Slayer2Fish script error")
    } finally {
        busy := false
    }
}

; Used only for a short M1 grace period and diagnostics, not completion.
FrameVisible(cap, cfg) {
    x := cfg["barLeft"] + Round((cfg["barWidth"] - 1) * 0.5)
    dark := 0
    for offset in [45, 90, 135] {
        if (offset >= cfg["barHeight"] - 5)
            continue
        rgb := ReadPixel(cap, x, cfg["barTop"] + offset)
        r := (rgb >> 16) & 255
        g := (rgb >> 8) & 255
        b := rgb & 255
        if (r < 85 && g < 115 && b < 165)
            dark += 1
    }
    return dark >= 2
}

; Candidate colours are compared within the current frame. The rectangle is
; sampled across more of its sides; the marker is compared with nearby pixels
; on the same row rather than only against a fixed brightness threshold.
DetectBar(cap, cfg) {
    global detectDiag
    targetRun := NewRun()
    dotRun := NewRun()
    baseX := cfg["barLeft"]
    width := cfg["barWidth"]
    y := cfg["barTop"] + 4
    bottom := cfg["barTop"] + cfg["barHeight"] - 5
    targetOffsets := [3, 5, 9, 12, 16, 20, 46, 50, 54, 59, 62]
    dotOffsets := [29, 33, 37]
    bgLeftOffset := 15
    bgRightOffset := 51
    while (y <= bottom) {
        targetVotes := 0
        dotVotes := 0
        bgLeftX := baseX + Round(bgLeftOffset * (width - 1) / 66)
        bgRightX := baseX + Round(bgRightOffset * (width - 1) / 66)
        bgLight := (PixelLight(ReadPixel(cap, bgLeftX, y)) + PixelLight(ReadPixel(cap, bgRightX, y))) / 2
        for offset in targetOffsets {
            x := baseX + Round(offset * (width - 1) / 66)
            rgb := ReadPixel(cap, x, y)
            if IsTargetPixel(rgb)
                targetVotes += 1
        }
        for offset in dotOffsets {
            x := baseX + Round(offset * (width - 1) / 66)
            rgb := ReadPixel(cap, x, y)
            if IsMarkerPixel(rgb, bgLight)
                dotVotes += 1
        }
        FeedRun(targetRun, targetVotes >= 2, y)
        FeedRun(dotRun, dotVotes >= 2, y)
        y += 2
    }
    targetHeight := targetRun.bestEnd - targetRun.bestStart + 1
    dotHeight := dotRun.bestEnd - dotRun.bestStart + 1
    detectDiag := "Target=" targetRun.bestCount "/" targetHeight "px | Marker=" dotRun.bestCount "/" dotHeight "px"
    if (targetRun.bestCount < 5 || dotRun.bestCount < 3 || targetHeight > 80 || dotHeight > 40)
        return ""
    targetY := Round((targetRun.bestStart + targetRun.bestEnd) / 2)
    dotY := Round((dotRun.bestStart + dotRun.bestEnd) / 2)
    return {targetY: targetY, targetTop: targetRun.bestStart, targetBottom: targetRun.bestEnd, dotY: dotY}
}

IsTargetPixel(rgb) {
    r := (rgb >> 16) & 255
    g := (rgb >> 8) & 255
    b := rgb & 255
    total := r + g + b
    if (total < 45)
        return false
    colorScore := 200 * (2 * g - r - b) / (total + 30)
    return g >= r + 4 && g >= b + 4 && colorScore >= 22
}

IsMarkerPixel(rgb, bgLight) {
    r := (rgb >> 16) & 255
    g := (rgb >> 8) & 255
    b := rgb & 255
    brightEnough := PixelLight(rgb) - bgLight >= 35
    roughlyPale := Min(r, g, b) >= 50 && Max(r, g, b) - Min(r, g, b) <= 95
    return brightEnough && roughlyPale
}

PixelLight(rgb) {
    r := (rgb >> 16) & 255
    g := (rgb >> 8) & 255
    b := rgb & 255
    return (r + 2 * g + b) / 4
}

NewRun() {
    return {count: 0, start: 0, bestCount: 0, bestStart: 0, bestEnd: 0}
}

FeedRun(run, matched, y) {
    if matched {
        if (run.count = 0)
            run.start := y
        run.count += 1
        if (run.count > run.bestCount) {
            run.bestCount := run.count
            run.bestStart := run.start
            run.bestEnd := y
        }
    } else {
        run.count := 0
    }
}

ReadPixel(cap, x, y) {
    offset := ((y - cap.top) * cap.width + (x - cap.left)) * 4
    return NumGet(cap.bits, offset, "UInt")
}

MakeCapture(left, top, width, height) {
    result := {left: left, top: top, width: width, height: height, screenDC: 0, memoryDC: 0, bitmap: 0, oldBitmap: 0, bits: 0}
    try {
        info := Buffer(40, 0)
        NumPut("UInt", 40, "Int", width, "Int", -height, "UShort", 1, "UShort", 32, info)
        result.screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
        if !result.screenDC
            throw Error("GetDC failed")
        result.memoryDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", result.screenDC, "Ptr")
        if !result.memoryDC
            throw Error("CreateCompatibleDC failed")
        ptr := 0
        result.bitmap := DllCall("gdi32\CreateDIBSection", "Ptr", result.screenDC, "Ptr", info, "UInt", 0, "Ptr*", &ptr, "Ptr", 0, "UInt", 0, "Ptr")
        if (!result.bitmap || !ptr)
            throw Error("CreateDIBSection failed")
        result.bits := ptr
        result.oldBitmap := DllCall("gdi32\SelectObject", "Ptr", result.memoryDC, "Ptr", result.bitmap, "Ptr")
        if !result.oldBitmap
            throw Error("SelectObject failed")
        return result
    } catch as err {
        FreeCapture(result)
        throw err
    }
}

GrabFrame(cap) {
    copied := DllCall("gdi32\BitBlt", "Ptr", cap.memoryDC, "Int", 0, "Int", 0, "Int", cap.width, "Int", cap.height, "Ptr", cap.screenDC, "Int", cap.left, "Int", cap.top, "UInt", 0x00CC0020, "Int")
    if copied
        DllCall("gdi32\GdiFlush")
    return copied
}

FreeCapture(cap) {
    if (cap.oldBitmap && cap.memoryDC) {
        DllCall("gdi32\SelectObject", "Ptr", cap.memoryDC, "Ptr", cap.oldBitmap, "Ptr")
        cap.oldBitmap := 0
    }
    if cap.bitmap {
        DllCall("gdi32\DeleteObject", "Ptr", cap.bitmap)
        cap.bitmap := 0
        cap.bits := 0
    }
    if cap.memoryDC {
        DllCall("gdi32\DeleteDC", "Ptr", cap.memoryDC)
        cap.memoryDC := 0
    }
    if cap.screenDC {
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", cap.screenDC)
        cap.screenDC := 0
    }
}

HoldMouse() {
    global mouseHeld, holdAt
    if !mouseHeld {
        SendEvent("{LButton down}")
        mouseHeld := true
        holdAt := A_TickCount
    }
}

ReleaseMouse() {
    global mouseHeld, holdAt
    if mouseHeld {
        SendEvent("{LButton up}")
        mouseHeld := false
    }
    holdAt := 0
}

EndPulse() {
    global pulseActive
    pulseActive := false
    ReleaseMouse()
}

CancelPulse() {
    global pulseActive
    SetTimer(EndPulse, 0)
    pulseActive := false
}

HoldT() {
    global tHeld
    if !tHeld {
        SendEvent("{t down}")
        tHeld := true
    }
}

ReleaseT() {
    global tHeld
    if tHeld {
        SendEvent("{t up}")
        tHeld := false
    }
}

ReleaseInputs() {
    CancelPulse()
    ReleaseMouse()
    ReleaseT()
}

Cleanup(exitReason, exitCode) {
    global cap, pickOverlay, pickBox
    SetTimer(Tick, 0)
    SetTimer(PickerPoll, 0)
    ReleaseInputs()
    if IsObject(pickBox)
        pickBox.Destroy()
    if IsObject(pickOverlay)
        pickOverlay.Destroy()
    if IsObject(cap)
        FreeCapture(cap)
}