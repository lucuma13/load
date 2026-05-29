;-----------------------------------------
; Mac to Windows Keyboard Mapping
;=========================================

; ! = ALT
; ^ = CTRL
; + = SHIFT
; # = WIN

; --------------------------------------------------------------

; Todo: 
; Prevent Alt from activating top menu bar on Premiere
; Fix "Reveal in Explorer" not working on Premiere (and hence "Open clip with Mediainfo" macro not working either)
; Cmd+Shift+V cuts (macOS style)
; Adjust special characters according to language used
; Macro to install: VLC, MediaInfo, Winrar
; Fix issues with backtick and backslash keys
; Fix issues with pound and euro symbols


; -------------------------------------------------------------
; Header
; --------------------------------------------------------------

#Requires AutoHotkey v2
#SingleInstance Force
SetTitleMatchMode 2

; -------------------------------------------------------------
; Global macOS mappings
; --------------------------------------------------------------

; Prevent Windows key from launching start panel
~LWin::vkE8
~RWin::vkE8

; Prevent Alt+Shift keys from changing input source language
LAlt & LShift::vkE8

; Prevent Alt Gr from triggering Ctrl+Alt
~RAlt:: Send "!"

; Function keys
F3::Send "#{Tab}"
F7::Send "{Media_Prev}"
F8::Send "{Media_Play_Pause}"
F9::Send "{Media_Next}"
F10::Send "{Volume_Mute}"
F11::Send "{Volume_Down}"
F12::Send "{Volume_Up}"

; Spotlight
#Space::Send "#s"

; Save
#s::Send "^s"

; Select all
#a::Send "^a"

; Copy
#c::Send "^c"

; Paste
#v::Send "^v"

; Cut
#x::Send "^x" 

; Find
#f::Send "^f"

; Undo
#z::Send "^z"

; Redo
#+z::Send "^+z"
#y::Send "^y"

;Print
#p::Send "^p"

; New tab
#t::Send "^t"

; Close tab
#w::Send "^w"

; Go to Start
#Home::Send "^{Home}"

; Go to End
#End::Send "^{End}"

; Delete
#Backspace::Send "+{Home}{Delete}"

;Lock the screen (it's not remappable)
;#l::

; New item or folder
#n::Send "^n"
#+n::Send "^+n"

; Close windows (Cmd + Q to Alt + F4)
#q::Send "!{F4}"

; Refresh
#r::Send "{F5}"

; Change input language source
^Space::Send "#{Space}"

; Switch application
LWin & Tab::AltTab

; Minimise window
#h::WinMinimize "A"

; Capture entire screen with Cmd + Shift + 3
#+3::Send "#{PrintScreen}"

; Capture portion of the screen with Cmd + Shift + 4
#+4::Send "#+s"

; Print reverse date
#!^d::Send (A_YYYY A_MM A_DD)

; Middle click
; #LButton::Send "{MButton}"
#LButton::Send "^{LButton}"

; New Terminal Here
#!t:: {
    Static terminal := "wt.exe"
    targetDir := ""

    if WinActive("ahk_class CabinetWClass") {
        ; Save the user's current clipboard so we don't overwrite their copied data
        oldClip := ClipboardAll()
        A_Clipboard := ""
        
        ; 1. Try to copy the selected item's path first
        Send("^c")
        if ClipWait(0.2) {
            ; Clean the copied text of any quotes or hidden newlines
            itemPath := Trim(A_Clipboard, '" `t`r`n')
            
            ; If it's a directory, use it. If it's a file, get the parent folder.
            if InStr(FileExist(itemPath), "D") {
                targetDir := itemPath
            } else if FileExist(itemPath) {
                SplitPath(itemPath, , &parentDir)
                targetDir := parentDir
            }
        }
        
        ; 2. If nothing was selected, grab the current folder from the Address Bar
        if (targetDir == "") {
            A_Clipboard := ""
            Send("^l")       ; Focus the address bar
            Sleep(50)        ; Micro-pause for UI to catch up
            Send("^c")       ; Copy the path
            Sleep(50)
            Send("{Esc}")    ; Unfocus the address bar
            
            if ClipWait(0.2) {
                targetDir := Trim(A_Clipboard, '" `t`r`n')
            }
        }

        ; Restore the user's original clipboard
        A_Clipboard := oldClip
    }

    ; 3. Fallback: If we still have nothing, default to the Home folder
    if (targetDir == "" || !DirExist(targetDir)) {
        targetDir := EnvGet("USERPROFILE")
    }

    ; 4. Execute Terminal
    Run(terminal ' -d "' targetDir '"')
}
; --------------------------------------------------------------
; Global macOS mappings for special chars
; --------------------------------------------------------------

