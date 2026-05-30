## 🚗 Auto Set Up Workstation

* macOS
Fast set-up:
```bash
curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh | bash -s -- --fast
```

Full set-up:
```bash
curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh | bash -s -- --full
```

* Windows:
Fast set-up:
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing -OutFile "$env:TEMP\load-win.ps1"; & "$env:TEMP\load-win.ps1" --fast
```

Full set-up:
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing -OutFile "$env:TEMP\load-win.ps1"; & "$env:TEMP\load-win.ps1" --full
```


## 🍏 Manual Set up Mac worksation

1. Download my Premiere Pro shortcuts:
```
for dir in "$HOME/Documents/Adobe/Premiere Pro"/*/; do
    if ls "$dir"Profile-*/Win &>/dev/null 2>&1; then
        (cd "$dir" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/Luis_Mengo_25.1.kys")
    fi
done
```

2. Set preferences:
```
# ----------------------------------------------------------
# TextEdit preferences
# ----------------------------------------------------------

# New document "Plain text"
defaults write com.apple.TextEdit RichText -int 0 # Plain Text

# Turn off "Correct spelling automatically" OFF"
defaults write com.apple.TextEdit CorrectSpellingAutomatically -bool false 

# Turn off "Smart dashes"
defaults write com.apple.TextEdit SmartDashes -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Turn off "Text replacement"
defaults write com.apple.TextEdit TextReplacement -bool false
defaults write NSGlobalDomain NSAutomaticTextCompletionEnabled -bool false

# Turn off show ruler
defaults write com.apple.TextEdit ShowRuler -bool false

# Clear preference cache and restart text subsystems to force application
killall cfprefsd
killall AppleSpell
killall TextEdit 2>/dev/null || true
```

3. Install Homebrew:
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

4. Install useful formulas and casks:
```
brew install git media-info exiftool ffmpeg atomicparsley bento4 wget uv
brew install --cask google-chrome vlc caffeine audacity mediainfo mediahuman-audio-converter appcleaner
uv tool install triplecheck
```

5. Download and install Pro Video Formats:
```
cd ~/Downloads

if [ ! -f ProVideoFormats.dmg ]; then
  curl -O "https://updates.cdn-apple.com/2026/macos/072-84099-20260127-5022F0FE-82CF-44E9-B96D-430E73501EBA/ProVideoFormats.dmg"
fi

hdiutil attach ~/Downloads/ProVideoFormats.dmg -nobrowse
sudo installer -pkg "/Volumes/Pro Video Formats/ProVideoFormats.pkg" -target /
hdiutil detach "/Volumes/Pro Video Formats" -quiet
rm ~/Downloads/ProVideoFormats.dmg
```
## 🪟 Manual Set up Windows worksation

1. Download my Premiere Pro shortcuts:
```
foreach ($dir in Get-ChildItem "$HOME\Documents\Adobe\Premiere Pro" -Directory) {
  if (Test-Path "$($dir.FullName)\Profile-*\Win") {
    curl --output-dir "$($dir.FullName)" -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/Luis_Mengo_25.1_WINDOWS.kys"
  }
}
```

2. Install useful packages (test, combine arguments in single line and add these if necessary: --accept-package-agreements --accept-source-agreements):
```
winget install AutoHotkey.AutoHotkey
winget install astral-sh.uv MediaArea.MediaInfo MediaArea.MediaInfo.GUI OliverBetz.ExifTool Gyan.FFmpeg
winget install AtomicParsley.AtomicParsley Bento4.Bento4 ImageMagick.ImageMagick Google.Chrome VideoLAN.VLC ZhornSoftware.Caffeine Audacity.Audacity
```
3. Download and install my AHK shortcuts:
```
$path="$HOME\Downloads\MacKeyboard_LM.ahk"; curl.exe -o $path "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/MacKeyboard_LM.ahk"; Start-Process "AutoHotkey.exe" -ArgumentList $p -Verb RunAs
```

