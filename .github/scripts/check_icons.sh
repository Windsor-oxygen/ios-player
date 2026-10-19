#!/usr/bin/env bash
# Проверяет, что все альтернативные иконки из asset catalog попали в собранный
# .app: Info.plist → CFBundleIcons → CFBundleAlternateIcons. Иначе — ошибка.
# Использование: check_icons.sh <Player.app> <Assets.xcassets>
set -euo pipefail

app="$1"
assets="$2"
plist="$app/Info.plist"

expected=$(find "$assets" -maxdepth 1 -type d -name 'AppIcon-*.appiconset' -exec basename {} .appiconset \; | sort)
count=$(echo "$expected" | grep -c . || true)
if [[ "$count" -lt 6 ]]; then
  echo "::error::В asset catalog меньше 6 альтернативных иконок ($count)" >&2
  exit 1
fi

primary=$(plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw -o - "$plist" 2>/dev/null || true)
if [[ "$primary" != "AppIcon" ]]; then
  echo "::error::Основная иконка в Info.plist: '${primary}', ожидалась AppIcon" >&2
  exit 1
fi

if ! alternates=$(plutil -extract CFBundleIcons.CFBundleAlternateIcons json -o - "$plist" 2>/dev/null); then
  echo "::error::В Info.plist сборки нет CFBundleIcons → CFBundleAlternateIcons" >&2
  plutil -p "$plist" >&2
  exit 1
fi

missing=0
for name in $expected; do
  if python3 -c 'import json, sys; sys.exit(0 if sys.argv[1] in json.loads(sys.argv[2]) else 1)' "$name" "$alternates"; then
    echo "✓ $name"
  else
    echo "::error::Иконка $name не попала в CFBundleAlternateIcons" >&2
    missing=1
  fi
done
[[ "$missing" -eq 0 ]] || exit 1

# Справочно: тёмные и tinted-рендишены иконок в Assets.car.
if xcrun assetutil --info "$app/Assets.car" > assetutil.json 2>/dev/null; then
  python3 - <<'PY' || true
import json
rows = json.load(open("assetutil.json"))
icons = [r for r in rows if str(r.get("Name", "")).startswith("AppIcon")]
appearances = sorted({str(r.get("Appearance", "—")) for r in icons})
print(f"Assets.car: {len(icons)} рендишенов иконок, оформления: {', '.join(appearances)}")
PY
fi
