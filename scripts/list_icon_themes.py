#!/usr/bin/env python3
"""List Freedesktop icon themes with preview icon paths (JSON on stdout)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

PREVIEW_NAMES = [
    "folder",
    "user-home",
    "firefox",
    "kitty",
    "org.gnome.Nautilus",
    "applications-system",
    "utilities-terminal",
    "text-x-generic",
    "image-x-generic",
    "audio-x-generic",
    "video-x-generic",
    "preferences-system",
]

SIZE_DIRS = [
    "scalable",
    "48x48",
    "48",
    "64x64",
    "32x32",
    "32",
    "24x24",
    "22x22",
    "16x16",
]

CATEGORIES = [
    "apps",
    "places",
    "categories",
    "devices",
    "mimetypes",
    "status",
    "actions",
]

SEARCH_DIRS = [
    Path.home() / ".local/share/icons",
    Path("/usr/share/icons"),
    Path("/usr/local/share/icons"),
    Path.home() / ".icons",
]


def _read_gsettings_icon_theme() -> str:
    try:
        out = subprocess.check_output(
            ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return out.strip("'\"")
    except Exception:
        return ""


def _parse_index(index_path: Path) -> tuple[str, bool, bool]:
    """Return (display_name, hidden, looks_like_icon_theme)."""
    try:
        text = index_path.read_text(errors="ignore")
    except OSError:
        return "", True, False

    hidden = False
    display = ""
    looks_icon = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == "Hidden=true":
            hidden = True
        elif stripped.startswith("Name=") and "[" not in stripped.split("=", 1)[0]:
            # Prefer the first plain Name= (not Name[locale]=)
            if not display:
                display = stripped.split("=", 1)[1].strip()
        lower = stripped.lower()
        if lower.startswith("directories=") and any(
            key in lower
            for key in (
                "apps",
                "places",
                "mimetypes",
                "actions",
                "categories",
                "devices",
                "status",
                "emblems",
            )
        ):
            looks_icon = True

    return display, hidden, looks_icon


def _has_icon_dirs(theme_dir: Path) -> bool:
    candidates = [
        "scalable/apps",
        "scalable/places",
        "48x48/apps",
        "48x48/places",
        "32x32/apps",
        "apps/48",
        "apps/scalable",
        "places/48",
        "places/scalable",
        "places/64",
    ]
    return any((theme_dir / rel).is_dir() for rel in candidates)


def find_icon(theme_dir: Path, name: str) -> str:
    for size in SIZE_DIRS:
        for cat in CATEGORIES:
            for ext in ("svg", "png"):
                for path in (
                    theme_dir / size / cat / f"{name}.{ext}",
                    theme_dir / cat / size / f"{name}.{ext}",
                ):
                    if path.is_file():
                        return str(path)

    # Limited fallback — avoid scanning huge trees fully
    for size in SIZE_DIRS[:5]:
        size_dir = theme_dir / size
        if not size_dir.is_dir():
            # breeze-style: category/size
            for cat in CATEGORIES:
                cat_size = theme_dir / cat / size
                if not cat_size.is_dir():
                    continue
                for ext in ("svg", "png"):
                    path = cat_size / f"{name}.{ext}"
                    if path.is_file():
                        return str(path)
            continue
        for cat in CATEGORIES:
            for ext in ("svg", "png"):
                path = size_dir / cat / f"{name}.{ext}"
                if path.is_file():
                    return str(path)
    return ""


def collect_themes() -> list[dict]:
    seen: set[str] = set()
    themes: list[dict] = []

    for root in SEARCH_DIRS:
        if not root.is_dir():
            continue
        try:
            entries = sorted(root.iterdir(), key=lambda p: p.name.lower())
        except OSError:
            continue

        for theme_dir in entries:
            if not theme_dir.is_dir():
                continue
            theme_id = theme_dir.name
            if theme_id in seen:
                continue

            index_path = theme_dir / "index.theme"
            if not index_path.is_file():
                continue

            display, hidden, looks_icon = _parse_index(index_path)
            if hidden:
                continue
            if not looks_icon and not _has_icon_dirs(theme_dir):
                continue

            previews: list[str] = []
            for name in PREVIEW_NAMES:
                path = find_icon(theme_dir, name)
                if path:
                    previews.append(path)
                if len(previews) >= 5:
                    break

            # Skip themes that can't show any preview icons
            if not previews:
                continue

            seen.add(theme_id)
            themes.append(
                {
                    "id": theme_id,
                    "name": display or theme_id,
                    "path": str(theme_dir),
                    "previews": previews,
                }
            )

    themes.sort(key=lambda t: t["name"].lower())
    return themes


def main() -> int:
    payload = {
        "current": _read_gsettings_icon_theme(),
        "themes": collect_themes(),
    }
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
