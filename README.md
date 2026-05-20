## 🍏 Set up Mac worksation

1. Download my Premiere Pro shortcuts:
```
curl --output-dir $HOME/Documents/Adobe/Premiere\ Pro/ -O "https://raw.githubusercontent.com/lucuma13/prem/refs/heads/main/Luis_Mengo_25.1.kys"
```

2. Set preferences:
```
# ----------------------------------------------------------
# macOS
# ----------------------------------------------------------

# Keyboard/Trackpad preferences
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2

# Set the battery percentage to show in the menu bar
defaults write com.apple.controlcenter BatteryShowPercentage -bool true

# ----------------------------------------------------------
# Finder preferences
# ----------------------------------------------------------

# Enable path bar and status bar
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
killall Finder

# Modify "Calculate all sizes" on Finder view options (it does not work perfectly)
osascript -e 'tell application "Finder" to quit' && sleep 2 && plutil -convert xml1 ~/Library/Preferences/com.apple.finder.plist && python3 -c "
import plistlib, os
path = os.path.expanduser('~/Library/Preferences/com.apple.finder.plist')
p = plistlib.load(open(path,'rb'))
def f(o):
    if isinstance(o,dict):
        for k,v in o.items():
            if k=='calculateAllSizes':
                o[k]=True
            else:
                f(v)
    elif isinstance(o,list):
        for i in o:
            f(i)
f(p)
plistlib.dump(p,open(path,'wb'))
" && sleep 1 && open -a Finder

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

3. Change default shell to bash, then restart Terminal:
```
chsh -s /bin/bash && echo "export BASH_SILENCE_DEPRECATION_WARNING=1" >> ~/.bash_profile
```

4. Install Homebrew:
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

5. Install useful formulas and casks:
```
brew install git media-info exiftool ffmpeg atomicparsley bento4 wget uv
brew install --cask google-chrome vlc caffeine audacity mediainfo mediahuman-audio-converter appcleaner
uv tool install triplecheck
```

6. Download and install Pro Video Formats:
```
if system_profiler SPInstallHistoryDataType 2>/dev/null | grep -q "Pro Video Formats"; then
    echo "Pro Video Formats is already installed."
else
    echo "Pro Video Formats not found. Downloading..."
    cd ~/Downloads && curl -O "https://updates.cdn-apple.com/2026/macos/072-84099-20260127-5022F0FE-82CF-44E9-B96D-430E73501EBA/ProVideoFormats.dmg"
    
    hdiutil attach ~/Downloads/ProVideoFormats.dmg -nobrowse -quiet
    sudo installer -pkg "/Volumes/ProVideoFormats/ProVideoFormats.pkg" -target /
    hdiutil detach "/Volumes/ProVideoFormats" -quiet
    rm ~/Downloads/ProVideoFormats.dmg

    echo "Installation complete."
fi
```
## 🪟 Set up Windows worksation

1. Download my Premiere Pro shortcuts:
```
curl --output-dir $HOME/Documents/Adobe/Premiere\ Pro/ -O "https://raw.githubusercontent.com/lucuma13/prem/refs/heads/main/Luis_Mengo_25.1_WINDOWS.kys"
```

2. Install useful packages (test, combine arguments in single line and add these if necessary: --accept-package-agreements --accept-source-agreements):
```
winget install AutoHotkey.AutoHotkey
winget install astral-sh.uv MediaArea.MediaInfo MediaArea.MediaInfo.GUI OliverBetz.ExifTool Gyan.FFmpeg
winget install AtomicParsley.AtomicParsley Bento4.Bento4 ImageMagick.ImageMagick Google.Chrome VideoLAN.VLC ZhornSoftware.Caffeine Audacity.Audacity
```
3. Download and install my AHK shortcuts:
```
$path="$HOME\Downloads\MacKeyboard_LM.ahk"; curl.exe -o $path "https://raw.githubusercontent.com/lucuma13/prem/refs/heads/main/MacKeyboard_LM"; Start-Process "AutoHotkey.exe" -ArgumentList $p -Verb RunAs
```

