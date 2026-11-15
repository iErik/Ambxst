pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

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

    // Groups: [{ id, name, members: [ip, …] }], saved in StateService.
    property var groups: []
    // Group ids in order; only reassigned when the set changes, so group
    // cards aren't rebuilt when a member is added or removed.
    property var groupIds: []
    onGroupsChanged: {
        const ids = groups.map(g => g.id);
        if (ids.join(",") !== groupIds.join(","))
            groupIds = ids;
    }
    readonly property string groupsKey: "yeelightGroups"

    property bool discovering: false
    property string lastError: ""
    readonly property bool running: helper.running
    // Module switch (Ambxst > Modules). Off stops the helper.
    readonly property bool enabled: Config.general.moduleYeelight ?? true
    onEnabledChanged: if (!enabled)
        helper.running = false

    readonly property string stateKey: "yeelightBulbs"
    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("../../scripts/yeelight.py").toString().replace("file://", ""))

    function displayName(bulb) {
        if (!bulb)
            return "";
        return bulb.name && bulb.name.length > 0 ? bulb.name : "Bulb " + bulb.ip.split(".").pop();
    }

    // Start the helper (idempotent), re-add remembered bulbs and scan.
    function start() {
        if (!enabled)
            return;
        loadGroups();
        loadScenes();
        if (helper.running)
            return;
        helper.running = true;
    }

    // ── scenes ──────────────────────────────────────────────────────────
    // Built-in scenes. kind: "ct" (white, kelvin), "hsv" (colour) or "flow"
    // (a looping colour flow). Applied with the bulbs' own set_scene, which
    // also turns them on.
    readonly property var builtInScenes: [
        {
            id: "bright",
            name: "Bright",
            kind: "ct",
            ct: 6000,
            bright: 100
        },
        {
            id: "reading",
            name: "Reading",
            kind: "ct",
            ct: 4200,
            bright: 80
        },
        {
            id: "relax",
            name: "Relax",
            kind: "ct",
            ct: 2700,
            bright: 45
        },
        {
            id: "sunset",
            name: "Sunset",
            kind: "hsv",
            hue: 22,
            sat: 90,
            bright: 60
        },
        {
            id: "movie",
            name: "Movie",
            kind: "hsv",
            hue: 235,
            sat: 75,
            bright: 15
        },
        {
            id: "night",
            name: "Night",
            kind: "ct",
            ct: 1700,
            bright: 3
        },
        {
            id: "party",
            name: "Party",
            kind: "flow",
            // duration ms, mode (1 = colour), rgb, brightness; repeated
            flow: "1500,1,16711680,100,1500,1,16744192,100,1500,1,65280,100,1500,1,65535,100,1500,1,255,100,1500,1,16711935,100",
            colors: ["#ff0000", "#ff8000", "#00ff00", "#00ffff", "#0000ff", "#ff00ff"]
        }
    ]

    // Custom scenes: [{ id, name, bulbs: { ip: { power, bright, color_mode,
    // ct, hue, sat, rgb } } }], saved in StateService.
    property var customScenes: []
    readonly property string scenesKey: "yeelightScenes"
    property bool _scenesLoaded: false

    function loadScenes() {
        if (_scenesLoaded || !StateService.initialized)
            return;
        _scenesLoaded = true;
        const saved = StateService.get(scenesKey, []) || [];
        customScenes = saved.filter(sc => sc && sc.id && sc.bulbs);
    }

    function _saveScenes(next) {
        customScenes = next;
        if (StateService.initialized)
            StateService.set(scenesKey, next);
    }

    // Bulbs a scene applies to: a group's members, or every bulb.
    function targetIps(groupId) {
        return groupId ? _members(groupId) : Object.keys(bulbs);
    }

    function applyScene(scene, groupId) {
        if (!scene)
            return;
        const ips = targetIps(groupId);
        if (scene.bulbs) {
            // Custom: restore each bulb it recorded.
            for (const ip of ips) {
                const st = scene.bulbs[ip];
                if (st)
                    _applyState(ip, st);
            }
            return;
        }
        for (const ip of ips)
            _applyState(ip, scene);
    }

    function _applyState(ip, st) {
        if (st.power === false) {
            setPower(ip, false);
            return;
        }
        const kind = st.kind ?? (st.color_mode === 2 ? "ct" : (st.color_mode === 1 ? "rgb" : "hsv"));
        const bright = Math.max(1, Math.min(100, Math.round(st.bright ?? 100)));
        if (kind === "flow") {
            _patch(ip, {
                power: true
            });
            _set(ip, "set_scene", ["cf", 0, 1, st.flow]);
        } else if (kind === "ct") {
            _patch(ip, {
                power: true,
                color_mode: 2,
                ct: st.ct,
                bright: bright
            });
            _set(ip, "set_scene", ["ct", Math.round(st.ct), bright]);
        } else if (kind === "rgb") {
            _patch(ip, {
                power: true,
                color_mode: 1,
                rgb: st.rgb,
                bright: bright
            });
            _set(ip, "set_scene", ["color", st.rgb, bright]);
        } else {
            _patch(ip, {
                power: true,
                color_mode: 3,
                hue: st.hue,
                sat: st.sat,
                bright: bright
            });
            _set(ip, "set_scene", ["hsv", Math.round(st.hue), Math.round(st.sat), bright]);
        }
    }

    // Save the current state of the target bulbs as a new custom scene.
    function saveScene(name, groupId) {
        const recorded = {};
        for (const ip of targetIps(groupId)) {
            const b = bulbs[ip];
            if (!b)
                continue;
            recorded[ip] = {
                power: b.power,
                bright: b.bright,
                color_mode: b.color_mode,
                ct: b.ct,
                hue: b.hue,
                sat: b.sat,
                rgb: b.rgb
            };
        }
        if (Object.keys(recorded).length === 0)
            return "";
        const id = "s" + Date.now().toString(36);
        const n = (name || "").trim() || ("Scene " + (customScenes.length + 1));
        _saveScenes(customScenes.concat([{
                id: id,
                name: n,
                bulbs: recorded
            }]));
        return id;
    }

    function renameScene(id, name) {
        const n = (name || "").trim();
        if (!n)
            return;
        _saveScenes(customScenes.map(sc => sc.id === id ? Object.assign({}, sc, {
                name: n
            }) : sc));
    }

    function deleteScene(id) {
        _saveScenes(customScenes.filter(sc => sc.id !== id));
    }

    // ── groups ──────────────────────────────────────────────────────────
    property bool _groupsLoaded: false
    function loadGroups() {
        if (_groupsLoaded || !StateService.initialized)
            return;
        _groupsLoaded = true;
        const saved = StateService.get(groupsKey, []) || [];
        groups = saved.filter(g => g && g.id).map(g => ({
                    id: g.id,
                    name: g.name || "",
                    members: Array.isArray(g.members) ? g.members : []
                }));
    }

    function _saveGroups(next) {
        groups = next;
        if (StateService.initialized)
            StateService.set(groupsKey, next);
    }

    function group(id) {
        return groups.find(g => g.id === id) ?? null;
    }

    function groupName(g) {
        if (!g)
            return "";
        return g.name && g.name.length > 0 ? g.name : "Group";
    }

    function createGroup(name, members) {
        const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
        const n = (name || "").trim() || ("Group " + (groups.length + 1));
        _saveGroups(groups.concat([{
                id: id,
                name: n,
                members: members || []
            }]));
        return id;
    }

    function renameGroup(id, name) {
        _saveGroups(groups.map(g => g.id === id ? Object.assign({}, g, {
                name: (name || "").trim() || g.name
            }) : g));
    }

    function deleteGroup(id) {
        _saveGroups(groups.filter(g => g.id !== id));
    }

    function toggleMember(id, ip) {
        _saveGroups(groups.map(g => {
            if (g.id !== id)
                return g;
            const members = g.members.indexOf(ip) >= 0 ? g.members.filter(m => m !== ip) : g.members.concat([ip]);
            return Object.assign({}, g, {
                members: members
            });
        }));
    }

    function _members(id) {
        const g = group(id);
        return g ? g.members.filter(ip => !!bulbs[ip]) : [];
    }

    // A group's state, derived from its members: on if any member is on,
    // brightness averaged over the lit members, colour from the first lit
    // member (or the first member).
    function groupState(id) {
        const members = _members(id).map(ip => bulbs[ip]);
        if (members.length === 0)
            return {
                power: false,
                bright: 0,
                ct: 4000,
                rgb: 0,
                hue: 0,
                sat: 0,
                color_mode: 2,
                online: false,
                count: 0
            };
        const lit = members.filter(b => b.power);
        const ref = lit.length > 0 ? lit[0] : members[0];
        const brightOf = lit.length > 0 ? lit : members;
        return {
            power: lit.length > 0,
            bright: Math.round(brightOf.reduce((a, b) => a + b.bright, 0) / brightOf.length),
            ct: ref.ct,
            rgb: ref.rgb,
            hue: ref.hue,
            sat: ref.sat,
            color_mode: ref.color_mode,
            online: members.some(b => b.online),
            count: members.length
        };
    }

    function setGroupPower(id, on) {
        for (const ip of _members(id))
            setPower(ip, on);
    }
    function toggleGroupPower(id) {
        setGroupPower(id, !groupState(id).power);
    }
    function setGroupBrightness(id, value) {
        for (const ip of _members(id))
            setBrightness(ip, value);
    }
    function setGroupColor(id, hue, sat) {
        for (const ip of _members(id))
            setColor(ip, hue, sat);
    }
    function setGroupTemperature(id, kelvin) {
        for (const ip of _members(id))
            setTemperature(ip, kelvin);
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.loadGroups();
            root.loadScenes();
        }
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
        _saveGroups(groups.map(g => Object.assign({}, g, {
                members: g.members.filter(m => m !== ip)
            })));
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
