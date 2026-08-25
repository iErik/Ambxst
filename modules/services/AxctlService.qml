pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var focusedMonitor: null
    property var focusedWorkspace: null
    property var focusedClient: null

    property int focusHistoryCounter: 0

    property QtObject clients: QtObject {
        property var values: []
    }

    property QtObject monitors: QtObject {
        property var values: []
    }

    property QtObject workspaces: QtObject {
        property var values: []
    }

    signal rawEvent(var event)

    // Config path for axctl daemon
    property string configPath: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/ambxst/axctl.toml"

    // Compositor identity / capabilities. Env is the instant bootstrap; axctl
    // `system get-capabilities` confirms and fills the feature mask.
    property string compositorId: {
        if (Quickshell.env("NIRI_SOCKET"))
            return "niri";
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
            return "hyprland";
        return "unknown";
    }
    property bool capabilitiesReady: false
    property var capabilities: ({})
    readonly property bool isNiri: compositorId === "niri"
    readonly property bool isHyprland: compositorId === "hyprland"
    readonly property bool supportsLayoutSwitch: capabilitiesReady ? capabilities.layout_switch === true : isHyprland
    readonly property bool supportsBlur: capabilitiesReady ? capabilities.blur === true : !isNiri
    readonly property bool supportsSpecialWorkspace: capabilitiesReady ? capabilities.special_workspaces === true : isHyprland
    readonly property bool supportsInnerOuterGaps: capabilitiesReady ? capabilities.inner_outer_gaps !== false : !isNiri
    readonly property var availableLayouts: (capabilities.layouts && capabilities.layouts.length) ? capabilities.layouts : (isNiri ? [] : ["dwindle", "master", "scrolling"])
    readonly property var shadowCaps: capabilities.shadow || ({
        enabled: true,
        size: true,
        color: true,
        offset: true,
        render_power: isHyprland,
        scale: isHyprland,
        sharp: isHyprland,
        ignore_window: isHyprland
    })

    function applyCapabilities(caps) {
        if (!caps || typeof caps !== "object")
            return;
        if (caps.id)
            compositorId = String(caps.id);
        capabilities = caps;
        capabilitiesReady = true;
    }

    function defaultCapabilitiesFor(id) {
        if (id === "niri") {
            return {
                id: "niri",
                layouts: [],
                layout_switch: false,
                blur: false,
                shadows: true,
                shadow: {
                    enabled: true, size: true, color: true, offset: true,
                    render_power: false, scale: false, sharp: false, ignore_window: false
                },
                animations: true,
                rounded_corners: true,
                workspaces_supported: true,
                windows_supported: true,
                special_workspaces: false,
                inner_outer_gaps: false
            };
        }
        return {
            id: id || "hyprland",
            layouts: ["dwindle", "master", "scrolling"],
            layout_switch: true,
            blur: true,
            shadows: true,
            shadow: {
                enabled: true, size: true, color: true, offset: true,
                render_power: true, scale: true, sharp: true, ignore_window: true
            },
            animations: true,
            rounded_corners: true,
            workspaces_supported: true,
            windows_supported: true,
            special_workspaces: true,
            inner_outer_gaps: true
        };
    }

    function switchRelativeWorkspace(delta) {
        const values = root.workspaces.values || [];
        const focusedMon = root.focusedMonitor;
        const monName = focusedMon ? (focusedMon.name || "") : "";
        let list = values.filter(ws => {
            if (root.isNiri && monName)
                return String(ws.monitor) === String(monName) || String(ws.monitor) === String(focusedMon.id);
            return true;
        });
        if (!list.length)
            list = values.slice();
        list.sort((a, b) => (a.id || 0) - (b.id || 0));
        if (!list.length)
            return;
        const currentId = root.focusedWorkspace ? root.focusedWorkspace.id : list[0].id;
        let idx = list.findIndex(ws => ws.id === currentId);
        if (idx < 0)
            idx = 0;
        const next = list[(idx + delta + list.length) % list.length];
        if (next)
            root.dispatch("workspace " + next.id);
    }

    function dispatch(command) {
        if (!command) return;

        let spaceIdx = command.indexOf(' ');
        let action = spaceIdx !== -1 ? command.substring(0, spaceIdx).trim() : command.trim();
        let rawArgs = spaceIdx !== -1 ? command.substring(spaceIdx + 1).trim() : "";

        let getAddr = (str) => {
            let m = str.match(/address:([^\s,]+)/);
            return m ? m[1] : str.trim();
        };

        let cmdArgs = [];

        if (action === "workspace") {
            const rel = String(rawArgs).trim();
            if (rel === "r+1" || rel === "e+1" || rel === "+1" || rel === "m+1") {
                root.switchRelativeWorkspace(1);
                return;
            }
            if (rel === "r-1" || rel === "e-1" || rel === "-1" || rel === "m-1") {
                root.switchRelativeWorkspace(-1);
                return;
            }
            cmdArgs = ["workspace", "switch", rawArgs];
        } else if (action === "closewindow") {
            cmdArgs = ["window", "close", getAddr(rawArgs)];
        } else if (action === "focuswindow") {
            cmdArgs = ["window", "focus", getAddr(rawArgs)];
        } else if (action === "movetoworkspacesilent") {
            let subParts = rawArgs.split(',');
            cmdArgs = ["window", "move-to-workspace-silent", subParts[0].trim()];
            if (subParts.length > 1) {
                cmdArgs.push(getAddr(subParts[1]));
            }
        } else if (action === "focusmonitor") {
            cmdArgs = ["monitor", "focus", rawArgs];
        } else if (action === "togglespecialworkspace") {
            if (root.isNiri)
                return;
            cmdArgs = ["workspace", "toggle-special"];
            if (rawArgs) cmdArgs.push(rawArgs);
        } else if (action === "movewindowpixel") {
            if (root.isNiri)
                return;
            cmdArgs = ["system", "execute", command];
        } else {
            cmdArgs = ["system", "execute", command];
        }

        let finalCommand = ["axctl"].concat(cmdArgs.filter(x => x !== "" && x !== undefined));

        let proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        proc.command = finalCommand;
        proc.onExited.connect(() => proc.destroy());
        proc.running = true;
    }

    // Switch/focus without warping the pointer.
    //
    // Important: do NOT "save cursor → act → restore". That causes a visible
    // twitch (and fights the user if they move the mouse right after click).
    // On Hyprland 0.56+ (Lua config), use dispatchers that leave the cursor alone.
    function switchWorkspacePreserveCursor(workspaceId) {
        if (workspaceId === undefined || workspaceId === null || workspaceId === "")
            return;
        const ws = String(workspaceId);
        let proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
            // hl.dsp.focus({ workspace }) switches without restoring last-ws cursor.
            proc.command = [
                "bash", "-c",
                `hyprctl repl 'hl.dispatch(hl.dsp.focus({ workspace = "${ws}" }))' >/dev/null 2>&1 || axctl workspace switch "${ws}"`
            ];
        } else {
            proc.command = ["axctl", "workspace", "switch", ws];
        }
        proc.onExited.connect(() => proc.destroy());
        proc.running = true;
    }

    // Focus a window without warping into it. Optional workspaceId avoids a
    // cross-workspace focus warp by switching the workspace first (no-warp),
    // then focusing under cursor:no_warps.
    function focusWindowPreserveCursor(address, workspaceId) {
        if (!address)
            return;
        let addr = String(address).replace(/^address:/, "");
        let ws = workspaceId !== undefined && workspaceId !== null && workspaceId !== ""
            ? String(workspaceId)
            : "";
        if (!ws) {
            let clients = root.clients.values || [];
            for (let i = 0; i < clients.length; i++) {
                if (clients[i].address === addr) {
                    ws = String(clients[i].workspace?.id || "");
                    break;
                }
            }
        }

        let proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
            proc.command = [
                "bash", "-c",
                (ws ? `hyprctl repl 'hl.dispatch(hl.dsp.focus({ workspace = "${ws}" }))' >/dev/null 2>&1 || true\n` : "") +
                'hyprctl repl \'hl.config({ cursor = { no_warps = true } })\' >/dev/null 2>&1 || true\n' +
                `hyprctl repl 'hl.dispatch(hl.dsp.focus({ window = "${addr}" }))' >/dev/null 2>&1 || axctl window focus "${addr}" >/dev/null 2>&1 || true\n` +
                'hyprctl repl \'hl.config({ cursor = { no_warps = false } })\' >/dev/null 2>&1 || true\n'
            ];
        } else {
            proc.command = ["axctl", "window", "focus", addr];
        }
        proc.onExited.connect(() => proc.destroy());
        proc.running = true;
    }

    // Focus a window and warp the pointer into it (Alt-Tab / task switcher).
    // Prefer axctl: on Hyprland it focuses and warps reliably across app types.
    function focusWindow(address, workspaceId) {
        if (!address)
            return;
        let addr = String(address).replace(/^address:/, "");
        let proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        // workspaceId accepted for API symmetry with PreserveCursor; axctl focus
        // switches as needed and warps to the window center.
        proc.command = ["axctl", "window", "focus", addr];
        proc.onExited.connect(() => proc.destroy());
        proc.running = true;
    }

    function monitorFor(screen) {
        if (!screen) return null;
        let screenName = screen.name || screen;
        let values = root.monitors.values || [];
        for (let i = 0; i < values.length; i++) {
            if (values[i].name === screenName) return values[i];
        }
        return null;
    }

    function applyState(state) {
        if (!state) return;

        // --- Windows ---
        if (state.windows) {
            let existingClients = root.clients.values || [];
            let mappedClients = state.windows.map(win => {
                let existing = existingClients.find(c => c.address === win.id);
                let prevFocus = existing && existing.focusHistoryID !== undefined ? existing.focusHistoryID : 999999;
                let newFocus = win.is_focused ? (existing && existing.is_focused ? prevFocus : --root.focusHistoryCounter) : prevFocus;
                return {
                    address: win.id,
                    class: win.app_id,
                    title: win.title,
                    workspace: { id: parseInt(win.workspace_id) || 0, name: win.workspace_id },
                    monitor: parseInt(win.metadata ? win.metadata.monitor_id : 0) || 0,
                    floating: win.is_floating,
                    fullscreen: win.is_fullscreen,
                    hidden: win.is_hidden,
                    mapped: true,
                    at: [win.metadata ? (win.metadata.x || 0) : 0, win.metadata ? (win.metadata.y || 0) : 0],
                    size: [win.metadata ? (win.metadata.width || 100) : 100, win.metadata ? (win.metadata.height || 100) : 100],
                    xwayland: (win.metadata ? win.metadata.xwayland : false) || false,
                    is_focused: win.is_focused || false,
                    focusHistoryID: newFocus
                };
            });
            root.clients.values = mappedClients;
            let focused = mappedClients.find(w => w.address === (root.focusedClient ? root.focusedClient.address : undefined)) || mappedClients.find(w => w.is_focused) || null;
            if (focused !== root.focusedClient) {
                root.focusedClient = focused;
            }
        }

        // --- Workspaces ---
        if (state.workspaces) {
            let mappedWorkspaces = state.workspaces.map(ws => ({
                id: parseInt(ws.id) || 0,
                name: ws.name,
                monitor: ws.monitor_id,
                active: ws.is_active,
                windows: 0
            }));
            root.workspaces.values = mappedWorkspaces;
            let focused = mappedWorkspaces.find(ws => ws.active) || null;
            if (focused !== root.focusedWorkspace) {
                root.focusedWorkspace = focused;
            }
        }

        // --- Monitors ---
        if (state.monitors) {
            let mappedMonitors = state.monitors.map(mon => ({
                id: parseInt(mon.id) || 0,
                name: mon.name,
                focused: mon.is_focused,
                width: mon.width,
                height: mon.height,
                refreshRate: mon.refresh_rate,
                scale: mon.scale,
                // Layout position / rotation — required by Overview window placement
                x: mon.metadata ? (mon.metadata.x || 0) : 0,
                y: mon.metadata ? (mon.metadata.y || 0) : 0,
                transform: mon.metadata ? (mon.metadata.transform || 0) : 0,
                activeWorkspace: { id: parseInt(mon.metadata ? mon.metadata.active_workspace : 0) || 0, name: mon.metadata ? mon.metadata.active_workspace : "" }
            }));
            root.monitors.values = mappedMonitors;
            let focused = mappedMonitors.find(m => m.focused) || null;
            if (focused !== root.focusedMonitor) {
                root.focusedMonitor = focused;
            }
        }
    }

    property Process ensureConfigDir: Process {
        command: ["mkdir", "-p", (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/ambxst"]
        running: true
    }

    property Process axctlProcess: Process {
        command: ["axctl", "-c", root.configPath, "daemon"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                // Daemon logs can be printed here if needed
            }
        }
        onExited: (code) => {
            console.warn("axctl daemon exited with code:", code);
            // Another instance may already own the socket (common after messy
            // reloads). Prefer re-subscribing over restarting into a crash loop.
            if (!reconnectTimer.running)
                reconnectTimer.restart();
        }
    }

    Timer {
        id: subscribeDelay
        interval: 500
        running: true
        onTriggered: {
            axctlSubscribe.running = true;
            if (!root.capabilitiesReady)
                root.applyCapabilities(root.defaultCapabilitiesFor(root.compositorId));
            capabilitiesProcess.running = true;
        }
    }

    property Process capabilitiesProcess: Process {
        command: ["axctl", "system", "get-capabilities"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.applyCapabilities(parsed);
                } catch (e) {
                    console.warn("AxctlService: get-capabilities failed, using env defaults:", e);
                    if (!root.capabilitiesReady)
                        root.applyCapabilities(root.defaultCapabilitiesFor(root.compositorId));
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && !root.capabilitiesReady)
                root.applyCapabilities(root.defaultCapabilitiesFor(root.compositorId));
        }
    }

    // Auto-reconnect on unexpected subscribe/daemon exit.
    // Only relaunch the daemon if subscribe keeps failing and no daemon is alive.
    property int _subscribeFailCount: 0
    Timer {
        id: reconnectTimer
        interval: 1000
        onTriggered: {
            root._subscribeFailCount += 1;
            if (!axctlProcess.running && root._subscribeFailCount >= 2) {
                console.warn("axctl: relaunching daemon after repeated subscribe failures");
                root._subscribeFailCount = 0;
                axctlProcess.running = true;
                subscribeDelay.restart();
            } else {
                axctlSubscribe.running = true;
            }
        }
    }

    property Process axctlSubscribe: Process {
        command: ["axctl", "subscribe"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                if (!data) return;
                try {
                    let parsedJson = JSON.parse(data);

                    // Successful traffic — reset fail streak
                    root._subscribeFailCount = 0;

                    // Apply inline state immediately (every event carries full state)
                    if (parsedJson.state) {
                        root.applyState(parsedJson.state);
                    }

                    // Emit raw event for consumers
                    parsedJson.name = parsedJson.method ? parsedJson.method.split('.').pop().toLowerCase() : "";
                    parsedJson.data = parsedJson.params;
                    root.rawEvent(parsedJson);
                } catch (e) {
                    console.error("AxctlService subscribe JSON parse error:", e);
                }
            }
        }
        onExited: (code) => {
            console.warn("axctl subscribe exited:", code);
            reconnectTimer.restart();
        }
    }

    Component.onDestruction: {
        reconnectTimer.running = false
        subscribeDelay.running = false
        axctlProcess.running = false
        axctlSubscribe.running = false
    }
}