vkDC::Send "``"        ; produces `
+vkDC::~               ; produces ~
; vkDE::Send "{Blind}\\"             ; it should produce \ but it doesn't
+vkDE::Send "{|}"      ; produces |
+'::"
+2::@
+3::Send "{#}"

; These are likely to conflict with other shortcuts, so they remain mostly commented
;Alt & 1::Send "{¡}"
;Alt & 2::Send "{™}"
!3::Send "£"           ; produces £
;Alt & 3::Send "{£}"
;Alt & 4::Send "{¢}"
;Alt & 5::Send "{§}"
;Alt & 6::Send "{ˆ}"
;Alt & 7::Send "{¶}"
;Alt & 8::Send "{•}"
;Alt & 9::Send "{ª}"
;Alt & 0::Send "{º}"

; These are likely to conflict with other shortcuts, so they remain mostly commented
;!+1::Send {⁄}
!+2::Send "€"          ; produces €
;!+3::Send {‹}
;!+4::Send {›}
;!+5::Send {†}
;;!+6::Send {}
;!+7::Send {‡}
;!+8::Send {°}
;!+9::Send {·}
;!+0::Send {‚}

; --------------------------------------------------------------
; Dead keys for diacritics (ABC Extended style)
; --------------------------------------------------------------

global deadAccent := ""

; Dead key triggers
!e:: SetDeadKey("acute")        ; acute ( ´ )      á é í ó ú ý
!`:: SetDeadKey("grave")        ; grave ( ` )      à è ì ò ù
!u:: SetDeadKey("umlaut")       ; umlaut ( ¨ )     ä ë ï ö ü ÿ
!i:: SetDeadKey("circumflex")   ; circumflex ( ˆ ) â ê î ô û
!n:: SetDeadKey("tilde")        ; tilde ( ˜ )      ã ñ õ
!k:: SetDeadKey("ring")         ; ring ( ˚ )       å
!b:: SetDeadKey("breve")        ; breve ( ˘ )      ă ĕ ĭ ŏ ŭ
!p:: SetDeadKey("commabelow")   ; comma-below ( , ) ș ț

SetDeadKey(accent) {
    global deadAccent
    deadAccent := accent
}

accentMap := Map(
    "acute",      Map("a","á","e","é","i","í","o","ó","u","ú","y","ý",
                      "A","Á","E","É","I","Í","O","Ó","U","Ú","Y","Ý"),
    "grave",      Map("a","à","e","è","i","ì","o","ò","u","ù",
                      "A","À","E","È","I","Ì","O","Ò","U","Ù"),
    "umlaut",     Map("a","ä","e","ë","i","ï","o","ö","u","ü","y","ÿ",
                      "A","Ä","E","Ë","I","Ï","O","Ö","U","Ü"),
    "circumflex", Map("a","â","e","ê","i","î","o","ô","u","û",
                      "A","Â","E","Ê","I","Î","O","Ô","U","Û"),
    "tilde",      Map("a","ã","n","ñ","o","õ",
                      "A","Ã","N","Ñ","O","Õ"),
    "ring",       Map("a","å","A","Å"),
    "breve",      Map("a","ă","e","ĕ","i","ĭ","o","ŏ","u","ŭ",
                      "A","Ă","E","Ĕ","I","Ĭ","O","Ŏ","U","Ŭ"),
    "commabelow", Map("s","ș","t","ț","r","ȑ",
                      "S","Ș","T","Ț","R","Ȑ")
)

~*a:: TryAccent("a")
~*b:: TryAccent("b")
~*c:: TryAccent("c")
~*d:: TryAccent("d")
~*e:: TryAccent("e")
~*f:: TryAccent("f")
~*g:: TryAccent("g")
~*h:: TryAccent("h")
~*i:: TryAccent("i")
~*j:: TryAccent("j")
~*k:: TryAccent("k")
~*l:: TryAccent("l")
~*m:: TryAccent("m")
~*n:: TryAccent("n")
~*o:: TryAccent("o")
~*p:: TryAccent("p")
~*q:: TryAccent("q")
~*r:: TryAccent("r")
~*s:: TryAccent("s")
~*t:: TryAccent("t")
~*u:: TryAccent("u")
~*v:: TryAccent("v")
~*w:: TryAccent("w")
~*x:: TryAccent("x")
~*y:: TryAccent("y")
~*z:: TryAccent("z")

TryAccent(key) {
    global deadAccent, accentMap
    if (deadAccent = "")
        return
    actualKey := GetKeyState("Shift", "P") ? StrUpper(key) : key
    accent := deadAccent
    deadAccent := ""
    if (accentMap.Has(accent) && accentMap[accent].Has(actualKey))
        Send "{Backspace}" accentMap[accent][actualKey]
}

; --------------------------------------------------------------
; App-specific - Premiere Pro
; --------------------------------------------------------------

#HotIf WinActive("ahk_exe Adobe Premiere Pro.exe")

; Prevent Alt from activating top menu bar
~LAlt::
~RAlt::
{
    Send("{Blind}{vkE8}")
}



#d::Send "^d"
#+d::Send "^+d"
#+e::Send "^+e"
#i::Send "^i"
#l:: Send "^l"
#m::Send "^m"
#r::Send "^r"
#,::Send "^,"
#Left::Send "^{Left}"
#Right::Send "^{Right}"

#!,::Send "^!,"
#!k::Send "^!,"

; Nudge audio gain by 1dB with "[" and "]"
[::Send "{g}-1{Enter}"
]::Send "{g}1{Enter}"

; Move clip one track up (Selects)
#e::Send "d!{Up}"

; Add frame hold
#+h::Send "^+h"

; Reverse speed
#+r::
{
	Send "^r"
	Send "{Tab}"
	Send "{Tab}"
	Send "{Space}"
	Send "{Enter}"
}

;F19::Send, df+3{Up}. ;replace with clip from bin test

; Open clip with MediaInfo
#+i:: {
    ; 1. Simulate Premiere Pro Keystroke
    Send("!+f")

    ; 2. Beat the Tab Bug: Use the Clipboard to get the REAL selection
    Static mediaInfoApp := A_ProgramFiles '\MediaInfo\MediaInfo.exe'
    
    if WinActive("ahk_class CabinetWClass") || WinActive("ahk_class Progman") || WinActive("ahk_class WorkerW") {
        oldClip := ClipboardAll() ; Save current clipboard
        A_Clipboard := ""
        
        Send("^c") ; Copy selection
        if ClipWait(0.5) {
            ; AHK automatically handles multiple file paths with newlines
            for itemPath in StrSplit(A_Clipboard, "`n", "`r") {
                if (itemPath != "") {
                    ; Open each item in MediaInfo
                    Run(mediaInfoApp ' "' itemPath '"')
                }
            }
        }
        
        A_Clipboard := oldClip ; Restore clipboard
    }
}

#HotIf

; --------------------------------------------------------------
; App-specific - Google Chrome
; --------------------------------------------------------------

#HotIf WinActive("ahk_class Chrome_WidgetWin_1")

#+t::Send "^+t"
#y::Send "^h"
#!l::Send "^j"
#Enter::Send "^{Enter}"

#,::
{
	Send "^t"
	Send "chrome://settings"
	Send "{Enter}"
}

#HotIf

; --------------------------------------------------------------
;  App-specific - Explorer/Finder
; --------------------------------------------------------------

#HotIf WinActive("ahk_class CabinetWClass")

#1::Send "^!2" ; View as Large Icons
#2::Send "^!6" ; View as Details
#3::Send "^!5" ; View as List

#j:: ; View options
{
Send "!v"
Send "{Right}"
}


#+.:: ; Show hidden files
{
Send "!v"
Send "hh"
}

#i::Send "!{Enter}"
#[::Send "!{Left}" ; Go to prior folder in history
#]::Send "!{Right}" ; Go to next folder in history

; Cmd+Down will extract a zip/rar file, or open anything else
#Down:: {
    oldClip := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    
    if !ClipWait(0.5) {
        A_Clipboard := oldClip
        return
    }

    ; Split the clipboard into individual lines (one for each file)
    fileList := StrSplit(A_Clipboard, "`n", "`r")

    for selectedPath in fileList {
        if (selectedPath == "")
            continue

        ; Clean the individual path
        currentPath := Trim(selectedPath, '" `t`r`n')
        SplitPath(currentPath, , , &ext)

        if (ext = "zip" || ext = "rar" || ext = "7z") {
            destPath := RegExReplace(currentPath, "\.[^.\\]+$")
            
            if (ext = "zip") {
                ; PowerShell command with escaped quotes for each specific file
                psCmd := 'powershell.exe -NoProfile -Command "Expand-Archive -Path \`"' currentPath '\`" -DestinationPath \`"' destPath '\`" -Force"'
                Run(psCmd, , "Hide")
            } else {
                ; For RAR/7Z, we have to use the UI method. 
                ; Note: This opens a menu for each file, which can be messy for 10+ files.
                Run('explorer.exe /select,"' currentPath '"') ; Ensure focus is right
                Sleep(50)
                Send("+{F10}") 
                Sleep(100)
                Send("e")
            }
        } else {
            ; Open non-archive files
            Run('"' currentPath '"')
        }
    }

    if (fileList.Length > 1)
        ToolTip("Processing " fileList.Length " items...")
    
    SetTimer(() => ToolTip(), -2000)
    A_Clipboard := oldClip
}

