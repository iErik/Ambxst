#!/usr/bin/env python3
"""Yeelight LAN helper for Ambxst.

Speaks the Yeelight LAN protocol (no cloud): SSDP-style discovery on UDP
239.255.255.250:1982 and one persistent TCP connection per bulb on port 55443.
Bulbs must have "LAN Control" enabled in the Yeelight app.

Talks to the shell with JSON lines:

stdin (commands)
    {"cmd": "discover"}
    {"cmd": "add", "ip": "192.168.1.42"}
    {"cmd": "remove", "ip": "192.168.1.42"}
    {"cmd": "set", "ip": "192.168.1.42", "method": "set_bright", "params": [60, "smooth", 300]}
    {"cmd": "refresh"}

stdout (events)
    {"event": "bulb", "bulb": {...}}              found or changed
    {"event": "error", "ip": ..., "message": ...}
    {"event": "discover-done", "count": n}
    {"event": "listening", "port": n}             discovery socket port

Repeated "set" commands with the same method are coalesced and sent at most
every SEND_INTERVAL seconds per bulb (the latest value always goes out), to
stay under the bulbs' ~60 commands/minute quota while dragging a slider.
"""

from __future__ import annotations

import json
import select
import socket
import struct
import sys
import threading
import time

MCAST_GROUP = "239.255.255.250"
MCAST_PORT = 1982
CONTROL_PORT = 55443
SEND_INTERVAL = 0.25
DISCOVER_WINDOW = 2.5
RECONNECT_DELAY = 5.0
SWEEP_TIMEOUT = 0.6
PROPS = ["power", "bright", "ct", "rgb", "hue", "sat", "color_mode", "name"]

_out_lock = threading.Lock()


