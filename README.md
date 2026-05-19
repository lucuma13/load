## 🍏 Set up Mac worksation

1. Download my Premiere Pro shortcuts:
```
curl --output-dir $HOME/Documents/Adobe/Premiere\ Pro/ -O "https://raw.githubusercontent.com/lucuma13/prem/refs/heads/main/Luis_Mengo_25.1.kys"
```

2. Change default shell to bash:
```
chsh -s /bin/bash && echo "export BASH_SILENCE_DEPRECATION_WARNING=1" >> ~/.bash_profile
```

3. Install Homebrew:
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

4. Install useful formulas and casks:
```
brew tap lucuma13/dit
brew install git media-info exiftool ffmpeg atomicparsley bento4 imagemagick wget lookback
brew install --cask google-chrome vlc caffeine audacity mediainfo mediahuman-audio-converter appcleaner
```

5. Download and install Pro Video Formats:
```
cd ~/Downloads && curl -O "https://updates.cdn-apple.com/2026/macos/072-84099-20260127-5022F0FE-82CF-44E9-B96D-430E73501EBA/ProVideoFormats.dmg"
```
```
hdiutil attach ~/Downloads/ProVideoFormats.dmg
sudo installer -pkg /Volumes/ProVideoFormats/ProVideoFormats.pkg -target /
```
```
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