#Up::Send "!{Up}"

#d:: {
    Send "^c"
;    Sleep 100   ; Add if running into timing issues
    Send "^v"
}

#!c:: {
    A_Clipboard := ""
    Send("^c")
    if ClipWait(0.5) {
        A_Clipboard := Trim(A_Clipboard, " `t`r`n")    ; Handle multiple files
    }
}

Enter:: {
 If ControlGetClassNN(ControlGetFocus()) ; If the focused control name
  ~= 'Edit|Search|Notify'                ;  contains any of the case-sensitive strings listed here
      Send '`n'
 Else Send '{F2}'
}

#+i:: {
  Static app := A_ProgramFiles '\MediaInfo\MediaInfo.exe'
  For item in getSelected()
   Run app ' "' item '"'
}

#HotIf

getSelected() {
 hwnd := WinExist('A'), selection := []
 If WinGetClass() ~= '(Cabinet|Explore)WClass'
  For window in ComObject('Shell.Application').Windows {
   Try window.hwnd
   Catch
    Return
   If window.hwnd = hwnd
    For item in window.document.SelectedItems
     selection.Push(item.Path)
  }
 Return selection
}

#+j:: {
        ; Use the shell environment variable for the Downloads path
        downloadsPath := EnvGet("USERPROFILE") "\Downloads"
        
        ; Navigate the current active Explorer window
        For window in ComObject("Shell.Application").Windows {
            if (window.HWND == WinActive("A")) {
                window.Navigate(downloadsPath)
                return
            }
        }
        ; Fallback: If navigation fails, just open a new window
        Run(downloadsPath)
    }

#+a:: {
        ; This is the Windows Shell ID for the Applications folder
        appsFolder := "shell:AppsFolder"
        
        For window in ComObject("Shell.Application").Windows {
            if (window.HWND == WinActive("A")) {
                window.Navigate(appsFolder)
                return
            }
        }
        Run(appsFolder)
    }

#+d:: {
        desktopPath := A_Desktop
        
        For window in ComObject("Shell.Application").Windows {
            if (window.HWND == WinActive("A")) {
                window.Navigate(desktopPath)
                return
            }
        }
        Run(desktopPath)
    }