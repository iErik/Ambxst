#!/usr/bin/env python3
"""List Freedesktop cursor themes with preview image paths (JSON on stdout)."""

from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import zlib
from pathlib import Path

SEARCH_DIRS = [
    Path.home() / ".local/share/icons",
    Path("/usr/share/icons"),
    Path("/usr/local/share/icons"),
    Path.home() / ".icons",
]

# Common cursor names to show as card previews
PREVIEW_CURSORS = [
    "left_ptr",
    "default",
    "pointer",
    "hand2",
    "hand1",
    "text",
    "xterm",
    "crosshair",
    "move",
    "fleur",
    "sb_v_double_arrow",
    "sb_h_double_arrow",
    "wait",
    "watch",
]

CACHE_ROOT = Path.home() / ".cache" / "ambxst" / "cursor-previews"


def _read_gsettings_cursor_theme() -> str:
    try:
        out = subprocess.check_output(
            ["gsettings", "get", "org.gnome.desktop.interface", "cursor-theme"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return out.strip("'\"")
    except Exception:
        return ""


def _parse_index(index_path: Path) -> tuple[str, bool]:
    """Return (display_name, hidden)."""
    try:
        text = index_path.read_text(errors="ignore")
    except OSError:
        return "", True

    hidden = False
    display = ""
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == "Hidden=true":
            hidden = True
        elif stripped.startswith("Name=") and "[" not in stripped.split("=", 1)[0]:
            if not display:
                display = stripped.split("=", 1)[1].strip()
    return display, hidden


def _write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + rgba[y * width * 4 : (y + 1) * width * 4] for y in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def _extract_xcursor_png(xcursor_path: Path, out_path: Path, prefer: int = 48) -> bool:
    """Decode an Xcursor file and write the nearest size as PNG. Returns success."""
    try:
        data = xcursor_path.read_bytes()
    except OSError:
        return False

    if data[:4] != b"Xcur" or len(data) < 16:
        return False

    try:
        _header_size, _version, ntoc = struct.unpack_from("<III", data, 4)
    except struct.error:
        return False

    best: tuple[float, int, int, bytes] | None = None
    for i in range(ntoc):
        try:
            typ, _subtype, pos = struct.unpack_from("<III", data, 16 + i * 12)
        except struct.error:
            break
        if typ != 0xFFFD0002:  # IMAGE
            continue
        try:
            header_size, _t, _size, _ver, width, height, _xhot, _yhot, _delay = struct.unpack_from(
                "<IIIIIIIII", data, pos
            )
        except struct.error:
            continue
        if width <= 0 or height <= 0 or width > 512 or height > 512:
            continue
        pix_off = pos + header_size
        nbytes = width * height * 4
        if pix_off + nbytes > len(data):
            continue
        pixels = data[pix_off : pix_off + nbytes]
        # Native endian ARGB32 → RGBA (little-endian byte order is B,G,R,A)
        rgba = bytearray(nbytes)
        for j in range(width * height):
            b, g, r, a = pixels[j * 4 : j * 4 + 4]
            rgba[j * 4 : j * 4 + 4] = bytes((r, g, b, a))
        score = abs((width + height) / 2 - prefer)
        if best is None or score < best[0]:
            best = (score, width, height, bytes(rgba))

    if best is None:
        return False

    try:
        _write_png(out_path, best[1], best[2], best[3])
        return True
    except OSError:
        return False


def _resolve_cursor_file(cursors_dir: Path, name: str) -> Path | None:
    candidate = cursors_dir / name
    if candidate.is_file() and not candidate.is_symlink():
        return candidate
    if candidate.is_symlink() or candidate.is_file():
        try:
            resolved = candidate.resolve()
            if resolved.is_file():
                return resolved
        except OSError:
            pass
    return candidate if candidate.is_file() else None


def find_preview(theme_dir: Path, theme_id: str, cursor_name: str) -> str:
    """Return a filesystem path Qt can load (svg/png), or empty string."""
    # Prefer scalable SVG assets when present (Breeze, Oxygen, …)
    scalable_root = theme_dir / "cursors_scalable" / cursor_name
    if scalable_root.is_dir():
        for candidate in (
            scalable_root / "default.svg",
            *sorted(scalable_root.glob("*.svg")),
        ):
            if candidate.is_file():
                return str(candidate)

    # Theme-level cover / preview images
    for name in ("preview.png", "preview.svg", "thumbnail.png", "cover.png"):
        path = theme_dir / name
        if path.is_file():
            return str(path)

    cursors_dir = theme_dir / "cursors"
    xcursor = _resolve_cursor_file(cursors_dir, cursor_name)
    if not xcursor:
        return ""

    cache_path = CACHE_ROOT / theme_id / f"{cursor_name}.png"
    if cache_path.is_file() and cache_path.stat().st_mtime >= xcursor.stat().st_mtime:
        return str(cache_path)

    if _extract_xcursor_png(xcursor, cache_path):
        return str(cache_path)
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

            cursors_dir = theme_dir / "cursors"
            if not cursors_dir.is_dir():
                continue

            index_path = theme_dir / "index.theme"
            display = theme_id
            if index_path.is_file():
                parsed_name, hidden = _parse_index(index_path)
                if hidden:
                    continue
                if parsed_name:
                    display = parsed_name

            # Must have at least one real cursor file
            try:
                has_cursor = any(p.is_file() or p.is_symlink() for p in cursors_dir.iterdir())
            except OSError:
                has_cursor = False
            if not has_cursor:
                continue

            previews: list[str] = []
            for name in PREVIEW_CURSORS:
                path = find_preview(theme_dir, theme_id, name)
                if path and path not in previews:
                    previews.append(path)
                if len(previews) >= 4:
                    break

            seen.add(theme_id)
            themes.append(
                {
                    "id": theme_id,
                    "name": display,
                    "path": str(theme_dir),
                    "previews": previews,
                }
            )

    themes.sort(key=lambda t: t["name"].lower())
    return themes


def main() -> int:
    payload = {
        "current": _read_gsettings_cursor_theme(),
        "themes": collect_themes(),
    }
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
