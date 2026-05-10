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
; When Cmd+Down a zip/rar file, extract all, when cmd+down a file open it
; On Explorer - Copy filepath with Cmd+Alt+C
; Add accents as dead keys when English is the system language
; Cmd+Shift+V cuts (macOS style)
; Map all special characters macOS style
; Adjust brightness with F1 and F2
; Adjust special characters according to language used
; Shortcut to install: VLC, MediaInfo, Winrar
; Explorer go to folder: Cmd+Shift+D for Downloads, Cmd+Shift+A for Apps, etc

; -------------------------------------------------------------
; Header
; --------------------------------------------------------------

#Requires AutoHotkey v2
#SingleInstance Force
SetTitleMatchMode 2
;SendMode Input
;InstallKeybdHook

; -------------------------------------------------------------
; Global macOS mappings
; --------------------------------------------------------------

; Prevent Windows key from launching start panel
~LWin::vkE8
~RWin::vkE8

; Prevent Alt+Shift keys from changing input source language
LAlt & LShift::vkE8

; Prevent Alt Gr from triggering Ctrl+Alt
RAlt:: Send "!"

; Function keys
F3::Send "#{Tab}"
F7::SendInput "{Media_Prev}"
F8::SendInput "{Media_Play_Pause}"
F9::SendInput "{Media_Next}"
F10::SendInput "{Volume_Mute}"
F11::SendInput "{Volume_Down}"
F12::SendInput "{Volume_Up}"

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
#Backspace::Send "{Delete}"

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
Lwin & Tab::AltTab

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


; --------------------------------------------------------------
; Global macOS mappings for special chars
; --------------------------------------------------------------

+\::~
+'::"
+`::±
+2::@
+3::Send "{#}"

;Alt & 1::Send "{¡}"
;Alt & 2::Send "{™}"
;Alt & 3::Send "{£}"
;Alt & 4::Send "{¢}"
;Alt & 5::Send "{§}"
;Alt & 6::Send "{ˆ}"
;Alt & 7::Send "{¶}"
;Alt & 8::Send "{•}"
;Alt & 9::Send "{ª}"
;Alt & 0::Send "{º}"

;!+1::Send {⁄}
;!+2::Send {€}
;!+3::Send {‹}
;!+4::Send {›}
;!+5::Send {†}
;;!+6::Send {}
;!+7::Send {‡}
;!+8::Send {°}
;!+9::Send {·}
;!+0::Send {‚}


; --------------------------------------------------------------
; App-specific - Premiere Pro
; --------------------------------------------------------------

#HotIf WinActive("ahk_exe Adobe Premiere Pro.exe")

; Prevent Alt from activating top menu bar (NOT WORKING, hence code below)
;~Alt::Send "{Blind}{vkE8}" 

!c::
{
	Send "!c"
	Send "{Esc}"
}

#d::Send "^d"
#+d::Send "^+d"
#+e::Send "^+e"
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

#Down::Send "{Enter}"
#Up::Send "!{Up}"
#d::Send "^c^v"

#!c:: ; it should work with Send "^c" 
{
	A_Clipboard := ""
	Send "^c"
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