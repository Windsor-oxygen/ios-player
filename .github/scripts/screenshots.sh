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

diag="$out/diagnostics"
# Отметка времени: краш-репорты новее неё — от этого прогона.
marker=$(mktemp)
failed=()

# Процесс приложения жив (иначе на снимке будет рабочий стол).
app_running() {
  xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -q "UIKitApplication:$bundle"
}

# Краш-репорты (симулятор пишет их на хост) и журнал приложения.
collect_diagnostics() {
  local name="$1"
  mkdir -p "$diag"
  find "$HOME/Library/Logs/DiagnosticReports" -name 'Player*' -newer "$marker" \
    -exec cp {} "$diag/" \; 2>/dev/null || true
  xcrun simctl spawn "$udid" log show --last 2m --style compact \
    --predicate 'process == "Player"' > "$diag/$name.log" 2>&1 || true
}

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
  if app_running; then
    echo "снят $name (приложение запущено)"
  else
    echo "::error::$name: к моменту снимка приложение не запущено (упало или закрылось)"
    collect_diagnostics "$name"
    failed+=("$name")
  fi
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

if ((${#failed[@]})); then
  echo "::error::Приложение не работало на снимках: ${failed[*]}. Диагностика — в артефакте Screenshots/diagnostics."
  # Краткая выжимка краш-репортов прямо в лог: тип исключения и стек упавшего потока.
  for report in "$diag"/*.ips; do
    [[ -e "$report" ]] || continue
    echo "=== $(basename "$report")"
    python3 .github/scripts/summarize_crash.py "$report" || head -n 60 "$report"
  done
  for log in "$diag"/*.log; do
    [[ -e "$log" ]] || continue
    echo "=== $(basename "$log") (хвост)"
    tail -n 40 "$log"
  done
  exit 1
fi
