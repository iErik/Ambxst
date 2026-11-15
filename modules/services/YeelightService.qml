pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Yeelight bulbs over the LAN protocol (no cloud), via scripts/yeelight.py.
// The helper is started the first time the Lights page is shown and keeps one
// connection per bulb, pushing state changes (including ones made from the
// phone app). Bulbs need "LAN Control" enabled in the Yeelight app.
Singleton {
    id: root

    // ip -> { ip, id, model, name, power, bright, ct, rgb, hue, sat,
    //          color_mode (1 rgb, 2 white/ct, 3 hsv), online }
    property var bulbs: ({})
    readonly property var bulbList: {
        const list = Object.values(bulbs);
        list.sort((a, b) => root.displayName(a).localeCompare(root.displayName(b), undefined, {
                numeric: true
            }));
        return list;
    }
    // Bulb IPs in display order. Only reassigned when the set or order
    // changes, so views keyed on it don't rebuild on every state update.
    property var bulbIps: []
    onBulbsChanged: {
        const ips = bulbList.map(b => b.ip);
        if (ips.join(",") !== bulbIps.join(","))
            bulbIps = ips;
    }

    property bool discovering: false
    property string lastError: ""
    readonly property bool running: helper.running

    readonly property string stateKey: "yeelightBulbs"
    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("../../scripts/yeelight.py").toString().replace("file://", ""))

    function displayName(bulb) {
        if (!bulb)
            return "";
        return bulb.name && bulb.name.length > 0 ? bulb.name : "Bulb " + bulb.ip.split(".").pop();
    }

    // Start the helper (idempotent), re-add remembered bulbs and scan.
    function start() {
        if (helper.running)
            return;
        helper.running = true;
    }

    function discover() {
        start();
        discovering = true;
        send({
            cmd: "discover"
        });
    }

    function addIp(ip) {
        const value = (ip || "").trim();
        if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(value)) {
            lastError = "Not an IPv4 address: " + value;
            return;
        }
        start();
        send({
            cmd: "add",
            ip: value
        });
    }

    function forget(ip) {
        send({
            cmd: "remove",
            ip: ip
        });
        const next = Object.assign({}, bulbs);
        delete next[ip];
        bulbs = next;
        persist();
    }

    function setPower(ip, on) {
        _patch(ip, {
            power: on
        });
        _set(ip, "set_power", [on ? "on" : "off", "smooth", 300]);
    }

    function togglePower(ip) {
        const b = bulbs[ip];
        if (b)
            setPower(ip, !b.power);
    }

    function setAllPower(on) {
        for (const ip of Object.keys(bulbs))
            setPower(ip, on);
    }

    function setBrightness(ip, value) {
        const v = Math.max(1, Math.min(100, Math.round(value)));
        _ensureOn(ip);
        _patch(ip, {
            bright: v
        });
        _set(ip, "set_bright", [v, "smooth", 200]);
    }

    // hue 0-359, sat 0-100
    function setColor(ip, hue, sat) {
        const h = Math.max(0, Math.min(359, Math.round(hue)));
        const s = Math.max(0, Math.min(100, Math.round(sat)));
        _ensureOn(ip);
        _patch(ip, {
            hue: h,
            sat: s,
            color_mode: 3
        });
        _set(ip, "set_hsv", [h, s, "smooth", 200]);
    }

    // kelvin 1700-6500
    function setTemperature(ip, kelvin) {
        const k = Math.max(1700, Math.min(6500, Math.round(kelvin)));
        _ensureOn(ip);
        _patch(ip, {
            ct: k,
            color_mode: 2
        });
        _set(ip, "set_ct_abx", [k, "smooth", 200]);
    }

    function rename(ip, name) {
        const n = (name || "").trim();
        _patch(ip, {
            name: n
        });
        _set(ip, "set_name", [n]);
    }

    // ── internals ───────────────────────────────────────────────────────
    function send(obj) {
        if (helper.running)
            helper.write(JSON.stringify(obj) + "\n");
    }

    function _set(ip, method, params) {
        send({
            cmd: "set",
            ip: ip,
            method: method,
            params: params
        });
    }

    function _ensureOn(ip) {
        const b = bulbs[ip];
        if (b && !b.power)
            setPower(ip, true);
    }

    // Optimistic local update so the UI responds at once; the bulb confirms
    // through its own state notifications.
    function _patch(ip, values) {
        const b = bulbs[ip];
        if (!b)
            return;
        const next = Object.assign({}, bulbs);
        next[ip] = Object.assign({}, b, values);
        bulbs = next;
    }

    function persist() {
        if (StateService.initialized)
            StateService.set(stateKey, Object.keys(bulbs));
    }

    function _onEvent(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        switch (msg.event) {
        case "bulb":
            {
                const b = msg.bulb;
                const known = !!bulbs[b.ip];
                const next = Object.assign({}, bulbs);
                next[b.ip] = b;
                bulbs = next;
                if (!known)
                    persist();
                break;
            }
        case "discover-done":
            discovering = false;
            break;
        case "error":
            lastError = msg.message || "";
            break;
        }
    }

    Process {
        id: helper
        command: ["python3", "-u", root.scriptPath]
        stdinEnabled: true
        running: false

        stdout: SplitParser {
            onRead: data => root._onEvent(data)
        }

        stderr: SplitParser {
            onRead: data => console.warn("yeelight:", data)
        }

        onRunningChanged: {
            if (running) {
                const remembered = StateService.get(root.stateKey, []) || [];
                for (const ip of remembered)
                    root.send({
                        cmd: "add",
                        ip: ip
                    });
                root.discover();
            } else {
                root.discovering = false;
            }
        }
    }
}