def emit(obj: dict) -> None:
    with _out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def _local_ipv4() -> str:
    """The address of the interface holding the default route."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.0.2.1", 9))  # TEST-NET, nothing is sent
        return s.getsockname()[0]
    except OSError:
        return ""
    finally:
        s.close()


def _to_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


class Bulb:
    """One bulb: state, a control connection and a coalescing send queue."""

    def __init__(self, ip: str, port: int = CONTROL_PORT):
        self.ip = ip
        self.port = port
        self.id = ""
        self.model = ""
        self.state = {
            "power": "off", "bright": 0, "ct": 0, "rgb": 0,
            "hue": 0, "sat": 0, "color_mode": 0, "name": "",
        }
        self.online = False
        self._pending: dict[str, list] = {}
        self._lock = threading.Lock()
        self._wake = threading.Event()
        self._stop = False
        self._msg_id = 0
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    # -- state ---------------------------------------------------------------
    def snapshot(self) -> dict:
        s = self.state
        return {
            "ip": self.ip,
            "id": self.id,
            "model": self.model,
            "name": s.get("name", ""),
            "power": s.get("power") == "on",
            "bright": _to_int(s.get("bright")),
            "ct": _to_int(s.get("ct")),
            "rgb": _to_int(s.get("rgb")),
            "hue": _to_int(s.get("hue")),
            "sat": _to_int(s.get("sat")),
            "color_mode": _to_int(s.get("color_mode")),
            "online": self.online,
        }

    def update(self, values: dict) -> None:
        changed = False
        for key, value in values.items():
            if key in self.state and self.state[key] != value:
                self.state[key] = value
                changed = True
        if changed:
            emit({"event": "bulb", "bulb": self.snapshot()})

    def set_online(self, online: bool) -> None:
        if self.online != online:
            self.online = online
            emit({"event": "bulb", "bulb": self.snapshot()})

    # -- commands ------------------------------------------------------------
    def queue(self, method: str, params: list) -> None:
        with self._lock:
            # Replace an unsent command of the same method with the newest value.
            self._pending[method] = params
        self._wake.set()

    def stop(self) -> None:
        self._stop = True
        self._wake.set()

    def _next_id(self) -> int:
        self._msg_id = (self._msg_id % 100000) + 1
        return self._msg_id

    def _send(self, sock: socket.socket, method: str, params: list) -> None:
        msg = {"id": self._next_id(), "method": method, "params": params}
        sock.sendall((json.dumps(msg) + "\r\n").encode())

    def _handle(self, line: str) -> None:
        try:
            msg = json.loads(line)
        except ValueError:
            return
        if msg.get("method") == "props":
            self.update(msg.get("params", {}))
        elif "result" in msg and isinstance(msg["result"], list) and len(msg["result"]) == len(PROPS):
            self.update(dict(zip(PROPS, msg["result"])))
        elif "error" in msg:
            err = msg["error"] or {}
            emit({"event": "error", "ip": self.ip, "message": err.get("message", "error")})

    def _run(self) -> None:
        while not self._stop:
            try:
                sock = socket.create_connection((self.ip, self.port), timeout=4)
            except OSError as e:
                self.set_online(False)
                emit({"event": "error", "ip": self.ip, "message": f"connect failed: {e}"})
                self._wake.wait(RECONNECT_DELAY)
                self._wake.clear()
                continue

            sock.settimeout(None)
            self.set_online(True)
            buf = b""
            last_send = 0.0
            try:
                self._send(sock, "get_prop", PROPS)
                while not self._stop:
                    # Flush coalesced commands, rate-limited.
                    with self._lock:
                        due = bool(self._pending) and time.monotonic() - last_send >= SEND_INTERVAL
                        batch = list(self._pending.items()) if due else []
                        if due:
                            self._pending.clear()
                    for method, params in batch:
                        self._send(sock, method, params)
                        last_send = time.monotonic()

                    with self._lock:
                        waiting = bool(self._pending)
                    timeout = SEND_INTERVAL if waiting else 1.0
                    readable, _, _ = select.select([sock], [], [], timeout)
                    if readable:
                        data = sock.recv(4096)
                        if not data:
                            raise ConnectionError("closed by bulb")
                        buf += data
                        while b"\n" in buf:
                            raw, buf = buf.split(b"\n", 1)
                            line = raw.decode(errors="ignore").strip()
                            if line:
                                self._handle(line)
                    self._wake.clear()
            except (OSError, ConnectionError) as e:
                emit({"event": "error", "ip": self.ip, "message": f"connection lost: {e}"})
            finally:
                try:
                    sock.close()
                except OSError:
                    pass
                self.set_online(False)
            if not self._stop:
                time.sleep(1.0)


class Manager:
    def __init__(self):
        self.bulbs: dict[str, Bulb] = {}
        self.lock = threading.Lock()
        self.sock = self._open_discovery_socket()
        if self.sock:
            threading.Thread(target=self._listen, daemon=True).start()

    # -- bulbs ---------------------------------------------------------------
    def get_or_add(self, ip: str, port: int = CONTROL_PORT) -> Bulb:
        with self.lock:
            bulb = self.bulbs.get(ip)
            if bulb is None:
                bulb = Bulb(ip, port)
                self.bulbs[ip] = bulb
                emit({"event": "bulb", "bulb": bulb.snapshot()})
            return bulb

    def remove(self, ip: str) -> None:
        with self.lock:
            bulb = self.bulbs.pop(ip, None)
        if bulb:
            bulb.stop()

    # -- discovery -----------------------------------------------------------
    def _open_discovery_socket(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            try:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
            except OSError:
                pass
        port = MCAST_PORT
        try:
            # Port 1982 receives both search replies and the bulbs' periodic
            # NOTIFY announcements (open it in the firewall).
            sock.bind(("", MCAST_PORT))
            mreq = struct.pack("4s4s", socket.inet_aton(MCAST_GROUP), socket.inet_aton("0.0.0.0"))
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        except OSError:
            try:
                sock.bind(("", 0))
                port = sock.getsockname()[1]
            except OSError as e:
                emit({"event": "error", "ip": "", "message": f"discovery unavailable: {e}"})
                return None
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        emit({"event": "listening", "port": port})
        return sock

    def discover(self) -> None:
        if not self.sock:
            emit({"event": "discover-done", "count": len(self.bulbs)})
            return
        msg = (
            "M-SEARCH * HTTP/1.1\r\n"
            f"HOST: {MCAST_GROUP}:{MCAST_PORT}\r\n"
            'MAN: "ssdp:discover"\r\n'
            "ST: wifi_bulb\r\n\r\n"
        ).encode()
        try:
            self.sock.sendto(msg, (MCAST_GROUP, MCAST_PORT))
        except OSError as e:
            emit({"event": "error", "ip": "", "message": f"search failed: {e}"})

        def done():
            # Also sweep the local /24 for the control port: outgoing TCP gets
            # through a default firewall that drops the multicast replies.
            self._sweep()
            time.sleep(max(0.0, DISCOVER_WINDOW - SWEEP_TIMEOUT))
            emit({"event": "discover-done", "count": len(self.bulbs)})

        threading.Thread(target=done, daemon=True).start()

    def _sweep(self) -> None:
        local_ip = _local_ipv4()
        if not local_ip:
            return
        prefix = local_ip.rsplit(".", 1)[0]

        def probe(host: int):
            ip = f"{prefix}.{host}"
            if ip == local_ip or ip in self.bulbs:
                return
            s = socket.socket()
            s.settimeout(SWEEP_TIMEOUT)
            try:
                s.connect((ip, CONTROL_PORT))
                # Only bulbs answer get_prop with a result list.
                s.sendall(b'{"id":1,"method":"get_prop","params":["power"]}\r\n')
                s.settimeout(1.0)
                reply = s.recv(512)
                if b'"result"' in reply:
                    self.get_or_add(ip)
            except OSError:
                pass
            finally:
                s.close()

        threads = [threading.Thread(target=probe, args=(h,), daemon=True) for h in range(1, 255)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(SWEEP_TIMEOUT + 1.5)

    def _listen(self) -> None:
        while True:
            try:
                data, _ = self.sock.recvfrom(4096)
            except OSError:
                time.sleep(1)
                continue
            text = data.decode(errors="ignore")
            if not (text.startswith("HTTP/1.1 200") or text.startswith("NOTIFY")):
                continue  # our own M-SEARCH looped back, or noise
            headers = {}
            for line in text.split("\r\n")[1:]:
                if ":" in line:
                    key, value = line.split(":", 1)
                    headers[key.strip().lower()] = value.strip()
            location = headers.get("location", "")
            if not location.startswith("yeelight://"):
                continue
            hostport = location[len("yeelight://"):]
            ip, _, port = hostport.partition(":")
            bulb = self.get_or_add(ip, _to_int(port, CONTROL_PORT))
            if headers.get("id"):
                bulb.id = headers["id"]
            if headers.get("model"):
                bulb.model = headers["model"]
            bulb.update({k: headers[k] for k in PROPS if k in headers})


def main() -> None:
    manager = Manager()
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            cmd = json.loads(raw)
        except ValueError:
            continue
        kind = cmd.get("cmd")
        if kind == "discover":
            manager.discover()
        elif kind == "add" and cmd.get("ip"):
            manager.get_or_add(cmd["ip"].strip())
        elif kind == "remove" and cmd.get("ip"):
            manager.remove(cmd["ip"])
        elif kind == "set" and cmd.get("ip") and cmd.get("method"):
            bulb = manager.bulbs.get(cmd["ip"])
            if bulb:
                bulb.queue(cmd["method"], cmd.get("params", []))
        elif kind == "refresh":
            for bulb in list(manager.bulbs.values()):
                bulb.queue("get_prop", PROPS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
