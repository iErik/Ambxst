#!/usr/bin/env python3
"""Patch Ambxst-generated Hyprland configs so task-switcher-confirm is bindr/release.

axctl's Hyprland 0.56 lua generator emits:
  hl.bind("SUPER + Super_L", hl.dsp.exec_cmd("ambxst run task-switcher-confirm"))
without { release = true }, even when axctl.toml has flags = "r".
"""

from __future__ import annotations

import pathlib
import sys


def fix_lua(text: str) -> str:
    out = []
    for line in text.splitlines(True):
        if (
            "task-switcher-confirm" in line
            and "hl.bind(" in line
            and "release" not in line
        ):
            stripped = line.rstrip("\n")
            if stripped.endswith(")"):
                line = stripped[:-1] + ", { release = true })\n"
        out.append(line)
    return "".join(out)


def fix_conf(text: str) -> str:
    out = []
    for line in text.splitlines(True):
        if "task-switcher-confirm" in line and "bindr" not in line:
            leading = line[: len(line) - len(line.lstrip())]
            rest = line.lstrip()
            if rest.startswith("bind ") or rest.startswith("bind="):
                rest = rest.replace("bind", "bindr", 1)
                line = leading + rest
        out.append(line)
    return "".join(out)


def patch(path: pathlib.Path, fixer) -> bool:
    if not path.is_file():
        return False
    original = path.read_text()
    updated = fixer(original)
    if updated != original:
        path.write_text(updated)
        return True
    return False


def main(argv: list[str]) -> int:
    share = pathlib.Path(argv[1]) if len(argv) > 1 else pathlib.Path.home() / ".local/share/ambxst"
    changed = False
    changed |= patch(share / "hyprland.lua", fix_lua)
    changed |= patch(share / "hyprland.conf", fix_conf)
    print("patched" if changed else "unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
