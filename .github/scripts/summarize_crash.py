#!/usr/bin/env python3
"""Печатает суть краш-репорта iOS (.ips): исключение, причину и стек упавшего потока.

.ips — две JSON-записи подряд: заголовок (одна строка) и тело отчёта.
"""
import json
import sys


def main() -> int:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
        header_line = handle.readline()
        body = json.loads(handle.read())
    header = json.loads(header_line)
    print("app:", header.get("app_name"), header.get("app_version"), "build", header.get("build_version"))
    print("exception:", json.dumps(body.get("exception"), ensure_ascii=False))
    print("termination:", json.dumps(body.get("termination"), ensure_ascii=False))
    if body.get("asi"):
        print("asi:", json.dumps(body.get("asi"), ensure_ascii=False))
    images = body.get("usedImages", [])
    threads = body.get("threads", [])
    crashed = next((t for t in threads if t.get("triggered")), threads[0] if threads else {})
    print("crashed thread:", crashed.get("name") or crashed.get("queue") or "?")
    for frame in crashed.get("frames", [])[:40]:
        image = images[frame.get("imageIndex", 0)] if images else {}
        symbol = frame.get("symbol") or hex(frame.get("imageOffset", 0))
        location = ""
        if frame.get("sourceFile"):
            location = f" ({frame['sourceFile']}:{frame.get('sourceLine', '?')})"
        print(f"  {image.get('name', '?')}: {symbol}{location}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
