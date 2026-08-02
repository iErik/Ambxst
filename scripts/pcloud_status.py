#!/usr/bin/env python3
"""Best-effort pCloud status for Ambxst bar widget.

Reads mount/df for quota, process presence for running state, and
~/.pcloud/data.db task tables for pending transfers (upload_tasks, task, fstask).
Falls back to Cache/ heuristics when the DB has no queued rows.
"""

from __future__ import annotations

import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile


FS_TASK_LABELS = {
    1: "Create folder",
    2: "Remove folder",
    3: "Create/upload file",
    4: "Delete file",
    5: "Rename file",
    6: "Rename file",
    7: "Rename folder",
    8: "Rename folder",
    9: "Modify file",
    10: "Unset revision",
    11: "Set modified time",
    12: "Set created time",
}


def which(name: str) -> str | None:
    return shutil.which(name)


def home() -> str:
    return os.path.expanduser("~")


def default_drive() -> str:
    return os.path.join(home(), "pCloudDrive")


def detect_available() -> bool:
    if which("pcloud") or which("pcloudcc"):
        return True
    if os.path.isfile("/opt/pcloud/pCloud.AppImage"):
        return True
    if os.path.isdir(os.path.join(home(), ".pcloud")):
        return True
    if os.path.isdir(default_drive()):
        return True
    return False


