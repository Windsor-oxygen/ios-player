#!/usr/bin/env bash
# Скриншоты основных экранов в симуляторе на демо-данных (Debug-сборка,
# launch argument -PlayerDemo). Использование: screenshots.sh <udid> <Player.app> <папка>
set -euo pipefail

udid="$1"
app="$2"
out="$3"
bundle="io.github.windsor-oxygen.player"
mkdir -p "$out"

xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$app"
xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true

# shot <имя> <тема> <аргументы приложения…>
shot() {
  local name="$1" appearance="$2"
  shift 2
  xcrun simctl ui "$udid" appearance "$appearance" || true
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$bundle" -AppleLanguages "(ru)" -AppleLocale ru_RU \
    -PlayerDemoAppearance "$appearance" "$@" >/dev/null
  # Генерация демо-данных, сканирование, анимации появления.
  sleep 7
  xcrun simctl io "$udid" screenshot --type=png "$out/$name.png" >/dev/null
  echo "снят $name"
}

for appearance in dark light; do
  shot "01-library-miniplayer-$appearance" "$appearance" -PlayerDemo library
  shot "02-now-playing-$appearance" "$appearance" -PlayerDemo nowPlaying
  shot "03-settings-$appearance" "$appearance" -PlayerDemo settings
  shot "04-app-icon-$appearance" "$appearance" -PlayerDemo icons
  shot "05-empty-$appearance" "$appearance" -PlayerDemo empty
  shot "08-artwork-crop-$appearance" "$appearance" -PlayerDemo artworkCrop
  shot "09-placeholder-now-playing-$appearance" "$appearance" -PlayerDemo placeholder
done
shot "06-library-large-text-dark" dark -PlayerDemo library \
  -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
shot "07-now-playing-large-text-dark" dark -PlayerDemo nowPlaying \
  -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL

xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
ls -l "$out"
