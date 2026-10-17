#!/usr/bin/env bash
# Выбирает стабильный Xcode с iOS 18+ SDK. Версию не хардкодим: берём самый
# новый не-beta Xcode 16.x (SDK iOS 18.x, как на целевом устройстве), а если
# его нет — самый новый стабильный из установленных.
set -euo pipefail

echo "Установленные Xcode:"
ls /Applications | grep Xcode || true

stable() { grep -viE 'beta|_rc|release.?candidate' || true; }

pick=$( (ls -d /Applications/Xcode_16*.app 2>/dev/null || true) | stable | sort -V | tail -n 1)
if [[ -z "${pick}" ]]; then
  pick=$( (ls -d /Applications/Xcode_*.app 2>/dev/null || true) | stable | sort -V | tail -n 1)
fi
if [[ -z "${pick}" ]]; then
  echo "::error::Не найден стабильный Xcode" >&2
  exit 1
fi

echo "Выбран: ${pick}"
sudo xcode-select -s "${pick}/Contents/Developer"
xcodebuild -version
sdk=$(xcrun --sdk iphoneos --show-sdk-version)
echo "iOS SDK: ${sdk}"
if [[ "${sdk%%.*}" -lt 18 ]]; then
  echo "::error::Нужен iOS SDK 18+, найден ${sdk}" >&2
  exit 1
fi

version=$(xcodebuild -version | tr '\n' ' ' | sed 's/ *$//')
echo "version=${version}" >> "${GITHUB_OUTPUT}"