def is_running() -> bool:
    try:
        r = subprocess.run(
            ["pgrep", "-f", r"(^|/)(pcloud(\.bin)?|pCloud\.AppImage|pcloudcc)(\s|$)"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return r.returncode == 0
    except Exception:
        return False


def is_mounted(path: str) -> bool:
    if not path or not os.path.isdir(path):
        return False
    try:
        r = subprocess.run(
            ["findmnt", "-T", path, "-no", "FSTYPE,SOURCE"],
            capture_output=True,
            text=True,
            check=False,
        )
        out = (r.stdout or "").strip().lower()
        if r.returncode == 0 and out and ("pcloud" in out or "fuse" in out):
            return True
    except Exception:
        pass
    try:
        r = subprocess.run(
            ["mountpoint", "-q", path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return r.returncode == 0
    except Exception:
        return False


def df_quota(path: str) -> tuple[int, int, int]:
    """Return (total, used, avail) in bytes from df, or zeros."""
    if not path or not os.path.isdir(path):
        return 0, 0, 0
    try:
        r = subprocess.run(
            ["df", "-B1", "--output=size,used,avail", path],
            capture_output=True,
            text=True,
            check=False,
        )
        if r.returncode != 0:
            return 0, 0, 0
        lines = [ln.strip() for ln in (r.stdout or "").splitlines() if ln.strip()]
        if len(lines) < 2:
            return 0, 0, 0
        parts = lines[-1].split()
        if len(parts) < 3:
            return 0, 0, 0
        return int(parts[0]), int(parts[1]), int(parts[2])
    except Exception:
        return 0, 0, 0


def snapshot_db(db_path: str) -> str | None:
    if not os.path.isfile(db_path):
        return None
    fd, snap = tempfile.mkstemp(prefix="pcloud-status-", suffix=".db")
    os.close(fd)
    try:
        shutil.copy2(db_path, snap)
        for suf in ("-wal", "-shm"):
            src = db_path + suf
            if os.path.isfile(src):
                try:
                    shutil.copy2(src, snap + suf)
                except Exception:
                    pass
        return snap
    except Exception:
        try:
            os.remove(snap)
        except Exception:
            pass
        return None


def cleanup_snap(snap: str | None) -> None:
    if not snap:
        return
    for p in (snap, snap + "-wal", snap + "-shm"):
        try:
            os.remove(p)
        except Exception:
            pass


def read_settings(con: sqlite3.Connection) -> dict:
    out = {}
    try:
        rows = con.execute(
            "SELECT id, value FROM setting WHERE id IN "
            "('quota','usedquota','freequota','fsroot','runstatus','username')"
        ).fetchall()
        for key, value in rows:
            out[str(key)] = "" if value is None else str(value)
    except Exception:
        pass
    return out


def task_direction(task_type: int) -> str:
    # PSYNC_TASK_UPLOAD bit is the low bit (see ptasks.h).
    return "upload" if (int(task_type) & 1) == 1 else "download"


def task_label(task_type: int, name: str) -> str:
    name = (name or "").strip() or "Transfer"
    direction = task_direction(task_type)
    kind = "file" if (int(task_type) & 2) == 2 else "folder"
    return f"{direction.capitalize()} {kind}: {name}"


def collect_transfers(con: sqlite3.Connection, limit: int = 40) -> list[dict]:
    transfers: list[dict] = []
    seen: set[str] = set()

    def add(item: dict) -> None:
        key = f"{item.get('direction')}|{item.get('name')}|{item.get('size')}|{item.get('source')}"
        if key in seen:
            return
        seen.add(key)
        transfers.append(item)

    try:
        for row in con.execute(
            "SELECT type, status, fname, fpath, size FROM upload_tasks "
            "ORDER BY id DESC LIMIT ?",
            (limit,),
        ):
            t, status, fname, fpath, size = row
            name = (fname or fpath or "Upload").strip() or "Upload"
            add(
                {
                    "direction": "upload",
                    "name": name,
                    "size": int(size or 0),
                    "status": int(status or 0),
                    "type": int(t or 0),
                    "source": "upload_tasks",
                    "label": name,
                }
            )
    except Exception:
        pass

    try:
        for row in con.execute(
            "SELECT type, name, inprogress FROM task ORDER BY id DESC LIMIT ?",
            (limit,),
        ):
            t, name, inprogress = row
            t = int(t or 0)
            direction = task_direction(t)
            add(
                {
                    "direction": direction,
                    "name": (name or "Transfer").strip() or "Transfer",
                    "size": 0,
                    "status": 1 if inprogress else 0,
                    "type": t,
                    "source": "task",
                    "label": task_label(t, name or ""),
                }
            )
    except Exception:
        pass

    try:
        for row in con.execute(
            "SELECT type, status, text1, text2, int1 FROM fstask "
            "ORDER BY id DESC LIMIT ?",
            (limit,),
        ):
            t, status, text1, text2, int1 = row
            t = int(t or 0)
            name = (text1 or text2 or FS_TASK_LABELS.get(t, "FS task")).strip()
            if not name:
                name = FS_TASK_LABELS.get(t, "FS task")
            # CREAT/MODIFY are effectively uploads from the FUSE client.
            direction = "upload" if t in (3, 5, 9, 11, 12) else "sync"
            add(
                {
                    "direction": direction,
                    "name": name,
                    "size": int(int1 or 0),
                    "status": int(status or 0),
                    "type": t,
                    "source": "fstask",
                    "label": f"{FS_TASK_LABELS.get(t, 'FS task')}: {name}"
                    if name not in FS_TASK_LABELS.values()
                    else name,
                }
            )
    except Exception:
        pass

    return transfers[:limit]


def cache_pending(cache_dir: str) -> list[dict]:
    """Official console-client hint: non-`cached` files imply pending work."""
    if not os.path.isdir(cache_dir):
        return []
    pending = []
    try:
        for name in os.listdir(cache_dir):
            if name in ("cached", ".", ".."):
                continue
            path = os.path.join(cache_dir, name)
            if not os.path.isfile(path):
                continue
            try:
                size = os.path.getsize(path)
            except Exception:
                size = 0
            if size <= 0:
                continue
            pending.append(
                {
                    "direction": "sync",
                    "name": name,
                    "size": int(size),
                    "status": 1,
                    "type": -1,
                    "source": "cache",
                    "label": f"Caching {name}",
                }
            )
    except Exception:
        return []
    return pending[:20]


def main() -> int:
    available = detect_available()
    drive = default_drive()
    username = ""
    runstatus = ""
    total = used = free = 0
    transfers: list[dict] = []
    db_ok = False

    snap = None
    db_path = os.path.join(home(), ".pcloud", "data.db")
    if available and os.path.isfile(db_path):
        snap = snapshot_db(db_path)
        if snap:
            try:
                con = sqlite3.connect(snap, timeout=0.5)
                settings = read_settings(con)
                username = settings.get("username", "")
                runstatus = settings.get("runstatus", "")
                fsroot = settings.get("fsroot", "").strip()
                if fsroot:
                    drive = os.path.expanduser(fsroot)
                try:
                    total = int(settings.get("quota") or 0)
                    used = int(settings.get("usedquota") or 0)
                    free = int(settings.get("freequota") or 0)
                    if free <= 0 and total > 0:
                        free = max(total - used, 0)
                except Exception:
                    pass
                transfers = collect_transfers(con)
                db_ok = True
                con.close()
            except Exception:
                db_ok = False

    cleanup_snap(snap)

    mounted = is_mounted(drive)
    running = is_running()

    df_total, df_used, df_avail = df_quota(drive) if mounted else (0, 0, 0)
    if df_total > 0:
        total, used, free = df_total, df_used, df_avail

    if not transfers:
        transfers = cache_pending(os.path.join(home(), ".pcloud", "Cache"))

    uploading = sum(1 for t in transfers if t.get("direction") == "upload")
    downloading = sum(1 for t in transfers if t.get("direction") == "download")
    syncing = len(transfers) > 0

    status = "Unavailable"
    if not available:
        status = "Not installed"
    elif not running and not mounted:
        status = "Not running"
    elif mounted and syncing:
        status = "Syncing"
    elif mounted and running:
        status = "Connected"
    elif mounted:
        status = "Mounted"
    elif running:
        status = "Starting…"
    else:
        status = "Offline"

    payload = {
        "available": available,
        "running": running,
        "mounted": mounted,
        "syncing": syncing,
        "status": status,
        "drivePath": drive,
        "username": username,
        "runstatus": runstatus,
        "dbOk": db_ok,
        "quotaTotal": total,
        "quotaUsed": used,
        "quotaFree": free,
        "uploadCount": uploading,
        "downloadCount": downloading,
        "transferCount": len(transfers),
        "transfers": transfers,
    }
    sys.stdout.write(json.dumps(payload, separators=(",", ":")))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
