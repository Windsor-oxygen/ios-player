#!/usr/bin/env python3
"""Проверяет, что во View нет «магических» чисел.

Запуск из корня репозитория:  python3 tools/check_design_tokens.py

В App/UI (кроме App/UI/DesignSystem, где живут токены) запрещены числовые
литералы, кроме 0 и 1: отступы, размеры, радиусы, тени, прозрачность,
длительности анимаций и т. п. берутся из `DS.*`. Строки и комментарии
не проверяются.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "App" / "UI"
TOKENS = UI / "DesignSystem"

NUMBER = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])")
ALLOWED = {"0", "1", "0.0", "1.0"}


def strip_code(text: str) -> str:
    """Убирает комментарии и содержимое строковых литералов (с интерполяцией)."""
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if text[i] == '"':
            triple = text.startswith('"""', i)
            end = '"""' if triple else '"'
            i += len(end)
            while i < n and not text.startswith(end, i):
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == "\n" and not triple:
                    break
                i += 1
            i += len(end)
            out.append('""')
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def main() -> int:
    problems = []
    for path in sorted(UI.rglob("*.swift")):
        if TOKENS in path.parents:
            continue
        code = strip_code(path.read_text(encoding="utf-8"))
        for number, line in ((m.group(1), code.count("\n", 0, m.start()) + 1) for m in NUMBER.finditer(code)):
            if number not in ALLOWED:
                problems.append(f"{path.relative_to(ROOT)}:{line}: число {number} — вынесите в токен DS.*")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        print(f"\nНайдено магических чисел: {len(problems)}", file=sys.stderr)
        return 1
    print("Магических чисел во View нет")
    return 0


if __name__ == "__main__":
    sys.exit(main())
