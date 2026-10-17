#!/usr/bin/env python3
"""Печатает id доступного симулятора iPhone с самой новой iOS.

Сначала смотрит `xcodebuild -showdestinations` (только то, что реально
поддерживает выбранный Xcode), затем — `xcrun simctl list devices available`.
"""
import json
import re
import subprocess
import sys


def version_key(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", text))


def from_destinations(project: str, scheme: str) -> list[tuple[tuple[int, ...], str, str]]:
    out = subprocess.run(
        ["xcodebuild", "-showdestinations", "-project", project, "-scheme", scheme],
        capture_output=True, text=True, check=False,
    ).stdout
    found = []
    for line in out.splitlines():
        if "platform:iOS Simulator" not in line:
            continue
        ident = re.search(r"id:([0-9A-Fa-f-]{36})", line)
        os_ver = re.search(r"OS:([\d.]+)", line)
        name = re.search(r"name:([^,}]+)", line)
        if ident and os_ver and name and name.group(1).strip().startswith("iPhone"):
            found.append((version_key(os_ver.group(1)), ident.group(1), name.group(1).strip()))
    return found


def from_simctl() -> list[tuple[tuple[int, ...], str, str]]:
    out = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True, text=True, check=True,
    ).stdout
    found = []
    for runtime, devices in json.loads(out).get("devices", {}).items():
        if ".iOS-" not in runtime:
            continue
        ver = version_key(runtime.split(".iOS-")[-1])
        for device in devices:
            if device.get("name", "").startswith("iPhone") and device.get("isAvailable", True):
                found.append((ver, device["udid"], device["name"]))
    return found


def main() -> int:
    project, scheme = sys.argv[1], sys.argv[2]
    candidates = from_destinations(project, scheme) or from_simctl()
    candidates = [c for c in candidates if c[0] >= (18,)]
    if not candidates:
        print("Не найден симулятор iPhone с iOS 18+", file=sys.stderr)
        return 1
    candidates.sort(key=lambda c: c[0])
    ver, udid, name = candidates[-1]
    print(f"Симулятор: {name}, iOS {'.'.join(map(str, ver))}, {udid}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
