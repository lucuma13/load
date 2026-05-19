## 🍏 Set up Mac worksation

1. Download my Premiere Pro shortcuts:
```
curl --output-dir $HOME/Documents/Adobe/Premiere\ Pro/ -O "https://raw.githubusercontent.com/lucuma13/prem/refs/heads/main/Luis_Mengo_25.1.kys"
```

2. Modify Keyboard/Trackpad preferences, then log out and back in:

```zsh
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2
```

3. Modify "Calculate all sizes" on Finder view options:

```zsh
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
```

3. Change default shell to bash, then restart Terminal:
```zsh
chsh -s /bin/bash && echo "export BASH_SILENCE_DEPRECATION_WARNING=1" >> ~/.bash_profile
```

4. Install Homebrew:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

5. Install useful formulas and casks:
```bash
brew tap lucuma13/dit
brew install git media-info exiftool ffmpeg atomicparsley bento4 imagemagick wget uv
brew install --cask google-chrome vlc caffeine audacity mediainfo mediahuman-audio-converter appcleaner
uv tool install triplecheck
```

6. Download and install Pro Video Formats:
```bash
cd ~/Downloads && curl -O "https://updates.cdn-apple.com/2026/macos/072-84099-20260127-5022F0FE-82CF-44E9-B96D-430E73501EBA/ProVideoFormats.dmg"
```
```bash
hdiutil attach ~/Downloads/ProVideoFormats.dmg
sudo installer -pkg /Volumes/ProVideoFormats/ProVideoFormats.pkg -target /
```
```bash
hdiutil detach /Volumes/ProVideoFormats && rm ~/Downloads/ProVideoFormats.dmg
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

