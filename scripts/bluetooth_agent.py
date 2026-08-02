#!/usr/bin/env python3
"""BlueZ pairing agent for Ambxst.

Registers org.bluez.Agent1 (KeyboardDisplay) and speaks JSON lines on
stdout / stdin so QML can collect PIN/passkey input and confirmations.
"""

from __future__ import annotations

import json
import sys
import threading
from typing import Any, Callable, Optional

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

AGENT_PATH = "/org/ambxst/bluetooth_agent"
AGENT_IFACE = "org.bluez.Agent1"
AGENT_MANAGER_IFACE = "org.bluez.AgentManager1"
CAPABILITY = "KeyboardDisplay"


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Canceled(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Canceled"


def emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def device_info(bus: dbus.SystemBus, path: str) -> dict[str, str]:
    info = {"path": str(path), "address": "", "name": "Unknown device"}
    try:
        props = dbus.Interface(
            bus.get_object("org.bluez", path), "org.freedesktop.DBus.Properties"
        )
        data = props.GetAll("org.bluez.Device1")
        info["address"] = str(data.get("Address", "") or "")
        alias = data.get("Alias") or data.get("Name") or info["address"] or "Unknown device"
        info["name"] = str(alias)
    except Exception:
        pass
    return info


class Agent(dbus.service.Object):
    def __init__(self, bus: dbus.SystemBus) -> None:
        self.bus = bus
        self._next_id = 1
        self._pending: dict[int, dict[str, Any]] = {}
        dbus.service.Object.__init__(self, bus, AGENT_PATH)

    def _request(
        self,
        kind: str,
        device: str,
        *,
        code: str = "",
        entered: int = 0,
        ok: Optional[Callable[[Any], None]] = None,
        err: Optional[Callable[[Exception], None]] = None,
        needs_reply: bool = True,
        numeric: bool = False,
    ) -> int:
        req_id = self._next_id
        self._next_id += 1
        info = device_info(self.bus, device)
        if needs_reply:
            self._pending[req_id] = {
                "ok": ok,
                "err": err,
                "kind": kind,
                "needs_reply": needs_reply,
                "numeric": numeric,
            }
        payload = {
            "event": "request",
            "id": req_id,
            "kind": kind,
            "devicePath": info["path"],
            "address": info["address"],
            "name": info["name"],
            "code": code,
            "entered": entered,
            "needsReply": needs_reply,
            "numeric": numeric,
        }
        emit(payload)
        return req_id

    def handle_response(self, message: dict[str, Any]) -> None:
        req_id = message.get("id")
        if req_id is None:
            return
        try:
            req_id = int(req_id)
        except (TypeError, ValueError):
            return

        pending = self._pending.pop(req_id, None)
        if not pending:
            return

        action = (message.get("action") or "").strip().lower()
        ok = pending.get("ok")
        err = pending.get("err")
        kind = pending.get("kind")
        numeric = pending.get("numeric")

        if action in ("reject", "cancel"):
            if err:
                err(Rejected("Rejected") if action == "reject" else Canceled("Canceled"))
            return

        if action == "confirm":
            if ok:
                ok()
            return

        if action == "submit":
            value = str(message.get("value", ""))
            if not value:
                if err:
                    err(Rejected("Empty response"))
                return
            if kind == "passkey" or numeric:
                try:
                    if ok:
                        ok(dbus.UInt32(int(value)))
                except ValueError:
                    if err:
                        err(Rejected("Invalid passkey"))
                return
            if ok:
                ok(value)
            return

        if err:
            err(Rejected("Unknown action"))

    def cancel_all(self, reason: str = "Canceled") -> None:
        pending = list(self._pending.items())
        self._pending.clear()
        for req_id, entry in pending:
            emit({"event": "cancel", "id": req_id, "reason": reason})
            err = entry.get("err")
            if err:
                try:
                    err(Canceled(reason))
                except Exception:
                    pass

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self) -> None:
        self.cancel_all("Released")
        emit({"event": "released"})

    @dbus.service.method(
        AGENT_IFACE,
        in_signature="o",
        out_signature="s",
        async_callbacks=("ok", "err"),
    )
    def RequestPinCode(self, device, ok, err) -> None:
        self._request("pin", device, ok=ok, err=err, needs_reply=True, numeric=False)

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode) -> None:
        self._request(
            "display_pin",
            device,
            code=str(pincode),
            needs_reply=False,
        )

    @dbus.service.method(
        AGENT_IFACE,
        in_signature="o",
        out_signature="u",
        async_callbacks=("ok", "err"),
    )
    def RequestPasskey(self, device, ok, err) -> None:
        self._request("passkey", device, ok=ok, err=err, needs_reply=True, numeric=True)

    @dbus.service.method(AGENT_IFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered) -> None:
        self._request(
            "display_passkey",
            device,
            code=f"{int(passkey):06d}",
            entered=int(entered),
            needs_reply=False,
        )

    @dbus.service.method(
        AGENT_IFACE,
        in_signature="ou",
        out_signature="",
        async_callbacks=("ok", "err"),
    )
    def RequestConfirmation(self, device, passkey, ok, err) -> None:
        self._request(
            "confirm",
            device,
            code=f"{int(passkey):06d}",
            ok=ok,
            err=err,
            needs_reply=True,
        )

    @dbus.service.method(
        AGENT_IFACE,
        in_signature="o",
        out_signature="",
        async_callbacks=("ok", "err"),
    )
    def RequestAuthorization(self, device, ok, err) -> None:
        self._request("authorize", device, ok=ok, err=err, needs_reply=True)

    @dbus.service.method(
        AGENT_IFACE,
        in_signature="os",
        out_signature="",
        async_callbacks=("ok", "err"),
    )
    def AuthorizeService(self, device, uuid, ok, err) -> None:
        # Auto-accept service authorization; pairing PIN/confirm still goes through UI.
        try:
            ok()
        except Exception:
            if err:
                err(Rejected("AuthorizeService failed"))

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self) -> None:
        self.cancel_all("Canceled by BlueZ")


def stdin_loop(agent: Agent, loop: GLib.MainLoop) -> None:
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            emit({"event": "error", "message": "Invalid JSON on stdin"})
            continue

        if message.get("action") == "quit":
            GLib.idle_add(loop.quit)
            return

        GLib.idle_add(agent.handle_response, message)


def main() -> int:
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    try:
        bus = dbus.SystemBus()
    except Exception as exc:
        emit({"event": "error", "message": f"System bus unavailable: {exc}"})
        return 1

    agent = Agent(bus)
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), AGENT_MANAGER_IFACE)

    try:
        manager.RegisterAgent(AGENT_PATH, CAPABILITY)
    except dbus.DBusException as exc:
        emit({"event": "error", "message": f"RegisterAgent failed: {exc}"})
        return 1

    default_ok = True
    try:
        manager.RequestDefaultAgent(AGENT_PATH)
    except dbus.DBusException as exc:
        default_ok = False
        emit(
            {
                "event": "warning",
                "message": f"Could not become default agent (another agent may own pairing): {exc}",
            }
        )

    emit({"event": "ready", "defaultAgent": default_ok, "capability": CAPABILITY})

    loop = GLib.MainLoop()
    thread = threading.Thread(target=stdin_loop, args=(agent, loop), daemon=True)
    thread.start()

    try:
        loop.run()
    finally:
        agent.cancel_all("Agent exiting")
        try:
            manager.UnregisterAgent(AGENT_PATH)
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
