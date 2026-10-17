#!/usr/bin/env python3
"""Собирает App/Resources/Localizable.xcstrings из исходников и переводов.

Запуск из корня репозитория:  python3 tools/build_strings.py

Исходный язык — русский: ключом служит русская строка из кода, как это
делает Xcode для `Text("…")`, `String(localized: "…")` и т. п.
Интерполяции заменяются на спецификаторы формата (%lld для целых, %@ для строк).
Переводы на английский — в tools/strings_en.json. Если для какого-то ключа
перевода нет, скрипт печатает его и завершается с ошибкой.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "App"
CATALOG = SOURCES / "Resources" / "Localizable.xcstrings"
TRANSLATIONS = ROOT / "tools" / "strings_en.json"

# Конструкции, строковый литерал-аргумент которых локализуется (LocalizedStringKey
# или String.LocalizationValue). Смотрим на код непосредственно перед литералом.
LOCALIZED_CONTEXT = re.compile(
    r'(?:\bText|\bButton|\bLabel|\bSection|\bTab|\bPicker|\bTextField|\bLabeledContent|'
    r'\.navigationTitle|\.alert|\.confirmationDialog|ContentUnavailableView|'
    r'\.accessibilityLabel|\.accessibilityHint|\.accessibilityValue|String\(localized:|'
    r'prompt:|description:)\s*\(?\s*$'
)
CYRILLIC = re.compile(r'[А-Яа-яЁё]')
# Выражения, которые в интерполяции дают целое число (%lld). Остальное — %@.
INTEGER_HINT = re.compile(r'(count|added|failed|hidden|code|minutes|seconds|skipInterval)\)?$')


def string_literals(text: str):
    """Строковые литералы Swift: (позиция начала, части, интерполяции).

    Возвращает литерал как список: str — обычный текст, ('expr', код) — интерполяция.
    Понимает вложенные скобки и строки внутри интерполяций, пропускает комментарии.
    """
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            i = text.find("\n", i)
            if i < 0:
                return
            continue
        if text.startswith("/*", i):
            i = text.find("*/", i) + 2
            continue
        if text[i] == '"' and not text.startswith('"""', i):
            start = i
            parts, i = parse_literal(text, i + 1)
            yield start, parts
            continue
        i += 1


def parse_literal(text: str, i: int):
    parts: list = []
    buffer = []
    while i < len(text):
        ch = text[i]
        if ch == "\\":
            nxt = text[i + 1]
            if nxt == "(":
                if buffer:
                    parts.append("".join(buffer))
                    buffer = []
                depth, j = 1, i + 2
                while depth:
                    if text[j] == '"':
                        _, j = parse_literal(text, j + 1)
                        continue
                    depth += {"(": 1, ")": -1}.get(text[j], 0)
                    j += 1
                parts.append(("expr", text[i + 2:j - 1]))
                i = j
                continue
            buffer.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, nxt))
            i += 2
            continue
        if ch == '"':
            if buffer:
                parts.append("".join(buffer))
            return parts, i + 1
        buffer.append(ch)
        i += 1
    return parts, i


def to_key(parts) -> str:
    out = []
    for part in parts:
        if isinstance(part, tuple):
            out.append("%lld" if INTEGER_HINT.search(part[1].strip()) else "%@")
        else:
            out.append(part.replace("%", "%%") if any(isinstance(p, tuple) for p in parts) else part)
    return "".join(out)


def collect_keys() -> set[str]:
    keys: set[str] = set()
    for path in sorted(SOURCES.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for start, parts in string_literals(text):
            line_start = text.rfind("\n", 0, start) + 1
            line = text[line_start:start]
            if "Log." in line or "Logger(" in line:
                continue
            before = text[max(0, start - 80):start]
            plain = "".join(p for p in parts if isinstance(p, str))
            localized_call = LOCALIZED_CONTEXT.search(before) is not None
            ternary = re.search(r'[?:]\s*$', before) is not None and CYRILLIC.search(plain)
            if not (localized_call or ternary or CYRILLIC.search(plain)):
                continue
            key = to_key(parts)
            if key:
                keys.add(key)
    return keys


def main() -> int:
    translations: dict[str, str] = json.loads(TRANSLATIONS.read_text(encoding="utf-8"))
    keys = collect_keys()
    missing = sorted(key for key in keys if key not in translations)
    unused = sorted(key for key in translations if key not in keys)
    if missing:
        print("Нет перевода для:", file=sys.stderr)
        for key in missing:
            print(f"  {json.dumps(key, ensure_ascii=False)}", file=sys.stderr)
        return 1
    for key in unused:
        print(f"предупреждение: перевод не используется: {key!r}", file=sys.stderr)

    strings = {}
    for key in sorted(keys):
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": translations[key]}},
                "ru": {"stringUnit": {"state": "translated", "value": key}},
            },
        }
    catalog = {"sourceLanguage": "ru", "strings": strings, "version": "1.0"}
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {CATALOG.relative_to(ROOT)}: {len(keys)} keys")
    return 0


if __name__ == "__main__":
    sys.exit(main())
